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

/// Media type (MIME type) detection for Dart.
///
/// Identifies file formats from content bytes and/or filenames by merging the
/// [Freedesktop.org Shared MIME-info Database](https://specifications.freedesktop.org/shared-mime-info/latest/)
/// and the [Apache Tika](https://tika.apache.org/) database. Detection runs
/// through a three-stage pipeline — glob matching, magic-number inspection, and
/// root XML element matching — and applies the Freedesktop conflict-resolution
/// rules to rank results.
///
/// ## Quick start
///
/// ```dart
/// import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';
///
/// final matches = detect(bytes: bytes, fileName: 'report.pdf');
/// print(matches.bestMatch); // 'application/pdf'
/// ```
///
/// ## Key types
///
/// - [detect] — top-level function; runs the full layered pipeline.
/// - [MatchList] — detection result; exposes [MatchList.bestMatch] and per-strategy lists.
/// - [MatchResult] — a single match with [MatchResult.mediaType] and [MatchResult.priority].
/// - [MimeInfoRegistry] — abstract base; extend to build custom registries.
/// - [RegistryEntry] — full metadata for one MIME type: globs, magic rules, comments, aliases.
library;

export 'src/mediatype_detector_base.dart';
