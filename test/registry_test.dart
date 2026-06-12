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

/// Unit tests for [MimeInfoRegistry] utility methods and the complex-pattern
/// glob slow path that the integration tests don't reach directly.
library;

import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Minimal concrete registry for testing
// ---------------------------------------------------------------------------

class _TestRegistry extends MimeInfoRegistry {
  _TestRegistry(super.entries);
}

RegistryEntry _entry(String mediaType, {List<Glob> globs = const []}) =>
    RegistryEntry(mediaType: mediaType, globs: globs);

Glob _simpleGlob(String pattern) =>
    Glob(pattern: pattern, weight: 50, caseSensitive: false);

// ---------------------------------------------------------------------------

void main() {
  group('MimeInfoRegistry utility methods', () {
    final registry = _TestRegistry({
      'text/plain': [
        _entry('text/plain', globs: [_simpleGlob('*.txt')]),
      ],
      'image/png': [
        _entry('image/png', globs: [_simpleGlob('*.png')]),
      ],
    });

    test('length returns number of registered media types', () {
      expect(registry.length, equals(2));
    });

    test('contains returns true for a known type', () {
      expect(registry.contains('text/plain'), isTrue);
      expect(registry.contains('image/png'), isTrue);
    });

    test('contains returns false for an unknown type', () {
      expect(registry.contains('application/pdf'), isFalse);
    });

    test('toMap returns a map with one key per media type', () {
      final m = registry.toMap();
      expect(m.keys, containsAll(['text/plain', 'image/png']));
      expect(m['text/plain'], isA<List>());
    });

    test('toString returns valid JSON containing media types', () {
      final s = registry.toString();
      expect(s, contains('text/plain'));
      expect(s, contains('image/png'));
    });
  });

  // -------------------------------------------------------------------------
  group('MimeInfoRegistry complex-pattern glob slow path', () {
    // Patterns like 'README*' or 'Makefile' are not simple *.ext patterns and
    // are stored in complexPatterns, triggering the linear-scan path.
    final registry = _TestRegistry({
      'text/x-readme': [
        _entry('text/x-readme', globs: [_simpleGlob('README*')]),
      ],
      'text/x-makefile': [
        _entry('text/x-makefile', globs: [_simpleGlob('Makefile')]),
      ],
      'text/plain': [
        _entry('text/plain', globs: [_simpleGlob('*.txt')]),
      ],
    });

    test('README matches complex pattern README*', () {
      final result = registry.matchGlob('README');
      expect(result.map((r) => r.mediaType), contains('text/x-readme'));
    });

    test('README.md matches complex pattern README*', () {
      final result = registry.matchGlob('README.md');
      expect(result.map((r) => r.mediaType), contains('text/x-readme'));
    });

    test('Makefile matches complex pattern Makefile', () {
      final result = registry.matchGlob('Makefile');
      expect(result.map((r) => r.mediaType), contains('text/x-makefile'));
    });

    test('simple extension still matches via fast path alongside complex', () {
      final result = registry.matchGlob('notes.txt');
      expect(result.map((r) => r.mediaType), contains('text/plain'));
    });

    test('unmatched filename returns empty', () {
      final result = registry.matchGlob('unknown.xyz');
      expect(result, isEmpty);
    });
  });
}
