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

import 'package:collection/collection.dart';

import 'entry.dart' show RegistryEntry;

/// The result of a [MimeInfoRegistry.detect] call.
///
/// Holds the raw per-strategy lists ([globMatches], [magicMatches],
/// [rootXmlMatches]) and exposes a single merged view ([merged], [bestMatch])
/// that applies the Freedesktop conflict-resolution rules:
///
/// 1. Root XML results are definitive — returned immediately when present.
/// 2. Without magic, glob results are filtered to the most conservative
///    (parent) type so that unconfirmed subtypes are not over-reported.
/// 3. With magic, types confirmed by both magic and glob are ranked first
///    ("doubly confirmed"), followed by parent-child filtering.
class MatchList {
  final List<MatchResult> _globMatches;
  final List<MatchResult> _magicMatches;
  final List<MatchResult> _rootXmlMatches;

  late final List<MatchResult> _merged;

  MatchList({
    List<MatchResult>? globMatches,
    List<MatchResult>? magicMatches,
    List<MatchResult>? rootXmlMatches,
  }) : _rootXmlMatches = List.from(rootXmlMatches ?? []),
       _magicMatches = List.from(magicMatches ?? []),
       _globMatches = List.from(globMatches ?? []) {
    _merged = _merge();
  }

  /// Whether no media type could be determined (all strategy lists are empty).
  bool get isEmpty => _merged.isEmpty;

  /// Raw glob-match results, ordered by glob weight descending.
  ///
  /// These are the unfiltered filename matches before conflict resolution.
  /// Prefer [merged] or [bestMatch] for the final determination.
  Iterable<MatchResult> get globMatches => List.unmodifiable(_globMatches);

  /// Raw magic-match results, ordered by priority descending.
  ///
  /// These are the unfiltered byte-pattern matches before conflict resolution.
  /// Prefer [merged] or [bestMatch] for the final determination.
  Iterable<MatchResult> get magicMatches => List.unmodifiable(_magicMatches);

  /// Raw root-XML match results, ordered by priority descending.
  ///
  /// Only populated when the file appears to be XML-based. When present, these
  /// results are definitive and [merged] returns them directly.
  Iterable<MatchResult> get rootXmlMatches =>
      List.unmodifiable(_rootXmlMatches);

  /// All candidate media type strings from every strategy, deduplicated and
  /// ordered by priority descending.
  ///
  /// Unlike [merged], this list is not filtered by conflict-resolution rules —
  /// it is a flat union of all three strategy results. Use it to inspect every
  /// type that matched, regardless of confidence.
  Iterable<String> get candidates => [
    ..._globMatches,
    ..._magicMatches,
    ..._rootXmlMatches,
  ].sortedBy((m) => m.priority).reversed.map((e) => e.mediaType).toSet();

  /// All [MatchResult] objects from every strategy, deduplicated and ordered
  /// by priority descending.
  ///
  /// Similar to [candidates] but returns full [MatchResult] objects rather than
  /// plain strings. Not filtered by conflict-resolution rules.
  Iterable<MatchResult> get combined => [
    ..._globMatches,
    ..._magicMatches,
    ..._rootXmlMatches,
  ].sortedBy((m) => m.priority).reversed.toSet();

  /// Merge multiple result lists, deduplicating while preserving the priority
  /// order within each list and the precedence order of the lists themselves.
  List<MatchResult> _merge() {
    final rootResults = List<MatchResult>.from(_rootXmlMatches)..sort();
    final magicResults = List<MatchResult>.from(_magicMatches)..sort();
    var globResults = List<MatchResult>.from(_globMatches)..sort();

    // 1. Root XML matches are the most definitive — return immediately.
    if (rootResults.isNotEmpty) return rootResults;

    // 2. Glob-only mode: magic was not run, or ran but found nothing.
    //    Without content inspection we cannot confirm specific subtypes, so
    //    when a parent type and a child type both match by glob, keep the
    //    parent (the more conservative, confirmable identification).
    if (magicResults.isEmpty) {
      if (globResults.isEmpty) return const [];
      final keepSet = globResults.map((r) => r.mediaType).toSet();
      for (final result in globResults) {
        for (final other in globResults) {
          if (other.mediaType == result.mediaType) continue;
          if (other.subclassOf.contains(result.mediaType)) {
            // result is a parent of other; without magic, prefer the parent.
            keepSet.remove(other.mediaType);
          }
        }
      }
      return globResults.where((r) => keepSet.contains(r.mediaType)).toList();
    }

    // 3. Full-match mode: magic found results, filter glob to consistent matches.
    //    Keep a glob entry when:
    //      a) it has no magic of its own (extension-only type — always keep), or
    //      b) magic confirmed the same type directly, or
    //      c) magic confirmed a parent type and the glob identifies the subtype.
    final magicMediaTypes = magicResults.map((m) => m.mediaType).toSet();
    final globMediaTypes = globResults.map((m) => m.mediaType).toSet();

    globResults = globResults.where((m) {
      if (!m.hasMagic) return true;
      if (magicMediaTypes.contains(m.mediaType)) return true;
      return m.subclassOf.any((parent) => magicMediaTypes.contains(parent));
    }).toList();

    // 4. Combine: magic first (baseline), then filtered glob (refinements).
    final allResults = [...magicResults, ...globResults];

    // 5. Deduplicate by mediaType, keeping first occurrence.
    final uniqueResults = <MatchResult>[];
    final seenMediaTypes = <String>{};
    for (final result in allResults) {
      if (seenMediaTypes.add(result.mediaType)) {
        uniqueResults.add(result);
      }
    }

    // 6. Types appearing in BOTH magic and glob results have the highest
    //    confidence.  Sort them first, then by priority descending.
    final doublyConfirmed = magicMediaTypes.intersection(globMediaTypes);
    uniqueResults.sort((a, b) {
      final aTier = doublyConfirmed.contains(a.mediaType) ? 0 : 1;
      final bTier = doublyConfirmed.contains(b.mediaType) ? 0 : 1;
      if (aTier != bTier) return aTier.compareTo(bTier);
      return b.priority.compareTo(a.priority);
    });

    // 7. Parent-child filtering.
    //    Three-way decision for each (parent, child) pair:
    //      a) child is in magic results → child wins (magic explicitly identified it)
    //      b) parent is doubly-confirmed AND child is not in magic → parent wins
    //         (e.g. gzip confirmed by both glob *.gz and magic beats x-compressed-tar
    //          that only matched by glob extension, so we can't confirm it's really tar)
    //      c) otherwise → child wins (more specific identification)
    final keepSet = uniqueResults.map((r) => r.mediaType).toSet();
    for (final result in uniqueResults) {
      if (!keepSet.contains(result.mediaType)) continue;
      for (final other in uniqueResults) {
        if (other.mediaType == result.mediaType) continue;
        if (!keepSet.contains(other.mediaType)) continue;
        if (other.subclassOf.contains(result.mediaType)) {
          // result is a parent of other (child).
          if (magicMediaTypes.contains(other.mediaType)) {
            keepSet.remove(
              result.mediaType,
            ); // (a) magic confirmed child — parent out
          } else if (doublyConfirmed.contains(result.mediaType)) {
            keepSet.remove(
              other.mediaType,
            ); // (b) doubly-confirmed parent — child out
          } else {
            keepSet.remove(result.mediaType); // (c) child wins by default
          }
        }
      }
    }

    return uniqueResults.where((r) => keepSet.contains(r.mediaType)).toList();
  }

  /// The conflict-resolved result list, ordered by confidence then priority.
  ///
  /// Applies the Freedesktop MIME-info specification's conflict-resolution
  /// rules across the glob, magic, and root XML results. This is the primary
  /// output of detection; [bestMatch] returns the first element's media type.
  List<MatchResult> get merged => List.unmodifiable(_merged);

  /// The single best media type determination, or `null` if nothing matched.
  ///
  /// Equivalent to `merged.firstOrNull?.mediaType`. Use this when you only
  /// need one answer and do not need to inspect confidence or alternatives.
  String? get bestMatch {
    return _merged.firstOrNull?.mediaType;
  }
}

/// A single successful detection result for one media type.
///
/// Carries the matched [mediaType], its [priority] (higher = more specific),
/// and supporting metadata used by [MatchList]'s conflict-resolution rules
/// ([subclassOf], [hasMagic]).
class MatchResult implements Comparable<MatchResult> {
  /// The priority of the match rule that succeeded (e.g., from magic or rootXML).
  ///
  /// Higher values indicate stronger or more specific matches (usually up to 100).
  final int priority;

  final RegistryEntry _entry;

  /// The underlying media type that was matched.
  String get mediaType => _entry.mediaType;

  /// The parent media type(s) of this type, as declared in the MIME database.
  ///
  /// Used by [MatchList]'s parent-child filtering rules to determine whether a
  /// specific subtype (e.g. `application/vnd.oasis.opendocument.text`) can be
  /// promoted over a generic parent type (e.g. `application/zip`) confirmed by
  /// magic.
  List<String> get subclassOf => _entry.subclassOf;

  /// Whether the underlying [RegistryEntry] declares any magic rules.
  ///
  /// Types without magic rules are extension-only; [MatchList] always retains
  /// them regardless of what magic matching found.
  bool get hasMagic => _entry.magic.isNotEmpty;

  /// Creates a new [MatchResult] with the given [priority] and [mediaType].
  MatchResult({required this.priority, required this._entry});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MatchResult &&
        other.priority == priority &&
        other.mediaType == mediaType;
  }

  @override
  int get hashCode => Object.hash(priority, mediaType);

  @override
  int compareTo(MatchResult other) {
    // Sort descending by priority (higher priority first)
    final priorityComparison = other.priority.compareTo(priority);
    return priorityComparison != 0
        ? priorityComparison
        : mediaType.compareTo(other.mediaType);
  }

  Map<String, dynamic> toMap() {
    return {'priority': priority, 'mediaType': mediaType};
  }

  @override
  String toString() => jsonEncode(toMap());
}
