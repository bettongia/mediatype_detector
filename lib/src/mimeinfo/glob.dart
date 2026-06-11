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

import 'package:glob/glob.dart' as glob_pattern;

/// A filename glob pattern rule from the MIME database.
///
/// Each [Glob] maps a shell-style pattern (e.g. `*.png`, `*.tar.gz`) to its
/// match weight. Higher-weight globs represent more specific or more
/// authoritative mappings and win in conflict resolution.
class Glob {
  /// The shell-style glob pattern, e.g. `*.png` or `README*`.
  final String pattern;

  /// The confidence weight of this glob rule (typically 50 or 80).
  ///
  /// Higher values indicate a stronger mapping. The Freedesktop spec defines
  /// 50 as the default and 80 as a high-confidence override.
  final int weight;

  /// Whether this pattern must be matched case-sensitively.
  ///
  /// Even when `false`, the effective case sensitivity can be raised to `true`
  /// by the `caseSensitive` argument passed to [matches].
  final bool caseSensitive;

  const Glob({
    required this.pattern,
    this.weight = 50,
    required this.caseSensitive,
  });

  @override
  int get hashCode => Object.hash(pattern, weight, caseSensitive);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Glob &&
          runtimeType == other.runtimeType &&
          pattern == other.pattern &&
          weight == other.weight &&
          caseSensitive == other.caseSensitive;

  static final Map<Glob, glob_pattern.Glob> _cacheIgnoreCase = {};
  static final Map<Glob, glob_pattern.Glob> _cacheCaseSensitive = {};

  /// Returns `true` if [fileName] matches this glob pattern.
  ///
  /// Case sensitivity is determined by the logical OR of [caseSensitive] and
  /// [this.caseSensitive] — passing `true` forces case-sensitive matching even
  /// when the pattern itself is marked case-insensitive. Compiled [RegExp]
  /// objects are cached per [Glob] instance to avoid repeated parsing.
  bool matches(String fileName, {bool caseSensitive = false}) {
    final effectiveCaseSensitive = caseSensitive || this.caseSensitive;

    if (effectiveCaseSensitive) {
      final glob = _cacheCaseSensitive.putIfAbsent(
        this,
        () => glob_pattern.Glob(pattern, caseSensitive: true),
      );
      return glob.matches(fileName);
    } else {
      final glob = _cacheIgnoreCase.putIfAbsent(
        this,
        () => glob_pattern.Glob(pattern, caseSensitive: false),
      );
      return glob.matches(fileName);
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'pattern': pattern,
      'weight': weight,
      'caseSensitive': caseSensitive,
    };
  }

  @override
  String toString() => jsonEncode(toMap());
}
