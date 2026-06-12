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

/// Tests for ==, hashCode, and toMap on the core model types:
/// [Glob], [GenericIcon], [RootXML], [RegistryEntry], and [MatchResult].
library;

import 'dart:typed_data';

import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

RegistryEntry _entry(String mediaType) => RegistryEntry(mediaType: mediaType);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('Glob', () {
    final a = Glob(pattern: '*.png', weight: 80, caseSensitive: false);
    final b = Glob(pattern: '*.png', weight: 80, caseSensitive: false);
    final different = Glob(pattern: '*.jpg', weight: 50, caseSensitive: true);

    test('== equal instances', () => expect(a, equals(b)));
    test('== identical is equal', () => expect(a, equals(a)));
    test(
      '== different instances are not equal',
      () => expect(a, isNot(equals(different))),
    );
    test(
      'hashCode equal for equal instances',
      () => expect(a.hashCode, equals(b.hashCode)),
    );
    test(
      'hashCode differs for different instances',
      () => expect(a.hashCode, isNot(equals(different.hashCode))),
    );

    test('toMap contains expected keys', () {
      final m = a.toMap();
      expect(m['pattern'], equals('*.png'));
      expect(m['weight'], equals(80));
      expect(m['caseSensitive'], isFalse);
    });

    test('toString is valid JSON containing pattern', () {
      expect(a.toString(), contains('*.png'));
    });

    group('caseSensitive flag combinations', () {
      test('differs when caseSensitive differs', () {
        final cs = Glob(pattern: '*.png', weight: 80, caseSensitive: true);
        expect(a, isNot(equals(cs)));
        expect(a.hashCode, isNot(equals(cs.hashCode)));
      });

      test('differs when weight differs', () {
        final w = Glob(pattern: '*.png', weight: 50, caseSensitive: false);
        expect(a, isNot(equals(w)));
      });
    });
  });

  // -------------------------------------------------------------------------
  group('GenericIcon', () {
    test('tryParse returns correct enum for known value', () {
      expect(
        GenericIcon.tryParse('image-x-generic'),
        equals(GenericIcon.imageXGeneric),
      );
      expect(
        GenericIcon.tryParse('audio-x-generic'),
        equals(GenericIcon.audioXGeneric),
      );
      expect(GenericIcon.tryParse('folder'), equals(GenericIcon.folder));
    });

    test('tryParse returns null for unknown value', () {
      expect(GenericIcon.tryParse('does-not-exist'), isNull);
      expect(GenericIcon.tryParse(''), isNull);
    });

    test('toString returns the icon string value', () {
      expect(GenericIcon.imageXGeneric.toString(), equals('image-x-generic'));
      expect(GenericIcon.folder.toString(), equals('folder'));
    });

    test('value matches toString', () {
      for (final icon in GenericIcon.values) {
        expect(icon.toString(), equals(icon.value));
      }
    });

    test('round-trips through tryParse', () {
      for (final icon in GenericIcon.values) {
        expect(GenericIcon.tryParse(icon.value), equals(icon));
      }
    });
  });

  // -------------------------------------------------------------------------
  group('RootXML', () {
    final a = RootXML(
      namespaceURI: 'http://www.w3.org/2000/svg',
      localName: 'svg',
      weight: 80,
    );
    final b = RootXML(
      namespaceURI: 'http://www.w3.org/2000/svg',
      localName: 'svg',
      weight: 80,
    );
    final different = RootXML(
      namespaceURI: null,
      localName: 'html',
      weight: 50,
    );

    test('== equal instances', () => expect(a, equals(b)));
    test('== identical is equal', () => expect(a, equals(a)));
    test(
      '== different instances are not equal',
      () => expect(a, isNot(equals(different))),
    );
    test(
      'hashCode equal for equal instances',
      () => expect(a.hashCode, equals(b.hashCode)),
    );
    test(
      'hashCode differs for different instances',
      () => expect(a.hashCode, isNot(equals(different.hashCode))),
    );

    test('toMap contains expected keys', () {
      final m = a.toMap();
      expect(m['namespaceURI'], equals('http://www.w3.org/2000/svg'));
      expect(m['localName'], equals('svg'));
      expect(m['weight'], equals(80));
    });

    test('toMap with null namespaceURI', () {
      final m = different.toMap();
      expect(m['namespaceURI'], isNull);
      expect(m['localName'], equals('html'));
    });

    test('toString is valid JSON', () {
      expect(a.toString(), contains('svg'));
    });

    test('differs when namespaceURI differs', () {
      final c = RootXML(
        namespaceURI: 'http://other.ns',
        localName: 'svg',
        weight: 80,
      );
      expect(a, isNot(equals(c)));
      expect(a.hashCode, isNot(equals(c.hashCode)));
    });

    test('differs when localName differs', () {
      final c = RootXML(
        namespaceURI: 'http://www.w3.org/2000/svg',
        localName: 'g',
        weight: 80,
      );
      expect(a, isNot(equals(c)));
    });

    test('differs when weight differs', () {
      final c = RootXML(
        namespaceURI: 'http://www.w3.org/2000/svg',
        localName: 'svg',
        weight: 50,
      );
      expect(a, isNot(equals(c)));
    });

    test('matches valid XML with correct root element', () {
      final xml = Uint8List.fromList(
        '<svg xmlns="http://www.w3.org/2000/svg"></svg>'.codeUnits,
      );
      expect(a.matches(xml), isTrue);
    });

    test('does not match XML with wrong root element', () {
      final xml = Uint8List.fromList(
        '<html xmlns="http://www.w3.org/1999/xhtml"></html>'.codeUnits,
      );
      expect(a.matches(xml), isFalse);
    });

    test('returns false for non-XML bytes', () {
      final notXml = Uint8List.fromList('this is not xml'.codeUnits);
      expect(a.matches(notXml), isFalse);
    });

    test('returns false for empty bytes', () {
      expect(a.matches(Uint8List(0)), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('RegistryEntry', () {
    final a = RegistryEntry(
      mediaType: 'image/png',
      genericIcon: GenericIcon.imageXGeneric,
      globs: [Glob(pattern: '*.png', weight: 80, caseSensitive: false)],
      subclassOf: ['image/x-png'],
      alias: ['image/x-png'],
    );
    final b = RegistryEntry(
      mediaType: 'image/png',
      genericIcon: GenericIcon.imageXGeneric,
      globs: [Glob(pattern: '*.png', weight: 80, caseSensitive: false)],
      subclassOf: ['image/x-png'],
      alias: ['image/x-png'],
    );
    final minimal = RegistryEntry(mediaType: 'text/plain');
    final different = RegistryEntry(mediaType: 'image/jpeg');

    test('== equal instances', () => expect(a, equals(b)));
    test('== identical is equal', () => expect(a, equals(a)));
    test(
      '== minimal equal instances',
      () => expect(minimal, equals(RegistryEntry(mediaType: 'text/plain'))),
    );
    test('== different mediaType', () => expect(a, isNot(equals(different))));
    test(
      'hashCode equal for equal instances',
      () => expect(a.hashCode, equals(b.hashCode)),
    );
    test(
      'hashCode differs for different instances',
      () => expect(a.hashCode, isNot(equals(different.hashCode))),
    );

    test('toMap contains mediaType', () {
      expect(a.toMap()['mediaType'], equals('image/png'));
    });

    test('toMap includes genericIcon when set', () {
      expect(a.toMap()['genericIcon'], equals('image-x-generic'));
    });

    test('toMap omits optional fields when absent', () {
      final m = minimal.toMap();
      expect(m.containsKey('genericIcon'), isFalse);
      expect(m.containsKey('acronym'), isFalse);
      expect(m.containsKey('alias'), isFalse);
      expect(m.containsKey('subclassOf'), isFalse);
      expect(m.containsKey('globs'), isFalse);
      expect(m.containsKey('magic'), isFalse);
      expect(m.containsKey('rootXML'), isFalse);
    });

    test('toMap includes globs when set', () {
      final m = a.toMap();
      expect(m.containsKey('globs'), isTrue);
      expect((m['globs'] as List).length, equals(1));
    });

    test('toMap includes alias and subclassOf when set', () {
      final m = a.toMap();
      expect(m['alias'], equals(['image/x-png']));
      expect(m['subclassOf'], equals(['image/x-png']));
    });

    test('toString is valid JSON containing mediaType', () {
      expect(a.toString(), contains('image/png'));
    });

    test('accessors return unmodifiable views', () {
      expect(
        () => a.globs.add(
          Glob(pattern: '*.bmp', weight: 50, caseSensitive: false),
        ),
        throwsUnsupportedError,
      );
      expect(() => a.alias.add('x'), throwsUnsupportedError);
      expect(() => a.subclassOf.add('x'), throwsUnsupportedError);
    });

    test('entry with magic toMap includes magic key', () {
      final entry = RegistryEntry(
        mediaType: 'application/pdf',
        magic: [
          Magic(
            priority: 80,
            matches: [
              Match.factory(type: MatchType.string, value: '%PDF', offset: '0'),
            ],
          ),
        ],
      );
      expect(entry.toMap().containsKey('magic'), isTrue);
    });

    test('entry with rootXML toMap includes rootXML key', () {
      final entry = RegistryEntry(
        mediaType: 'image/svg+xml',
        rootXML: [
          RootXML(namespaceURI: 'http://www.w3.org/2000/svg', localName: 'svg'),
        ],
      );
      expect(entry.toMap().containsKey('rootXML'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('MatchResult', () {
    final entryPng = _entry('image/png');
    final entryJpeg = _entry('image/jpeg');

    final a = MatchResult(priority: 80, entry: entryPng);
    final b = MatchResult(priority: 80, entry: entryPng);
    final differentPriority = MatchResult(priority: 50, entry: entryPng);
    final differentType = MatchResult(priority: 80, entry: entryJpeg);

    test('== equal instances', () => expect(a, equals(b)));
    test('== identical is equal', () => expect(a, equals(a)));
    test(
      '== different priority',
      () => expect(a, isNot(equals(differentPriority))),
    );
    test(
      '== different mediaType',
      () => expect(a, isNot(equals(differentType))),
    );
    test(
      'hashCode equal for equal instances',
      () => expect(a.hashCode, equals(b.hashCode)),
    );
    test(
      'hashCode differs on priority',
      () => expect(a.hashCode, isNot(equals(differentPriority.hashCode))),
    );
    test(
      'hashCode differs on mediaType',
      () => expect(a.hashCode, isNot(equals(differentType.hashCode))),
    );

    test('toMap contains priority and mediaType', () {
      final m = a.toMap();
      expect(m['priority'], equals(80));
      expect(m['mediaType'], equals('image/png'));
    });

    test('toString is valid JSON', () {
      expect(a.toString(), contains('image/png'));
      expect(a.toString(), contains('80'));
    });

    test(
      'mediaType delegates to entry',
      () => expect(a.mediaType, equals('image/png')),
    );
    test(
      'hasMagic false when entry has no magic',
      () => expect(a.hasMagic, isFalse),
    );

    test('hasMagic true when entry has magic', () {
      final magicEntry = RegistryEntry(
        mediaType: 'application/pdf',
        magic: [
          Magic(
            priority: 80,
            matches: [
              Match.factory(type: MatchType.string, value: '%PDF', offset: '0'),
            ],
          ),
        ],
      );
      expect(MatchResult(priority: 80, entry: magicEntry).hasMagic, isTrue);
    });

    group('compareTo', () {
      test('higher priority sorts first', () {
        expect(a.compareTo(differentPriority), isNegative);
        expect(differentPriority.compareTo(a), isPositive);
      });

      test('equal priority sorts by mediaType alphabetically', () {
        // 'image/jpeg' < 'image/png' lexicographically
        expect(a.compareTo(differentType), isPositive);
        expect(differentType.compareTo(a), isNegative);
      });

      test('equal priority and mediaType returns zero', () {
        expect(a.compareTo(b), equals(0));
      });
    });
  });
}
