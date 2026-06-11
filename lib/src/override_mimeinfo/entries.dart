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

/// Hand-authored override entries that correct known bad mappings in the
/// upstream Tika and Freedesktop databases, or cover emerging formats not
/// yet present in either database.
///
/// **Do not generate this file.** Unlike the files under `g/`, this map is
/// maintained by hand. Add entries here when:
/// - An upstream database maps a glob to the wrong media type and the fix
///   cannot wait for the upstream to be updated.
/// - A file format is absent from both databases entirely.
///
/// Each entry is keyed by its canonical media type string. The glob [weight]
/// for corrective entries should be set high enough to beat the incorrect
/// upstream mapping — typically 60 or above — while remaining below the
/// "definitive" threshold of 80 reserved for high-confidence upstream entries.
///
/// ## Current corrections
///
/// | Pattern | Correct type   | Upstream defect                          |
/// |---------|----------------|------------------------------------------|
/// | `*.rs`  | `text/rust`    | Tika maps `*.rs` to                      |
/// |         |                | `application/rls-services+xml` (wrong)   |
library;

import 'package:betto_common/string.dart' show IntlString;

import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';

/// The static registry map consumed by [OverrideMimeInfoRegistry].
///
/// Keys are canonical media type strings; values are lists of
/// [RegistryEntry] instances (typically one per type).
const Map<String, List<RegistryEntry>> overrideDb = {
  // Tika incorrectly maps *.rs to application/rls-services+xml (a PIDF-based
  // XML type used in SIP resource lists). Rust source files are text/rust per
  // Freedesktop; the IANA registration for text/rust is pending. A weight of
  // 60 beats Tika's weight-50 entry while remaining below the 80 threshold
  // used for high-confidence upstream globs.
  'text/rust': [
    RegistryEntry(
      mediaType: 'text/rust',
      comments: [IntlString.constant('Rust source code')],
      subclassOf: ['text/plain'],
      globs: [Glob(pattern: '*.rs', weight: 60, caseSensitive: false)],
    ),
  ],
};
