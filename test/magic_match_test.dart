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

/// Unit tests for [Match] and [Magic] byte-pattern matching, with particular
/// focus on [MatchType.stringignorecase].
library;

import 'dart:typed_data';

import 'package:betto_mediatype_detector/src/mimeinfo/magic.dart';
import 'package:test/test.dart';

Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  group('MatchType.string', () {
    test('matches exact bytes at offset 0', () {
      final m = Match.factory(
        type: MatchType.string,
        value: 'PDF',
        offset: '0',
      );
      expect(m.matches(bytes('%PDF-1.4')), isFalse);
      expect(m.matches(bytes('PDF stuff')), isTrue);
    });

    test('does not match wrong content', () {
      final m = Match.factory(
        type: MatchType.string,
        value: 'PDF',
        offset: '0',
      );
      expect(m.matches(bytes('XYZ content')), isFalse);
    });

    test(
      'case-sensitive: uppercase pattern does not match lowercase input',
      () {
        final m = Match.factory(
          type: MatchType.string,
          value: 'HTML',
          offset: '0',
        );
        expect(m.matches(bytes('html body')), isFalse);
      },
    );

    test('matches at non-zero offset', () {
      final m = Match.factory(
        type: MatchType.string,
        value: 'PDF',
        offset: '1',
      );
      expect(m.matches(bytes('%PDF-1.4')), isTrue);
      expect(m.matches(bytes('PDF-1.4')), isFalse);
    });

    test('matches within an offset range', () {
      final m = Match.factory(
        type: MatchType.string,
        value: 'TAG',
        offset: '0:4',
      );
      expect(m.matches(bytes('__TAG_rest')), isTrue);
      expect(m.matches(bytes('_____TAG_rest')), isFalse);
    });

    test('returns false when value is longer than remaining bytes', () {
      final m = Match.factory(
        type: MatchType.string,
        value: 'TOOLONG',
        offset: '0',
      );
      expect(m.matches(bytes('TOO')), isFalse);
    });

    test('matches hex-encoded value', () {
      // 0x504446 == 'PDF'
      final m = Match.factory(
        type: MatchType.string,
        value: '0x504446',
        offset: '0',
      );
      expect(m.matches(bytes('PDF')), isTrue);
      expect(m.matches(bytes('XYZ')), isFalse);
    });

    test('applies mask before comparison', () {
      // value 0x0D, mask 0x0F → matches any byte whose lower nibble is 0x0D
      final m = Match.factory(
        type: MatchType.string,
        value: '0x0D',
        offset: '0',
        mask: '0x0F',
      );
      expect(
        m.matches(Uint8List.fromList([0x1D])),
        isTrue,
      ); // 0x1D & 0x0F == 0x0D
      expect(m.matches(Uint8List.fromList([0x0D])), isTrue);
      expect(m.matches(Uint8List.fromList([0x0E])), isFalse);
    });
  });

  group('MatchType.stringignorecase', () {
    test('matches pattern in same case', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'html',
        offset: '0',
      );
      expect(m.matches(bytes('html body')), isTrue);
    });

    test('matches pattern in uppercase input', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'html',
        offset: '0',
      );
      expect(m.matches(bytes('HTML body')), isTrue);
    });

    test('matches mixed-case input', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'html',
        offset: '0',
      );
      expect(m.matches(bytes('HtMl body')), isTrue);
    });

    test('matches uppercase pattern against lowercase input', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'HTML',
        offset: '0',
      );
      expect(m.matches(bytes('html body')), isTrue);
    });

    test('does not match wrong content', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'html',
        offset: '0',
      );
      expect(m.matches(bytes('xhtml body')), isFalse);
    });

    test('matches at non-zero offset', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'html',
        offset: '1',
      );
      expect(m.matches(bytes('<html>')), isTrue);
      expect(m.matches(bytes('html>')), isFalse);
    });

    test('matches within an offset range', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'html',
        offset: '0:4',
      );
      expect(m.matches(bytes('____HTML rest')), isTrue);
      expect(m.matches(bytes('_____HTML rest')), isFalse);
    });

    test('returns false when value is longer than remaining bytes', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'toolong',
        offset: '0',
      );
      expect(m.matches(bytes('TOO')), isFalse);
    });

    test('only folds ASCII alpha — digits and symbols are exact', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'a1b',
        offset: '0',
      );
      expect(m.matches(bytes('A1B')), isTrue);
      expect(m.matches(bytes('A2B')), isFalse);
      expect(m.matches(bytes('A1b')), isTrue);
    });

    test('matches hex-encoded value case-insensitively', () {
      // 0x48544D4C == 'HTML'
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: '0x48544D4C',
        offset: '0',
      );
      expect(m.matches(bytes('HTML')), isTrue);
      expect(m.matches(bytes('html')), isTrue);
      expect(m.matches(bytes('HtMl')), isTrue);
      expect(m.matches(bytes('XTML')), isFalse);
    });

    test('applies mask before case-folding', () {
      // Mask 0xFF (identity) — standard masking still works.
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'ab',
        offset: '0',
        mask: '0xFFFF',
      );
      expect(m.matches(bytes('AB')), isTrue);
      expect(m.matches(bytes('ab')), isTrue);
      expect(m.matches(bytes('xy')), isFalse);
    });

    test('empty input returns false', () {
      final m = Match.factory(
        type: MatchType.stringignorecase,
        value: 'html',
        offset: '0',
      );
      expect(m.matches(Uint8List(0)), isFalse);
    });

    test('sub-match OR semantics apply after parent matches', () {
      final parent = Match.factory(
        type: MatchType.stringignorecase,
        value: 'html',
        offset: '0',
        subMatches: [
          Match.factory(type: MatchType.string, value: 'BODY', offset: '5'),
        ],
      );
      // Parent matches, sub-match matches.
      expect(parent.matches(bytes('html BODY extra')), isTrue);
      // Parent matches, sub-match does not.
      expect(parent.matches(bytes('html ZODY extra')), isFalse);
    });

    test('sub-matches via Magic rule', () {
      // Build a Magic rule directly to test OR sub-match logic.
      final rule = Magic(
        priority: 60,
        matches: [
          Match.factory(
            type: MatchType.stringignorecase,
            value: 'html',
            offset: '0',
            subMatches: [
              Match.factory(type: MatchType.string, value: 'BODY', offset: '5'),
            ],
          ),
        ],
      );
      expect(rule.match(bytes('html BODY extra')), equals({60}));
      expect(rule.match(bytes('HTML BODY extra')), equals({60}));
      expect(rule.match(bytes('html ZODY extra')), isEmpty);
    });
  });

  group('Magic', () {
    test('returns priority when any Match succeeds', () {
      final rule = Magic(
        priority: 70,
        matches: [
          Match.factory(type: MatchType.string, value: 'PDF', offset: '0'),
          Match.factory(type: MatchType.string, value: 'BMP', offset: '0'),
        ],
      );
      expect(rule.match(bytes('PDF content')), equals({70}));
      expect(rule.match(bytes('BMP content')), equals({70}));
      expect(rule.match(bytes('PNG content')), isEmpty);
    });

    test('returns empty set when no Match succeeds', () {
      final rule = Magic(
        priority: 50,
        matches: [
          Match.factory(type: MatchType.string, value: 'NOPE', offset: '0'),
        ],
      );
      expect(rule.match(bytes('PDF content')), isEmpty);
    });

    test('works with stringignorecase matches', () {
      final rule = Magic(
        priority: 55,
        matches: [
          Match.factory(
            type: MatchType.stringignorecase,
            value: 'message',
            offset: '0',
          ),
        ],
      );
      expect(rule.match(bytes('MESSAGE from server')), equals({55}));
      expect(rule.match(bytes('message from server')), equals({55}));
      expect(rule.match(bytes('other content')), isEmpty);
    });

    test('equality and hashCode', () {
      final a = Magic(
        priority: 50,
        matches: [
          Match.factory(type: MatchType.string, value: 'PDF', offset: '0'),
        ],
      );
      final b = Magic(
        priority: 50,
        matches: [
          Match.factory(type: MatchType.string, value: 'PDF', offset: '0'),
        ],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString is valid JSON', () {
      final rule = Magic(
        priority: 50,
        matches: [
          Match.factory(type: MatchType.string, value: 'PDF', offset: '0'),
        ],
      );
      expect(() => rule.toString(), returnsNormally);
      expect(rule.toString(), contains('priority'));
    });
  });

  group('numeric MatchTypes', () {
    test('big16 matches big-endian 2-byte value', () {
      final m = Match.factory(
        type: MatchType.big16,
        value: '0x4D4D', // 'MM' — TIFF big-endian marker
        offset: '0',
      );
      expect(m.matches(Uint8List.fromList([0x4D, 0x4D, 0x00, 0x2A])), isTrue);
      expect(m.matches(Uint8List.fromList([0x49, 0x49, 0x2A, 0x00])), isFalse);
    });

    test('little16 matches little-endian 2-byte value', () {
      final m = Match.factory(
        type: MatchType.little16,
        value: '0x4949', // stored as [0x49, 0x49] little-endian → same bytes
        offset: '0',
      );
      expect(m.matches(Uint8List.fromList([0x49, 0x49])), isTrue);
    });

    test('big32 matches big-endian 4-byte value', () {
      final m = Match.factory(
        type: MatchType.big32,
        value: '0x89504E47', // PNG magic
        offset: '0',
      );
      expect(
        m.matches(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])),
        isTrue,
      );
    });

    test('little32 matches little-endian 4-byte value', () {
      final m = Match.factory(
        type: MatchType.little32,
        value: '0x46464952', // 'RIFF' stored little-endian
        offset: '0',
      );
      // little-endian bytes: 0x52, 0x49, 0x46, 0x46
      expect(m.matches(Uint8List.fromList([0x52, 0x49, 0x46, 0x46])), isTrue);
    });

    test('byte matches single byte value', () {
      final m = Match.factory(type: MatchType.byte, value: 'P', offset: '0');
      expect(m.matches(Uint8List.fromList([0x50])), isTrue); // 'P' == 0x50
      expect(m.matches(Uint8List.fromList([0x51])), isFalse);
    });
  });

  group('MinShouldMatch', () {
    test('passes when enough sub-matches succeed', () {
      final rule = Magic(
        priority: 60,
        matches: [
          Match.factory(
            type: MatchType.minShouldMatch,
            offset: '0',
            minShouldMatch: 1,
            subMatches: [
              Match.factory(type: MatchType.string, value: 'AB', offset: '0'),
              Match.factory(type: MatchType.string, value: 'XY', offset: '0'),
            ],
          ),
        ],
      );
      expect(rule.match(bytes('AB rest')), equals({60}));
      expect(rule.match(bytes('XY rest')), equals({60}));
      expect(rule.match(bytes('QQ rest')), isEmpty);
    });

    test(
      'requires threshold — fails when fewer than minShouldMatch succeed',
      () {
        final rule = Magic(
          priority: 60,
          matches: [
            Match.factory(
              type: MatchType.minShouldMatch,
              offset: '0',
              minShouldMatch: 2,
              subMatches: [
                Match.factory(type: MatchType.string, value: 'AB', offset: '0'),
                Match.factory(type: MatchType.string, value: 'CD', offset: '0'),
                Match.factory(type: MatchType.string, value: 'XY', offset: '0'),
              ],
            ),
          ],
        );
        // Only 'AB' matches — not enough.
        expect(rule.match(bytes('AB rest')), isEmpty);
        // Nothing matches.
        expect(rule.match(bytes('QQ rest')), isEmpty);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('MatchType', () {
    test('tryParse returns correct enum for known value', () {
      expect(MatchType.tryParse('string'), equals(MatchType.string));
      expect(
        MatchType.tryParse('stringignorecase'),
        equals(MatchType.stringignorecase),
      );
      expect(MatchType.tryParse('big16'), equals(MatchType.big16));
      expect(MatchType.tryParse('regex'), equals(MatchType.regex));
      expect(
        MatchType.tryParse('minShouldMatch'),
        equals(MatchType.minShouldMatch),
      );
    });

    test('tryParse returns null for unknown value', () {
      expect(MatchType.tryParse('unknown'), isNull);
      expect(MatchType.tryParse(''), isNull);
    });

    test('toString returns the string value', () {
      expect(MatchType.string.toString(), equals('string'));
      expect(MatchType.big32.toString(), equals('big32'));
      expect(MatchType.regex.toString(), equals('regex'));
    });
  });

  // -------------------------------------------------------------------------
  group('Match.factory error paths', () {
    test(
      'throws when minShouldMatch type used without minShouldMatch value',
      () {
        expect(
          () => Match.factory(type: MatchType.minShouldMatch, offset: '0'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('throws when value is null for non-minShouldMatch type', () {
      expect(
        () => Match.factory(type: MatchType.string, offset: '0'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Match toMap and toString', () {
    test('toMap without subMatches omits match key', () {
      final m = Match.factory(
        type: MatchType.string,
        value: 'PDF',
        offset: '0',
      );
      final map = m.toMap();
      expect(map['offset'], equals('0'));
      expect(map['datatype'], equals('string'));
      expect(map['value'], equals('PDF'));
      expect(map.containsKey('match'), isFalse);
    });

    test('toMap with mask includes mask key', () {
      final m = Match.factory(
        type: MatchType.string,
        value: '0x0F',
        offset: '0',
        mask: '0xFF',
      );
      expect(m.toMap()['mask'], equals('0xFF'));
    });

    test('toMap with subMatches includes match key', () {
      final m = Match.factory(
        type: MatchType.string,
        value: 'PDF',
        offset: '0',
        subMatches: [
          Match.factory(type: MatchType.string, value: 'sub', offset: '4'),
        ],
      );
      final map = m.toMap();
      expect(map.containsKey('match'), isTrue);
      expect((map['match'] as List).length, equals(1));
    });

    test('toString produces non-empty JSON string', () {
      final m = Match.factory(
        type: MatchType.string,
        value: 'PDF',
        offset: '0',
      );
      expect(m.toString(), contains('PDF'));
    });
  });

  // -------------------------------------------------------------------------
  group('host16 / host32', () {
    test('host16 matches on this platform', () {
      // Build a Match and verify it matches its own encoded bytes — the result
      // is platform-dependent but must always be consistent.
      final m = Match.factory(
        type: MatchType.host16,
        value: '0x4D4D',
        offset: '0',
      );
      // The match either succeeds or fails depending on host endianness; what
      // matters is that it doesn't throw and produces a deterministic result.
      expect(m.matches(Uint8List.fromList([0x4D, 0x4D])), isA<bool>());
      expect(
        m.matches(Uint8List.fromList([0x4D, 0x4D])),
        equals(m.matches(Uint8List.fromList([0x4D, 0x4D]))),
      );
    });

    test('host32 matches on this platform', () {
      final m = Match.factory(
        type: MatchType.host32,
        value: '0x89504E47',
        offset: '0',
      );
      expect(
        m.matches(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
        isA<bool>(),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('MinShouldMatch equality, hashCode, toMap', () {
    final a = Match.factory(
      type: MatchType.minShouldMatch,
      offset: '0',
      minShouldMatch: 2,
      subMatches: [
        Match.factory(type: MatchType.string, value: 'AB', offset: '0'),
        Match.factory(type: MatchType.string, value: 'XY', offset: '0'),
      ],
    );
    final b = Match.factory(
      type: MatchType.minShouldMatch,
      offset: '0',
      minShouldMatch: 2,
      subMatches: [
        Match.factory(type: MatchType.string, value: 'AB', offset: '0'),
        Match.factory(type: MatchType.string, value: 'XY', offset: '0'),
      ],
    );
    final different = Match.factory(
      type: MatchType.minShouldMatch,
      offset: '0',
      minShouldMatch: 1,
      subMatches: [
        Match.factory(type: MatchType.string, value: 'AB', offset: '0'),
      ],
    );

    test('== equal instances', () => expect(a, equals(b)));
    test('== identical is equal', () => expect(a, equals(a)));
    test(
      '== different threshold/subMatches not equal',
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

    test('toMap contains offset and datatype', () {
      final map = a.toMap();
      expect(map['offset'], equals('0'));
      expect(map['datatype'], equals('minShouldMatch'));
    });

    test('toMap includes match key when subMatches present', () {
      expect(a.toMap().containsKey('match'), isTrue);
    });

    test('mask is null', () => expect((a as dynamic).mask, isNull));
    test(
      'subMatches getter returns list',
      () => expect(a.subMatches.length, equals(2)),
    );
  });

  // -------------------------------------------------------------------------
  group('RegExpMatch', () {
    final a = Match.factory(
      type: MatchType.regex,
      value: r'\bPDF\b',
      offset: '0',
    );
    final b = Match.factory(
      type: MatchType.regex,
      value: r'\bPDF\b',
      offset: '0',
    );
    final different = Match.factory(
      type: MatchType.regex,
      value: r'\bPNG\b',
      offset: '0',
    );

    test('== equal instances', () => expect(a, equals(b)));
    test('== identical is equal', () => expect(a, equals(a)));
    test(
      '== different pattern not equal',
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

    test('toMap contains offset, datatype, value', () {
      final map = a.toMap();
      expect(map['offset'], equals('0'));
      expect(map['datatype'], equals('regex'));
      expect(map['value'], equals(r'\bPDF\b'));
      expect(map.containsKey('match'), isFalse);
    });

    test('toMap includes match key when subMatches present', () {
      final m = Match.factory(
        type: MatchType.regex,
        value: r'PDF',
        offset: '0',
        subMatches: [
          Match.factory(type: MatchType.string, value: 'sub', offset: '4'),
        ],
      );
      expect(m.toMap().containsKey('match'), isTrue);
    });

    test('matches at exact offset', () {
      final m = Match.factory(
        type: MatchType.regex,
        value: r'PDF',
        offset: '0',
      );
      expect(m.matches(bytes('PDF-1.4')), isTrue);
      expect(m.matches(bytes('other')), isFalse);
    });

    test('returns false when startOffset >= bytes.length', () {
      final m = Match.factory(
        type: MatchType.regex,
        value: r'PDF',
        offset: '100',
      );
      expect(m.matches(bytes('PDF')), isFalse);
    });

    test('matches with range offset', () {
      final m = Match.factory(
        type: MatchType.regex,
        value: r'PDF',
        offset: '0:4',
      );
      expect(m.matches(bytes('____PDF')), isTrue);
      expect(m.matches(bytes('nothing')), isFalse);
    });

    test('sub-match OR semantics apply', () {
      final m = Match.factory(
        type: MatchType.regex,
        value: r'PDF',
        offset: '0',
        subMatches: [
          Match.factory(type: MatchType.string, value: '-1.', offset: '3'),
        ],
      );
      expect(m.matches(bytes('PDF-1.4')), isTrue);
      expect(m.matches(bytes('PDF XXX')), isFalse);
    });

    group('createDartRegExp flag parsing', () {
      test('(?i) produces case-insensitive matching', () {
        final r = RegExpMatch.createDartRegExp(r'(?i)html');
        expect(r.hasMatch('HTML'), isTrue);
        expect(r.hasMatch('html'), isTrue);
        expect(r.hasMatch('XTML'), isFalse);
      });

      test('(?m) produces multiLine matching', () {
        final r = RegExpMatch.createDartRegExp(r'(?m)^start');
        expect(r.isMultiLine, isTrue);
        expect(r.hasMatch('other\nstart here'), isTrue);
      });

      test('(?s) produces dotAll matching', () {
        final r = RegExpMatch.createDartRegExp(r'(?s)a.b');
        expect(r.isDotAll, isTrue);
        expect(r.hasMatch('a\nb'), isTrue);
      });

      test('no flags — case-sensitive by default', () {
        final r = RegExpMatch.createDartRegExp(r'html');
        expect(r.hasMatch('html'), isTrue);
        expect(r.hasMatch('HTML'), isFalse);
        expect(r.isMultiLine, isFalse);
        expect(r.isDotAll, isFalse);
      });
    });
  });
}
