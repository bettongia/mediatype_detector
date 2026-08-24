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

/// Tests for the layered detection pipeline introduced in Phase 2 and Phase 3:
///
/// - The built-in [OverrideMimeInfoRegistry] short-circuits before the blended
///   Tika + Freedesktop registry when it produces a non-empty result.
/// - A caller-supplied [customRegistry] short-circuits before both the override
///   and the blended registries when it produces a non-empty result.
/// - Passing `null` for [customRegistry] is a no-op: blended results are
///   unchanged.
/// - The pipeline order is: custom → override → blended.
library;

import 'dart:io';

import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Minimal custom registry used across several tests.
//
// Maps the fictional extension *.bingo to application/vnd.test.bingo so that
// its glob is guaranteed never to collide with real Tika/Freedesktop entries.
// ---------------------------------------------------------------------------

/// A one-entry [MimeInfoRegistry] used to exercise the caller-registry layer.
/// Maps the fictional extension *.bingo to guarantee no collision with real
/// Tika/Freedesktop entries.
class _BingoRegistry extends MimeInfoRegistry {
  _BingoRegistry()
    : super(const {
        'application/vnd.test.bingo': [
          RegistryEntry(
            mediaType: 'application/vnd.test.bingo',
            globs: [Glob(pattern: '*.bingo', weight: 80, caseSensitive: false)],
          ),
        ],
      });
}

/// A one-entry [MimeInfoRegistry] that maps *.rs to a fictional type, used to
/// verify that the custom registry layer short-circuits the override registry.
class _CustomRsRegistry extends MimeInfoRegistry {
  _CustomRsRegistry()
    : super(const {
        'application/vnd.test.custom-rs': [
          RegistryEntry(
            mediaType: 'application/vnd.test.custom-rs',
            globs: [Glob(pattern: '*.rs', weight: 80, caseSensitive: false)],
          ),
        ],
      });
}

/// A magic-only [MimeInfoRegistry] that matches the PNG magic signature and
/// maps it to a fictional type, used to verify that bytes are forwarded to the
/// custom registry.
class _CustomPngMagicRegistry extends MimeInfoRegistry {
  _CustomPngMagicRegistry()
    : super({
        'application/vnd.test.custom-png': [
          RegistryEntry(
            mediaType: 'application/vnd.test.custom-png',
            magic: [
              Magic(
                priority: 80,
                matches: [
                  Match.factory(
                    type: MatchType.string,
                    offset: '0',
                    value: '\x89PNG\r\n\x1a\n',
                    mask: null,
                    minShouldMatch: null,
                  ),
                ],
              ),
            ],
          ),
        ],
      });
}

void main() {
  group('Override registry (built-in)', () {
    // -----------------------------------------------------------------------
    // The override registry corrects Tika's *.rs → application/rls-services+xml
    // mapping. These tests verify that the short-circuit fires for glob and
    // full detection, while magic-only falls through to the blended result.
    // -----------------------------------------------------------------------

    test('glob-only: *.rs resolves to text/rust via override registry', () {
      final result = detect(fileName: 'test.rs');
      expect(result.bestMatch, equals('text/rust'));
    });

    test(
      'full detection: *.rs resolves to text/rust via override registry',
      () {
        final bytes = File('test/data/programming/rust/test.rs')
            .readAsBytesSync();
        final result = detect(fileName: 'test.rs', bytes: bytes);
        expect(result.bestMatch, equals('text/rust'));
      },
    );

    test('magic-only: override registry has no magic rules for text/rust, '
        'falls through to blended result', () {
      // Without a file name the override registry cannot match (it only
      // has globs, no magic). The blended registry's magic result should
      // be returned instead.
      final bytes = File('test/data/programming/rust/test.rs')
          .readAsBytesSync();
      final result = detect(bytes: bytes);
      // The blended result for Rust source bytes is text/x-csrc (C source
      // magic heuristic). The override registry is not in play here.
      expect(result.bestMatch, equals('text/x-csrc'));
    });

    test('override registry does not interfere with unrelated file types', () {
      // PNG files have no entry in the override registry; the blended
      // result must be returned unchanged.
      final bytes = File('test/data/image/test.png').readAsBytesSync();
      final result = detect(fileName: 'test.png', bytes: bytes);
      expect(result.bestMatch, equals('image/png'));
    });
  });

  group('Caller-provided customRegistry', () {
    // -----------------------------------------------------------------------
    // Verify the three semantic requirements from the plan:
    //   1. Custom registry wins when it matches.
    //   2. null customRegistry is a no-op.
    //   3. Blended results are unchanged when no custom registry is supplied.
    // -----------------------------------------------------------------------

    test('custom registry wins when it matches (*.bingo → application/vnd.test.bingo)', () {
      final result = detect(
        fileName: 'my_data.bingo',
        customRegistry: _BingoRegistry(),
      );
      expect(result.bestMatch, equals('application/vnd.test.bingo'));
    });

    test('custom registry short-circuits override and blended registries', () {
      // _CustomRsRegistry maps *.rs to a fictional type at weight 80.
      // It should win over the override registry's text/rust entry (weight 60).
      final result = detect(
        fileName: 'test.rs',
        customRegistry: _CustomRsRegistry(),
      );
      expect(result.bestMatch, equals('application/vnd.test.custom-rs'));
    });

    test('null customRegistry is a no-op: blended results unchanged', () {
      final withNull = detect(
        fileName: 'test.png',
        // ignore: avoid_redundant_argument_values
        customRegistry: null,
      );
      final withoutParam = detect(fileName: 'test.png');
      expect(withNull.bestMatch, equals(withoutParam.bestMatch));
    });

    test('custom registry miss falls through to override registry', () {
      // The bingo registry does not match *.rs, so the override registry
      // (text/rust) should still fire.
      final result = detect(
        fileName: 'test.rs',
        customRegistry: _BingoRegistry(),
      );
      expect(result.bestMatch, equals('text/rust'));
    });

    test('custom registry miss falls through to blended registry', () {
      // The bingo registry does not match *.png, and there is no override
      // entry for png, so the blended registry must win.
      final bytes = File('test/data/image/test.png').readAsBytesSync();
      final result = detect(
        fileName: 'test.png',
        bytes: bytes,
        customRegistry: _BingoRegistry(),
      );
      expect(result.bestMatch, equals('image/png'));
    });

    test(
      'custom registry with bytes: bytes are forwarded to the custom registry',
      () {
        // _CustomPngMagicRegistry matches the PNG magic signature with no glob.
        // Supplying only bytes (no fileName) must trigger the magic match.
        final bytes = File('test/data/image/test.png').readAsBytesSync();
        final result = detect(
          bytes: bytes,
          customRegistry: _CustomPngMagicRegistry(),
        );
        expect(result.bestMatch, equals('application/vnd.test.custom-png'));
      },
    );
  });
}
