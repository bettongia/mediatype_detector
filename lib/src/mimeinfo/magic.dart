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
import 'dart:typed_data';

import 'package:betto_common/collections.dart';
import 'package:collection/collection.dart';

/// A magic-number rule that identifies a file type from its byte content.
///
/// Each [Magic] groups one or more [Match] conditions under a single
/// [priority]. All conditions are evaluated; any match returns [priority] as
/// a candidate score. The rule is satisfied when at least one [Match] (or
/// its sub-match chain) succeeds.
class Magic {
  /// The confidence score returned when this rule matches (typically 50–80).
  ///
  /// Higher values indicate a stronger identification. Scores are compared
  /// across rules to rank [MatchResult]s in the final [MatchList].
  final int priority;
  final List<Match> _matches;

  const Magic({required this._matches, this.priority = 50});

  @override
  int get hashCode =>
      Object.hash(priority, const ListEquality().hash(_matches));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Magic &&
          runtimeType == other.runtimeType &&
          priority == other.priority &&
          const ListEquality().equals(_matches, other._matches);

  /// The individual [Match] conditions that make up this rule.
  List<Match> get matches => UnmodifiableListView(_matches);

  /// Evaluates this rule against [bytes] and returns a set of matching
  /// priorities.
  ///
  /// Returns `{priority}` if any [Match] condition succeeds, or an empty set
  /// if none do. Callers accumulate these sets across all rules to build the
  /// full set of candidate priorities for a file.
  Set<int> match(Uint8List bytes) {
    final results = <int>{};
    for (final m in _matches) {
      if (m.matches(bytes)) {
        results.add(priority);
      }
    }
    return results;
  }

  Map<String, dynamic> toMap() {
    return {
      'priority': priority,
      'match': matches.map((e) => e.toMap()).toList(),
    };
  }

  @override
  String toString() => jsonEncode(toMap());
}

/// Types of data that can be matched in a magic rule.
enum MatchType {
  string('string'),
  stringignorecase('stringignorecase'),
  big16('big16'),
  big32('big32'),
  little16('little16'),
  little32('little32'),
  host16('host16'),
  host32('host32'),
  byte('byte'),
  regex('regex'),
  // This isn't specifically a type but it's used for Tika's mimeinfo
  minShouldMatch('minShouldMatch');

  final String value;

  const MatchType(this.value);

  static MatchType? tryParse(String value) {
    for (var t in MatchType.values) {
      if (t.value == value) {
        return t;
      }
    }
    return null;
  }

  @override
  String toString() => value;
}

/// A single byte-pattern condition within a [Magic] rule.
///
/// Checks for a specific byte sequence at a given [offset] within the file,
/// optionally applying a [mask] before comparison. Sub-matches ([subMatches])
/// form an OR group: the parent must match, then at least one sub-match must
/// also match.
///
/// Use [Match.factory] to construct instances; it selects the correct
/// subclass ([RegExpMatch], [MinShouldMatch], or the default [Match]).
class Match {
  /// The byte offset into the file, as `"N"` (exact) or `"N:M"` (range).
  final String offset;

  /// The data type that determines how [value] is interpreted and compared.
  final MatchType type;

  /// The value to match against, encoded per [type] (e.g. hex string, text).
  final String? value;

  /// An optional bitmask applied to both the file bytes and [value] before
  /// comparison, encoded as a hex string.
  final String? mask;

  /// For [MatchType.minShouldMatch] rules: the minimum number of sub-matches
  /// that must succeed.
  final int? minShouldMatch;
  final List<Match> _subMatches;

  // Pre-computed once at construction time to avoid repeated parsing per call.
  final (int, int?) _parsedOffset;
  final Uint8List _valueBytes;
  final Uint8List? _maskBytes;

  Match._internal({
    required this.type,
    this.value,
    this.offset = '0',
    this.mask,
    this.minShouldMatch = 0,
    this._subMatches = const [],
  }) : _parsedOffset = _parseOffset(offset),
       _valueBytes = value != null ? _valueToBytes(value, type) : Uint8List(0),
       _maskBytes = mask != null ? _hexToBytes(mask) : null;

  /// Creates the appropriate [Match] subclass for the given parameters.
  ///
  /// - [MatchType.minShouldMatch] → [MinShouldMatch]
  /// - [MatchType.regex] → [RegExpMatch]
  /// - All others → base [Match]
  ///
  /// Throws [ArgumentError] if required fields are missing for the chosen type.
  factory Match.factory({
    required MatchType type,
    String? value,
    String offset = '0',
    String? mask,
    int? minShouldMatch,
    List<Match> subMatches = const [],
  }) {
    if (type == MatchType.minShouldMatch || minShouldMatch != null) {
      if (minShouldMatch != null) {
        return MinShouldMatch(
          offset: offset,
          minShouldMatch: minShouldMatch,
          subMatches: subMatches,
        );
      }
      throw ArgumentError.notNull('minShouldMatch');
    }
    if (value == null) {
      throw ArgumentError.notNull('value');
    }
    if (type == MatchType.regex) {
      return RegExpMatch(
        value: value,
        offset: offset,
        minShouldMatch: minShouldMatch,
        subMatches: subMatches,
      );
    }

    return Match._internal(
      type: type,
      value: value,
      offset: offset,
      mask: mask,
      minShouldMatch: minShouldMatch,
      subMatches: subMatches,
    );
  }

  @override
  int get hashCode => Object.hash(
    offset,
    type,
    value,
    mask,
    const ListEquality().hash(_subMatches),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Match &&
          runtimeType == other.runtimeType &&
          offset == other.offset &&
          type == other.type &&
          value == other.value &&
          mask == other.mask &&
          const ListEquality().equals(_subMatches, other._subMatches);

  /// Child conditions that form an OR group evaluated after this match succeeds.
  List<Match> get subMatches => UnmodifiableListView(_subMatches);

  /// Returns `true` if [bytes] satisfies this match condition.
  ///
  /// Checks the byte sequence at each position in the [offset] range, applying
  /// [mask] if set. If the parent bytes match and [subMatches] is non-empty,
  /// at least one sub-match must also succeed.
  bool matches(Uint8List bytes) {
    if (_valueBytes.isEmpty) return false;

    final (startOffset, endOffset) = _parsedOffset;
    final rangeEnd = endOffset ?? startOffset;
    final compareFn = type == MatchType.stringignorecase
        ? _matchesAtIgnoreCase
        : _matchesAt;

    for (var pos = startOffset; pos <= rangeEnd; pos++) {
      if (pos + _valueBytes.length > bytes.length) break;

      if (compareFn(bytes, pos, _valueBytes, _maskBytes)) {
        // If there are sub-matches, at least one must also match (OR).
        if (_subMatches.isEmpty) return true;
        for (final sub in _subMatches) {
          if (sub.matches(bytes)) return true;
        }
        // Parent matched but no sub-match did.
        continue;
      }
    }
    return false;
  }

  /// Compare [valueBytes] against [bytes] at [position], applying [maskBytes]
  /// if provided.
  static bool _matchesAt(
    Uint8List bytes,
    int position,
    Uint8List valueBytes,
    Uint8List? maskBytes,
  ) {
    for (var i = 0; i < valueBytes.length; i++) {
      var fileByte = bytes[position + i];
      var valueByte = valueBytes[i];
      if (maskBytes != null && i < maskBytes.length) {
        fileByte &= maskBytes[i];
        valueByte &= maskBytes[i];
      }
      if (fileByte != valueByte) return false;
    }
    return true;
  }

  /// Compare [valueBytes] against [bytes] at [position] using ASCII
  /// case-insensitive comparison. [valueBytes] must already be lowercased
  /// (as produced by [_valueToBytes] for [MatchType.stringignorecase]).
  static bool _matchesAtIgnoreCase(
    Uint8List bytes,
    int position,
    Uint8List valueBytes,
    Uint8List? maskBytes,
  ) {
    for (var i = 0; i < valueBytes.length; i++) {
      var fileByte = bytes[position + i];
      var valueByte = valueBytes[i];
      if (maskBytes != null && i < maskBytes.length) {
        fileByte &= maskBytes[i];
        valueByte &= maskBytes[i];
      }
      // ASCII case-fold A–Z → a–z.
      if (fileByte >= 0x41 && fileByte <= 0x5A) fileByte |= 0x20;
      if (fileByte != valueByte) return false;
    }
    return true;
  }

  /// Parse an offset string: "N" returns (N, null), "N:M" returns (N, M).
  static (int, int?) _parseOffset(String offset) {
    final parts = offset.split(':');
    final start = int.parse(parts[0]);
    final end = parts.length > 1 ? int.parse(parts[1]) : null;
    return (start, end);
  }

  /// Convert a [value] string to bytes based on the [MatchType].
  static Uint8List _valueToBytes(String value, MatchType type) {
    switch (type) {
      case MatchType.string:
        if (value.startsWith('0x') || value.startsWith('0X')) {
          return _hexToBytes(value);
        }
        return Uint8List.fromList(value.codeUnits);
      case MatchType.stringignorecase:
        // Parse identically to `string`, then ASCII-lowercase the pattern so
        // _matchesAtIgnoreCase only needs to fold the file bytes.
        final raw = (value.startsWith('0x') || value.startsWith('0X'))
            ? _hexToBytes(value)
            : Uint8List.fromList(value.codeUnits);
        for (var i = 0; i < raw.length; i++) {
          if (raw[i] >= 0x41 && raw[i] <= 0x5A) raw[i] |= 0x20;
        }
        return raw;
      case MatchType.byte:
        return Uint8List.fromList(value.codeUnits);

      case MatchType.big16:
        final v = _parseHexInt(value);
        return Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);

      case MatchType.big32:
        final v = _parseHexInt(value);
        return Uint8List.fromList([
          (v >> 24) & 0xFF,
          (v >> 16) & 0xFF,
          (v >> 8) & 0xFF,
          v & 0xFF,
        ]);

      case MatchType.little16:
        final v = _parseHexInt(value);
        return Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);

      case MatchType.little32:
        final v = _parseHexInt(value);
        return Uint8List.fromList([
          v & 0xFF,
          (v >> 8) & 0xFF,
          (v >> 16) & 0xFF,
          (v >> 24) & 0xFF,
        ]);

      case MatchType.host16:
        final v = _parseHexInt(value);
        if (Endian.host == Endian.little) {
          return Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);
        } else {
          return Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);
        }

      case MatchType.host32:
        final v = _parseHexInt(value);
        if (Endian.host == Endian.little) {
          return Uint8List.fromList([
            v & 0xFF,
            (v >> 8) & 0xFF,
            (v >> 16) & 0xFF,
            (v >> 24) & 0xFF,
          ]);
        } else {
          return Uint8List.fromList([
            (v >> 24) & 0xFF,
            (v >> 16) & 0xFF,
            (v >> 8) & 0xFF,
            v & 0xFF,
          ]);
        }
      default:
        throw ArgumentError.value(type.name);
    }
  }

  /// Parse a hex string like "0xBEEFC0DE" or decimal string into an int.
  static int _parseHexInt(String s) {
    if (s.startsWith('0x') || s.startsWith('0X')) {
      return int.parse(s.substring(2), radix: 16);
    }
    return int.parse(s);
  }

  /// Convert a hex mask string like "0xffffff00ffffffff" to a list of bytes.
  static Uint8List _hexToBytes(String hex) {
    var s = hex;
    if (s.startsWith('0x') || s.startsWith('0X')) {
      s = s.substring(2);
    }
    // Pad to even length.
    if (s.length.isOdd) {
      s = '0$s';
    }
    final result = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      result.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  Map<String, dynamic> toMap() {
    return {
      'offset': offset,
      'datatype': type.name,
      'value': value,
      if (mask != null) 'mask': mask,
      if (_subMatches.isNotEmpty)
        'match': _subMatches.map((e) => e.toMap()).toList(),
    };
  }

  @override
  String toString() => jsonEncode(toMap());
}

/// A [Match] variant that requires at least [minShouldMatch] of its
/// [subMatches] to succeed, used for Tika's `minShouldMatch` rules.
class MinShouldMatch implements Match {
  @override
  final String offset;
  @override
  final MatchType type = MatchType.minShouldMatch;
  @override
  final String value = '';
  @override
  final List<Match> _subMatches;

  @override
  final int minShouldMatch;

  @override
  (int, int?) get _parsedOffset => (0, null);
  @override
  Uint8List get _valueBytes => Uint8List(0);
  @override
  Uint8List? get _maskBytes => null;

  MinShouldMatch({
    required this.offset,
    required this.minShouldMatch,
    this._subMatches = const [],
  });

  @override
  String? get mask => null;

  @override
  bool matches(Uint8List bytes) {
    int count = 0;
    for (final sub in _subMatches) {
      if (sub.matches(bytes)) {
        count++;
        if (count >= minShouldMatch) return true;
      }
    }
    return false;
  }

  @override
  List<Match> get subMatches => UnmodifiableListView(_subMatches);

  @override
  int get hashCode => Object.hash(
    offset,
    type,
    value,
    mask,
    minShouldMatch,
    const ListEquality().hash(_subMatches),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinShouldMatch &&
          runtimeType == other.runtimeType &&
          offset == other.offset &&
          type == other.type &&
          value == other.value &&
          mask == other.mask &&
          minShouldMatch == other.minShouldMatch &&
          const ListEquality().equals(_subMatches, other._subMatches);

  @override
  Map<String, dynamic> toMap() {
    return {
      'offset': offset,
      'datatype': type.name,
      'value': value,
      if (_subMatches.isNotEmpty)
        'match': _subMatches.map((e) => e.toMap()).toList(),
    };
  }
}

/// A [Match] variant that uses a regular expression instead of a byte pattern.
///
/// Used by Tika's `tika-mimetypes.xml` for `<match type="regex">` elements.
/// The [offset] and [value] (the regex pattern) are the only relevant fields;
/// inline flags such as `(?i)`, `(?m)`, and `(?s)` are parsed and applied.
class RegExpMatch implements Match {
  @override
  final String offset;
  @override
  final MatchType type = MatchType.regex;
  @override
  final String value;
  @override
  final List<Match> _subMatches;

  @override
  final int? minShouldMatch;

  @override
  (int, int?) get _parsedOffset => (0, null);
  @override
  Uint8List get _valueBytes => Uint8List(0);
  @override
  Uint8List? get _maskBytes => null;

  late RegExp _regex;

  RegExpMatch({
    required this.value,
    required this.offset,
    this.minShouldMatch,
    this._subMatches = const [],
  }) {
    _regex = createDartRegExp(value);
  }

  @override
  List<Match> get subMatches => UnmodifiableListView(_subMatches);

  @override
  String? get mask => null; // not used for regex matches

  @override
  int get hashCode => Object.hash(
    offset,
    type,
    value,
    mask,
    const ListEquality().hash(_subMatches),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegExpMatch &&
          runtimeType == other.runtimeType &&
          offset == other.offset &&
          type == other.type &&
          value == other.value &&
          mask == other.mask &&
          const ListEquality().equals(_subMatches, other._subMatches);

  @override
  Map<String, dynamic> toMap() {
    return {
      'offset': offset,
      'datatype': type.name,
      'value': value,
      if (_subMatches.isNotEmpty)
        'match': _subMatches.map((e) => e.toMap()).toList(),
    };
  }

  @override
  bool matches(Uint8List bytes) {
    bool m = false;
    // Parse offset — either "N" or "N:M".
    final (startOffset, endOffset) = Match._parseOffset(offset);

    // Limit how many bytes we convert to a string to avoid scanning the entire
    // file. 65536 bytes is more than sufficient for any magic pattern.
    const maxWindow = 65536;

    if (endOffset == null) {
      // Single offset: pattern must match at exactly that offset, not anywhere
      // further into the file. Use matchAsPrefix to anchor to startOffset.
      if (startOffset >= bytes.length) return false;
      final windowEnd = (startOffset + maxWindow).clamp(0, bytes.length);
      final content = String.fromCharCodes(bytes, startOffset, windowEnd);
      m = _regex.matchAsPrefix(content) != null;
    } else {
      // Range offset: try matching at each candidate position in the range.
      final rangeEnd = endOffset.clamp(0, bytes.length);
      final windowEnd = (rangeEnd + maxWindow).clamp(0, bytes.length);
      final content = String.fromCharCodes(bytes, 0, windowEnd);
      for (final pos in range(start: startOffset, stop: rangeEnd)) {
        if (pos >= bytes.length) {
          break;
        }
        if (_regex.hasMatch(content.substring(pos.toInt()))) {
          m = true;
          break;
        }
      }
    }
    if (m) {
      // If there are sub-matches, at least one must also match (OR).
      if (_subMatches.isEmpty) return true;
      for (final sub in _subMatches) {
        if (sub.matches(bytes)) return true;
      }
    }
    return false;
  }

  static RegExp createDartRegExp(String pattern) {
    // Regex to find inline flags at the start of the string, e.g., (?i) or (?im)
    final flagRegex = RegExp(r'^\(\?([ims]+)\)');
    final match = flagRegex.firstMatch(pattern);

    bool caseSensitive = true;
    bool multiLine = false;
    bool dotAll = false;

    String cleanPattern = pattern;

    if (match != null) {
      String flags = match.group(1)!;

      // Configure based on the flags found
      if (flags.contains('i')) caseSensitive = false;
      if (flags.contains('m')) multiLine = true;
      if (flags.contains('s')) dotAll = true;

      // Strip the flags from the pattern string
      cleanPattern = pattern.substring(match.end);
    }

    return RegExp(
      cleanPattern,
      caseSensitive: caseSensitive,
      multiLine: multiLine,
      dotAll: dotAll,
    );
  }
}
