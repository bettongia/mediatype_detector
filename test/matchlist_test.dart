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

/// Unit tests for [MatchList] getters and [MatchList._merge] conflict-resolution
/// branches that are not reached by the integration test suite.
library;

import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers — minimal RegistryEntry builders
// ---------------------------------------------------------------------------

RegistryEntry _plain(String mediaType, {List<String> subclassOf = const []}) =>
    RegistryEntry(mediaType: mediaType, subclassOf: subclassOf);

RegistryEntry _withMagic(
  String mediaType, {
  List<String> subclassOf = const [],
}) => RegistryEntry(
  mediaType: mediaType,
  subclassOf: subclassOf,
  magic: [
    Magic(
      priority: 80,
      matches: [
        Match.factory(type: MatchType.string, value: 'SIG', offset: '0'),
      ],
    ),
  ],
);

MatchResult _r(RegistryEntry entry, {int priority = 50}) =>
    MatchResult(priority: priority, entry: entry);

// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('MatchList getters', () {
    final glob = _r(_plain('text/plain'));
    final magic = _r(_plain('image/png'));
    final xml = _r(_plain('image/svg+xml'));

    final list = MatchList(
      globMatches: [glob],
      magicMatches: [magic],
      rootXmlMatches: [xml],
    );

    test('globMatches returns the glob results', () {
      expect(list.globMatches.toList(), equals([glob]));
    });

    test('magicMatches returns the magic results', () {
      expect(list.magicMatches.toList(), equals([magic]));
    });

    test('rootXmlMatches returns the rootXml results', () {
      expect(list.rootXmlMatches.toList(), equals([xml]));
    });

    test('merged returns unmodifiable list', () {
      expect(() => (list.merged as dynamic).add(glob), throwsUnsupportedError);
    });

    test('candidates includes types from all strategies', () {
      final types = list.candidates.toList();
      expect(types, contains('text/plain'));
      expect(types, contains('image/png'));
      expect(types, contains('image/svg+xml'));
    });

    test('candidates deduplicates repeated mediaType', () {
      final dup = MatchList(
        globMatches: [_r(_plain('text/plain'))],
        magicMatches: [_r(_plain('text/plain'))],
      );
      expect(dup.candidates.toList(), equals(['text/plain']));
    });

    test('combined returns MatchResult objects from all strategies', () {
      final types = list.combined.map((r) => r.mediaType).toSet();
      expect(types, containsAll(['text/plain', 'image/png', 'image/svg+xml']));
    });

    test('isEmpty is true when all lists empty', () {
      expect(MatchList().isEmpty, isTrue);
    });

    test('isEmpty is false when any list non-empty', () {
      expect(MatchList(globMatches: [glob]).isEmpty, isFalse);
    });

    test('bestMatch returns null when empty', () {
      expect(MatchList().bestMatch, isNull);
    });

    test('bestMatch returns first merged result', () {
      // rootXml dominates — bestMatch is the xml type.
      expect(list.bestMatch, equals('image/svg+xml'));
    });
  });

  // -------------------------------------------------------------------------
  group('MatchList._merge — rootXML is definitive', () {
    test('rootXml results bypass glob and magic', () {
      final list = MatchList(
        globMatches: [_r(_plain('text/plain'))],
        magicMatches: [_r(_plain('application/octet-stream'))],
        rootXmlMatches: [_r(_plain('image/svg+xml'), priority: 80)],
      );
      expect(list.bestMatch, equals('image/svg+xml'));
      expect(list.merged.length, equals(1));
    });
  });

  // -------------------------------------------------------------------------
  group('MatchList._merge — glob-only mode', () {
    test('returns glob results when no magic', () {
      final list = MatchList(globMatches: [_r(_plain('text/plain'))]);
      expect(list.bestMatch, equals('text/plain'));
    });

    test('empty glob and no magic returns empty', () {
      expect(MatchList().merged, isEmpty);
    });

    test('keeps parent, drops child when only glob matches', () {
      // child subclassOf parent — without magic, prefer parent (more conservative)
      final parent = _plain('application/zip');
      final child = _plain(
        'application/vnd.oasis.opendocument.text',
        subclassOf: ['application/zip'],
      );
      final list = MatchList(
        globMatches: [_r(parent, priority: 50), _r(child, priority: 50)],
      );
      final types = list.merged.map((r) => r.mediaType).toList();
      expect(types, contains('application/zip'));
      expect(types, isNot(contains('application/vnd.oasis.opendocument.text')));
    });
  });

  // -------------------------------------------------------------------------
  group('MatchList._merge — full-match mode glob filter', () {
    // Line 133: glob entry retained because magic confirmed the SAME type.
    test(
      'keeps glob entry when magic confirmed the same type (hasMagic=true)',
      () {
        final entry = _withMagic('image/png');
        final list = MatchList(
          globMatches: [_r(entry, priority: 80)],
          magicMatches: [_r(entry, priority: 80)],
        );
        expect(list.merged.map((r) => r.mediaType), contains('image/png'));
      },
    );

    // Line 133 false branch → line 136: glob entry retained because magic
    // confirmed a PARENT type listed in subclassOf.
    test('keeps glob entry when magic confirmed a subclassOf parent', () {
      final zipEntry = _withMagic('application/zip');
      final odtEntry = _withMagic(
        'application/vnd.oasis.opendocument.text',
        subclassOf: ['application/zip'],
      );
      final list = MatchList(
        // glob matched the specific ODT type
        globMatches: [_r(odtEntry, priority: 80)],
        // magic only confirmed ZIP (the parent)
        magicMatches: [_r(zipEntry, priority: 60)],
      );
      final types = list.merged.map((r) => r.mediaType).toList();
      expect(types, contains('application/vnd.oasis.opendocument.text'));
    });

    // Line 136 false: glob entry dropped because hasMagic=true but neither
    // type nor parent was confirmed by magic.
    test('drops glob entry when magic did not confirm type or parent', () {
      final pngEntry = _withMagic('image/png');
      final jpegEntry = _withMagic('image/jpeg');
      final list = MatchList(
        // glob matched PNG (has magic)
        globMatches: [_r(pngEntry, priority: 80)],
        // magic only confirmed JPEG — unrelated to PNG
        magicMatches: [_r(jpegEntry, priority: 80)],
      );
      final types = list.merged.map((r) => r.mediaType).toList();
      expect(types, isNot(contains('image/png')));
      expect(types, contains('image/jpeg'));
    });

    // Doubly-confirmed types sort before magic-only types.
    test('doubly-confirmed type ranks above magic-only type', () {
      final png = _withMagic('image/png');
      final jpeg = _withMagic('image/jpeg');
      final list = MatchList(
        globMatches: [_r(png, priority: 50)],
        magicMatches: [_r(png, priority: 50), _r(jpeg, priority: 80)],
      );
      // PNG is doubly confirmed (glob+magic); JPEG is magic-only.
      // PNG should appear first despite jpeg having equal or higher priority.
      expect(list.merged.first.mediaType, equals('image/png'));
    });

    // Parent-child rule (a): child in magic → child wins, parent dropped.
    test('child wins over parent when child is in magic results', () {
      final parent = _withMagic('application/zip');
      final child = _withMagic(
        'application/vnd.oasis.opendocument.text',
        subclassOf: ['application/zip'],
      );
      final list = MatchList(
        globMatches: [_r(parent, priority: 50), _r(child, priority: 50)],
        magicMatches: [_r(child, priority: 80)],
      );
      final types = list.merged.map((r) => r.mediaType).toList();
      expect(types, contains('application/vnd.oasis.opendocument.text'));
      expect(types, isNot(contains('application/zip')));
    });

    // Parent-child rule (b): doubly-confirmed parent → child dropped.
    test('doubly-confirmed parent wins over non-magic child', () {
      final parent = _withMagic('application/zip');
      // child has magic rules but was NOT in magic results for this file
      final child = _withMagic(
        'application/x-compressed-tar',
        subclassOf: ['application/zip'],
      );
      final list = MatchList(
        // both matched by glob
        globMatches: [_r(parent, priority: 80), _r(child, priority: 50)],
        // only parent confirmed by magic → parent is doubly-confirmed
        magicMatches: [_r(parent, priority: 80)],
      );
      final types = list.merged.map((r) => r.mediaType).toList();
      expect(types, contains('application/zip'));
      expect(types, isNot(contains('application/x-compressed-tar')));
    });
  });
}
