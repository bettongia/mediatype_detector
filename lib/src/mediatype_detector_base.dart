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

/// Detect the media type of the file.
///
/// Merges results from both the Tika and Freedesktop registries across all
/// three detection stages (glob, magic, root XML). For duplicate media types,
/// Tika takes precedence as it has broader coverage of modern formats; results
/// unique to Freedesktop are appended. The two databases complement each other:
/// Tika covers more XML-based application types (DITA, Apple iWork, MS Office
/// XML, etc.) while Freedesktop covers others (MathML, GML, GPX, Dia, etc.).
MatchList detect({
  Uint8List? bytes,
  String? fileName,
  bool caseSensitive = false,
}) {
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
/// [primary] takes precedence for duplicate types; the combined list is sorted
/// by priority descending.
List<MatchResult> _mergeResults(
  List<MatchResult> primary,
  List<MatchResult> secondary,
) {
  final seen = <String>{};
  final merged = <MatchResult>[];
  for (final m in [...primary, ...secondary]) {
    if (seen.add(m.mediaType)) merged.add(m);
  }
  merged.sort((a, b) => b.priority.compareTo(a.priority));
  return merged;
}
