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

import 'dart:typed_data' show Uint8List;

import 'tika_mimeinfo/registry.dart' show TikaMimeInfoRegistry;
import 'tika_mimeinfo/g/mimeinfo.dart' as tika;

import 'freedesktop_mimeinfo/registry.dart' show FreedesktopMimeInfoRegistry;
import 'freedesktop_mimeinfo/g/mimeinfo.dart' as fd;

import 'override_mimeinfo/registry.dart' show OverrideMimeInfoRegistry;
import 'override_mimeinfo/entries.dart' show overrideDb;
export 'override_mimeinfo/registry.dart' show OverrideMimeInfoRegistry;

import 'mimeinfo/base.dart';
export 'mimeinfo/base.dart';

// TIKA
final tikaMimeInfoRegistry = TikaMimeInfoRegistry(tika.mimeinfoDb);

// These two lines need to be swapped in if you have to completely
// clear out all 'g' files and start from scratch
//
// import 'package:betto_mediatype_detector/src/mimeinfo/registry.dart';
// final tikaMimeInfoRegistry = TikaMimeInfoRegistry(emptyRegistry);

// FreeDesktop
final freedesktopMimeInfoRegistry = FreedesktopMimeInfoRegistry(fd.mimeinfoDb);

// These two lines need to be swapped in if you have to completely
// clear out all 'g' files and start from scratch
//
// import 'package:betto_mediatype_detector/src/mimeinfo/registry.dart';
// final freedesktopMimeInfoRegistry = FreedesktopMimeInfoRegistry(emptyRegistry);

/// The built-in override registry.
///
/// Contains hand-authored corrections for known bad upstream mappings (e.g.
/// Tika's incorrect `*.rs` → `application/rls-services+xml` mapping) and
/// entries for emerging formats absent from both Tika and Freedesktop.
///
/// This registry is consulted by [detect] before the blended Tika +
/// Freedesktop registry. See `lib/src/override_mimeinfo/entries.dart` for
/// the entry list and authoring guidelines.
final overrideMimeInfoRegistry = OverrideMimeInfoRegistry(overrideDb);

/// Detects the media type of a file using a layered registry pipeline.
///
/// The pipeline consults registries in priority order, returning the result
/// of the first registry that produces a non-empty [MatchList]:
///
/// 1. **[customRegistry]** — an optional [MimeInfoRegistry] supplied by the
///    caller. Use this to add per-call detection of proprietary or
///    domain-specific media types without touching global state.
/// 2. **Override registry** — the built-in [OverrideMimeInfoRegistry] that
///    corrects known bad upstream mappings (e.g. `*.rs` → `text/rust`) and
///    covers formats absent from both upstream databases.
/// 3. **Blended registry** — the merged Tika + Freedesktop result. Merges
///    glob, magic, and root XML results from both databases across all three
///    detection stages. For duplicate media types the entry with the higher
///    priority is kept; on a tie the entry with the richer [RegistryEntry.subclassOf] chain
///    is preferred so that parent-child resolution works correctly.
///
/// Each layer uses short-circuit semantics: if a registry returns a non-empty
/// [MatchList], lower-priority registries are not consulted. A [customRegistry]
/// or override entry that only matches by glob will suppress the blended
/// registry's magic and root XML stages for that file; include magic rules in
/// the entry if content-confirmation is required.
///
/// Both [bytes] and [fileName] are optional, but providing both enables the
/// most accurate detection (magic + glob + root XML).
///
/// [caseSensitive] controls whether glob patterns are matched case-sensitively
/// (default: false — case-insensitive, appropriate for most file systems).
MatchList detect({
  Uint8List? bytes,
  String? fileName,
  bool caseSensitive = false,
  MimeInfoRegistry? customRegistry,
}) {
  // Layer 1: caller-provided custom registry (short-circuit).
  if (customRegistry != null) {
    final result = customRegistry.detect(
      bytes: bytes,
      fileName: fileName,
      caseSensitive: caseSensitive,
    );
    if (!result.isEmpty) return result;
  }

  // Layer 2: built-in override registry (short-circuit).
  final overrideResult = overrideMimeInfoRegistry.detect(
    bytes: bytes,
    fileName: fileName,
    caseSensitive: caseSensitive,
  );
  if (!overrideResult.isEmpty) return overrideResult;

  // Layer 3: blended Tika + Freedesktop registry.
  final tikaGlob = fileName != null
      ? tikaMimeInfoRegistry.matchGlob(fileName, caseSensitive: caseSensitive)
      : null;
  final fdGlob = fileName != null
      ? freedesktopMimeInfoRegistry.matchGlob(
          fileName,
          caseSensitive: caseSensitive,
        )
      : null;

  final tikaMagic = bytes != null
      ? tikaMimeInfoRegistry.matchMagic(bytes)
      : null;
  final fdMagic = bytes != null
      ? freedesktopMimeInfoRegistry.matchMagic(bytes)
      : null;

  final mergedGlob = fileName != null
      ? _mergeResults(tikaGlob!, fdGlob!)
      : null;
  final mergedMagic = bytes != null
      ? _mergeResults(tikaMagic!, fdMagic!)
      : null;

  List<MatchResult>? rootXmlMatches;
  if (bytes != null &&
      tikaMimeInfoRegistry.isLikelyXml(mergedGlob, mergedMagic)) {
    rootXmlMatches = _mergeResults(
      tikaMimeInfoRegistry.matchRootXML(bytes),
      freedesktopMimeInfoRegistry.matchRootXML(bytes),
    );
  }

  return MatchList(
    globMatches: mergedGlob,
    magicMatches: mergedMagic,
    rootXmlMatches: rootXmlMatches,
  );
}

/// Merges two result lists, deduplicating by media type.
///
/// When the same media type appears in both [primary] and [secondary], the
/// entry with the higher priority is kept. On a priority tie, the entry with
/// the richer [MatchResult.subclassOf] chain (longer list) is preferred, so
/// that parent-child relationships from Freedesktop are not discarded when
/// Tika supplies the same type at a lower weight. The combined list is sorted
/// by priority descending.
///
/// This resolves the class of bugs where `_mergeResults` was keeping Tika's
/// lower-priority duplicate and discarding Freedesktop's higher-priority or
/// richer-parentage entry (e.g. `.html`, `.key`, OOXML).
List<MatchResult> _mergeResults(
  List<MatchResult> primary,
  List<MatchResult> secondary,
) {
  // Build a map from mediaType → best MatchResult, preferring higher priority
  // and, on a tie, the richer subclassOf chain.
  final best = <String, MatchResult>{};
  for (final m in [...primary, ...secondary]) {
    final existing = best[m.mediaType];
    if (existing == null) {
      best[m.mediaType] = m;
    } else if (m.priority > existing.priority) {
      // Current entry has higher priority — replace.
      best[m.mediaType] = m;
    } else if (m.priority == existing.priority &&
        m.subclassOf.length > existing.subclassOf.length) {
      // Same priority but richer parentage — prefer the richer entry so that
      // parent-child resolution in MatchList._merge() can operate correctly
      // (e.g. OOXML glob needs subclassOf=[application/zip] to win over magic).
      best[m.mediaType] = m;
    }
    // Otherwise keep existing.
  }
  final merged = best.values.toList();
  merged.sort((a, b) => b.priority.compareTo(a.priority));
  return merged;
}
