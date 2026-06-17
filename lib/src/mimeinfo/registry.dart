// Copyright 2026 The Authors. See the AUTHORS file for details.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert' show utf8, jsonEncode;
import 'dart:typed_data' show Uint8List;

import 'package:collection/collection.dart';
import 'package:xml/xml.dart' show XmlDocument, XmlName;

import 'base.dart' show MatchList, MatchResult, RegistryEntry;
import 'glob_index.dart' show GlobIndex;

/// A map from canonical media type string to its list of [RegistryEntry]
/// instances (typically one per type, but may be more when a type has multiple
/// independent glob/magic/rootXML rule sets).
typedef Registry = Map<String, List<RegistryEntry>>;

/// An empty [Registry], useful as a placeholder when the generated database
/// files need to be regenerated from scratch. See `mediatype_detector_base.dart`
/// for the swap-in instructions.
const Registry emptyRegistry = {};

/// Abstract base for a MIME type registry.
///
/// Owns the detection pipeline ([detect]), plus the individual strategy methods
/// ([matchGlob], [matchMagic], [matchRootXML]) that callers can invoke
/// directly when they only need one stage.
///
/// The two bundled concrete registries (`TikaMimeInfoRegistry`,
/// `FreedesktopMimeInfoRegistry`) extend this class with their generated
/// databases. To build a custom registry, extend this class and pass your own
/// [Registry] map to the constructor.
///
/// ```dart
/// class MyRegistry extends MimeInfoRegistry {
///   MyRegistry() : super(const {'text/x-myformat': [...]});
/// }
/// ```
abstract class MimeInfoRegistry {
  final Map<String, List<RegistryEntry>> _entries;

  /// Lazily-built index for fast glob lookups by file extension.
  final GlobIndex _globIndex;

  /// Creates a new instance of the [MimeInfoRegistry].
  ///
  /// Since the underlying database is generated and global, instances of
  /// [MimeInfoRegistry] share the same underlying immutable map of entries.
  MimeInfoRegistry(Map<String, List<RegistryEntry>> entries)
    : _entries = UnmodifiableMapView(entries),
      _globIndex = GlobIndex(entries);

  Map<String, List<Map<String, dynamic>>> toMap() {
    return _entries.map(
      (key, entries) => MapEntry(key, [for (final e in entries) e.toMap()]),
    );
  }

  Iterable<RegistryEntry> _flattenedEntries = [];

  /// All [RegistryEntry] instances in the registry as a flat iterable.
  ///
  /// Lazily built on first access and cached. Used internally by [matchMagic]
  /// and [matchRootXML], which must scan every entry.
  Iterable<RegistryEntry> get flattenedEntries {
    if (_flattenedEntries.isEmpty) {
      _flattenedEntries = _entries.values.flattened;
    }

    return _flattenedEntries;
  }

  @override
  String toString() => jsonEncode(toMap());

  /// Detects the media type of a file using all three strategies.
  ///
  /// Pass [bytes] for magic and root XML matching, [fileName] for glob
  /// matching, or both for the highest-confidence result. [fileName] must be a
  /// bare filename (e.g. `document.pdf`), not a full path — extract the
  /// basename with `path.basename` before calling if needed.
  ///
  /// Per the Freedesktop shared-mime-info specification:
  /// - Root XML results are definitive when present.
  /// - Magic results take precedence over glob results.
  /// - A type confirmed by both magic and glob is promoted to the top.
  ///
  /// Returns a [MatchList] containing per-strategy results and a
  /// conflict-resolved [MatchList.merged] list.
  MatchList detect({
    Uint8List? bytes,
    String? fileName,
    bool caseSensitive = false,
  }) {
    List<MatchResult>? globMatches;
    List<MatchResult>? magicMatches;
    List<MatchResult>? rootXmlMatches;

    // Step 1: Glob match on the file name.
    globMatches = (fileName != null)
        ? matchGlob(fileName, caseSensitive: caseSensitive)
        : null;

    // Step 2: Magic matching.
    magicMatches = (bytes != null) ? matchMagic(bytes) : null;

    // Step 3: Root XML matching (only if magic or glob suggest XML).
    if (isLikelyXml(globMatches, magicMatches)) {
      rootXmlMatches = (bytes != null) ? matchRootXML(bytes) : [];
    } else {
      rootXmlMatches = null;
    }

    return MatchList(
      rootXmlMatches: rootXmlMatches,
      magicMatches: magicMatches,
      globMatches: globMatches,
    );
  }

  /// The number of media type entries in the registry.
  int get length => _entries.length;

  /// Whether the registry contains an entry for the given [mediaType] string.
  bool contains(String mediaType) => _entries.containsKey(mediaType);

  /// Returns `true` if the current glob or magic results suggest an XML-based
  /// format, indicating that [matchRootXML] should be run.
  ///
  /// A file is considered likely XML when any match declares a media type
  /// whose subtype ends in `+xml`, whose top-level type is `xml`, or which
  /// is a subclass of `application/xml`.
  bool isLikelyXml(
    List<MatchResult>? globMatches,
    List<MatchResult>? magicMatches,
  ) {
    /// Whether this media type is effectively an XML-based format.
    bool isXml(String mediaType) {
      final tokens = mediaType.split('/');
      return (tokens[0] == 'xml' || tokens[1].endsWith('+xml'));
    }

    return ((globMatches?.any(
              (m) => m.subclassOf.contains('application/xml'),
            ) ??
            false) ||
        (magicMatches?.any((m) => m.subclassOf.contains('application/xml')) ??
            false) ||
        (globMatches?.any((m) => isXml(m.mediaType)) ?? false) ||
        (magicMatches?.any((m) => isXml(m.mediaType)) ?? false));
  }

  /// Returns all media types whose glob patterns match [fileName], ordered by
  /// weight descending.
  ///
  /// [fileName] must be a bare filename (e.g. `document.pdf`), not a full
  /// path. Simple `*.ext` patterns are resolved via a pre-built extension
  /// index in O(1); complex patterns (e.g. `README*`, `*.tar.gz`) are checked
  /// with a linear scan. Duplicate types are removed.
  List<MatchResult> matchGlob(String fileName, {bool caseSensitive = false}) {
    final matches = <MatchResult>[];

    // Fast path: look up by file extension(s).
    // We check progressively shorter extensions (e.g. "tar.gz" then "gz")
    // to catch compound extensions like *.tar.gz.
    final lowerName = fileName.toLowerCase();
    final dotIndex = lowerName.indexOf('.');
    if (dotIndex != -1 && dotIndex < lowerName.length - 1) {
      var remaining = lowerName.substring(dotIndex + 1);
      while (remaining.isNotEmpty) {
        final indexed = _globIndex.byExtension[remaining];
        if (indexed != null) {
          for (final entry in indexed) {
            if (entry.glob.matches(fileName, caseSensitive: caseSensitive)) {
              matches.add(
                MatchResult(
                  priority: entry.glob.weight,
                  entry: entry.registryEntry,
                ),
              );
            }
          }
        }
        //if (matches.isNotEmpty) {
        //  break;
        //}
        final nextDot = remaining.indexOf('.');
        if (nextDot == -1) break;
        remaining = remaining.substring(nextDot + 1);
      }
    }

    // Slow path: check complex patterns that can't be indexed by extension.
    for (final pattern in _globIndex.complexPatterns) {
      if (pattern.glob.matches(fileName, caseSensitive: caseSensitive)) {
        matches.add(
          MatchResult(
            priority: pattern.glob.weight,
            entry: pattern.registryEntry,
          ),
        );
      }
    }

    matches.sort((a, b) => b.priority.compareTo(a.priority));
    return matches.toSet().toList();
  }

  /// Returns all media types whose magic rules match [bytes], ordered by
  /// priority descending. Duplicate types are removed.
  List<MatchResult> matchMagic(Uint8List bytes) {
    final matches = <MatchResult>[];
    for (final entry in flattenedEntries) {
      matches.addAll(entry.matchesMagic(bytes));
    }
    matches.sort((a, b) => b.priority.compareTo(a.priority));
    return matches.toSet().toList();
  }

  /// Returns all media types whose root XML rules match the root element of
  /// [bytes], ordered by priority descending.
  ///
  /// [bytes] is parsed as UTF-8 XML once; the root element's local name and
  /// namespace are checked against every registered [RootXML] rule. Returns an
  /// empty list if [bytes] cannot be parsed as XML. Duplicate types are removed.
  List<MatchResult> matchRootXML(Uint8List bytes) {
    // Parse the XML file once at this level.
    final XmlName rootName;
    try {
      final document = XmlDocument.parse(utf8.decode(bytes));
      rootName = document.rootElement.name;
    } catch (_) {
      return [];
    }

    final matches = <MatchResult>[];
    for (final entry in flattenedEntries) {
      if (entry.rootXML.isNotEmpty) {
        for (final rule in entry.rootXML) {
          if (rule.matchesElement(rootName)) {
            matches.add(MatchResult(priority: rule.weight, entry: entry));
          }
        }
      }
    }
    matches.sort((a, b) => b.priority.compareTo(a.priority));
    return matches.toSet().toList();
  }
}
