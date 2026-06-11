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

import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:betto_common/string.dart' show IntlString;
import 'package:collection/collection.dart';

import 'glob.dart';
import 'icon.dart';
import 'magic.dart';
import 'match.dart';
import 'xml.dart';

/// Full metadata and detection rules for a single media type.
///
/// Each entry corresponds to one `<mime-type>` element in the upstream MIME
/// database XML. The generated files under `g/` construct these from the
/// parsed database; hand-authored entries (e.g. in the override registry) are
/// written directly in Dart.
class RegistryEntry {
  /// The canonical media type string, e.g. `text/plain` or `image/png`.
  final String mediaType;
  final List<IntlString> _comments;

  /// A short acronym for the type, e.g. `PDF` for `application/pdf` (optional).
  final IntlString? acronym;

  /// The expanded form of [acronym], e.g. `Portable Document Format` (optional).
  final IntlString? expandedAcronym;

  /// A custom icon name for this type (optional).
  final IntlString? icon;

  /// A generic fallback icon category, e.g. [GenericIcon.document] (optional).
  final GenericIcon? genericIcon;

  final List<String> _alias;
  final List<String> _subclassOf;

  final List<Glob> _globs;
  final List<Magic> _magic;
  final List<RootXML> _rootXML;

  /// Creates a registry entry for [mediaType].
  ///
  /// All parameters except [mediaType] are optional and default to empty.
  /// At least one of [globs], [magic], or [rootXML] should be supplied for the
  /// entry to participate in detection.
  const RegistryEntry({
    required this.mediaType,
    this.acronym,
    this.expandedAcronym,
    this.icon,
    this.genericIcon,
    this._comments = const [],
    this._alias = const [],
    this._subclassOf = const [],
    this._globs = const [],
    this._magic = const [],
    this._rootXML = const [],
  });

  List<IntlString> get comments => UnmodifiableListView(_comments);
  List<String> get alias => UnmodifiableListView(_alias);
  List<String> get subclassOf => UnmodifiableListView(_subclassOf);
  List<Glob> get globs => UnmodifiableListView(_globs);
  List<Magic> get magic => UnmodifiableListView(_magic);

  List<RootXML> get rootXML => UnmodifiableListView(_rootXML);

  @override
  int get hashCode => Object.hash(
    mediaType,
    const ListEquality().hash(_comments),
    acronym,
    expandedAcronym,
    icon,
    genericIcon,
    const ListEquality().hash(_alias),
    const ListEquality().hash(_subclassOf),
    const ListEquality().hash(_globs),
    const ListEquality().hash(_magic),

    const ListEquality().hash(_rootXML),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RegistryEntry) return false;

    return mediaType == other.mediaType &&
        acronym == other.acronym &&
        expandedAcronym == other.expandedAcronym &&
        icon == other.icon &&
        genericIcon == other.genericIcon &&
        const ListEquality().equals(_comments, other._comments) &&
        const ListEquality().equals(_alias, other._alias) &&
        const ListEquality().equals(_subclassOf, other._subclassOf) &&
        const ListEquality().equals(_globs, other._globs) &&
        const ListEquality().equals(_magic, other._magic) &&
        const ListEquality().equals(_rootXML, other._rootXML);
  }

  /// Check if the given file name matches any of the globs.
  List<MatchResult> matchesGlob(String fileName, {bool caseSensitive = false}) {
    final matches = <MatchResult>[];
    for (final glob in _globs) {
      if (glob.matches(fileName, caseSensitive: caseSensitive)) {
        matches.add(MatchResult(priority: glob.weight, entry: this));
      }
    }
    return matches;
  }

  /// Check if the given byte stream matches any of the magic elements.
  List<MatchResult> matchesMagic(Uint8List bytes) {
    final results = <MatchResult>[];
    for (final magic in _magic) {
      //print(mediaType);
      final priorities = magic.match(bytes);
      for (final priority in priorities) {
        results.add(MatchResult(priority: priority, entry: this));
      }
    }
    return results;
  }

  Map<String, dynamic> toMap() {
    return {
      'mediaType': mediaType,
      'comments': _comments.map((e) => e.toMap()).toList(),
      if (acronym != null) 'acronym': acronym!.toMap(),
      if (expandedAcronym != null) 'expandedAcronym': expandedAcronym!.toMap(),
      if (icon != null) 'icon': icon!.toMap(),
      if (genericIcon != null) 'genericIcon': genericIcon!.value,
      if (_alias.isNotEmpty) 'alias': _alias,
      if (_subclassOf.isNotEmpty) 'subclassOf': _subclassOf,
      if (_globs.isNotEmpty) 'globs': _globs.map((e) => e.toMap()).toList(),
      if (_magic.isNotEmpty) 'magic': _magic.map((e) => e.toMap()).toList(),

      if (_rootXML.isNotEmpty)
        'rootXML': _rootXML.map((e) => e.toMap()).toList(),
    };
  }

  @override
  String toString() => jsonEncode(toMap());
}
