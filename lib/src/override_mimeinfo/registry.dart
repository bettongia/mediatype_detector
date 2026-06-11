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

import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';

/// A hand-authored registry that corrects known bad mappings in the upstream
/// Tika and Freedesktop databases and covers formats absent from both.
///
/// This registry is consulted **before** the blended Tika + Freedesktop
/// registry in the top-level [detect] function. If it returns a non-empty
/// [MatchList] for a given file, that result is returned immediately without
/// consulting the blended registry (short-circuit semantics).
///
/// See `lib/src/override_mimeinfo/entries.dart` for the current correction
/// entries and the criteria for adding new ones.
class OverrideMimeInfoRegistry extends MimeInfoRegistry {
  /// Creates an instance backed by the provided [entries] map.
  OverrideMimeInfoRegistry(super.entries);
}
