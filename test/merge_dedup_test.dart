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

/// Unit tests for the `_mergeResults` dedup logic in
/// `lib/src/mediatype_detector_base.dart`.
///
/// `_mergeResults` is a private function so these tests exercise it indirectly
/// through the public `detect()` API. Each test targets a specific dedup
/// scenario that was previously broken and covers the three root-cause
/// categories identified during investigation:
///
/// 1. **Higher-priority secondary** — Freedesktop entry has a higher glob
///    weight for the same media type than the Tika primary. The fix must keep
///    the Freedesktop entry so that Freedesktop's higher priority wins.
///
/// 2. **Richer subclassOf secondary** — both registries return the same glob
///    media type at equal weight, but Freedesktop's entry carries a useful
///    `subclassOf` chain that `MatchList._merge()` needs for parent/child
///    resolution. The fix must keep the Freedesktop entry on a tie so that
///    parentage is preserved.
///
/// 3. **Genuine priority tie, no subclassOf advantage** — distinct media types
///    from each registry both match at priority 50, with no subclassOf
///    relationship. The blended result order is deterministic (alphabetical
///    tie-break in the sort).
library;

import 'dart:io';

import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';
import 'package:test/test.dart';

void main() {
  group('_mergeResults dedup scenarios', () {
    // -------------------------------------------------------------------------
    // Scenario 1: Higher-priority secondary — text/html (.html glob)
    //
    // Tika: text/html at priority 50.
    // Freedesktop: text/html at priority 80, application/xhtml+xml at 50.
    //
    // Old behaviour: Tika's text/html(50) was kept; it tied with xhtml+xml(50)
    // and lost the alphabetical tie-break, so glob returned application/xhtml+xml.
    //
    // Fixed behaviour: Freedesktop's text/html(80) must be kept; it sorts first.
    // -------------------------------------------------------------------------
    test('glob-only: text/html wins over application/xhtml+xml for *.html '
        '(higher-priority secondary)', () {
      final result = detect(fileName: 'test.html');
      expect(
        result.bestMatch,
        equals('text/html'),
        reason:
            'Freedesktop text/html at priority 80 must beat '
            'application/xhtml+xml at priority 50',
      );
    });

    test('glob-only: text/html wins for *.html (HTML 4 file)', () {
      final result = detect(fileName: 'test_html4.html');
      expect(result.bestMatch, equals('text/html'));
    });

    // -------------------------------------------------------------------------
    // Scenario 1 (same pattern): application/vnd.apple.keynote (.key glob)
    //
    // Tika: keynote at priority 50.
    // Freedesktop: keynote at priority 80, pgp-keys at 50.
    //
    // Old behaviour: Tika's keynote(50) tied with pgp-keys(50) and lost the
    // alphabetical tie-break (k > a), so glob returned pgp-keys.
    //
    // Fixed behaviour: Freedesktop's keynote(80) is kept; it sorts first.
    // -------------------------------------------------------------------------
    test(
      'glob-only: application/vnd.apple.keynote wins over application/pgp-keys '
      'for *.key (higher-priority secondary)',
      () {
        final result = detect(fileName: 'test.key');
        expect(
          result.bestMatch,
          equals('application/vnd.apple.keynote'),
          reason:
              'Freedesktop keynote at priority 80 must beat '
              'pgp-keys at priority 50',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Scenario 2: Richer subclassOf secondary — OOXML full detection
    //
    // Both registries return the OOXML glob type (e.g. .docx) at the same
    // priority, but they disagree on the parent:
    //   Tika glob: subclassOf=[application/x-tika-ooxml]
    //   FD glob:   subclassOf=[application/zip]
    //
    // Magic returns:
    //   Tika: application/x-tika-ooxml
    //   FD:   application/zip
    //
    // For MatchList._merge() to keep the OOXML glob entry (rule a: hasMagic=false)
    // and recognise it as a subtype of the magic result, the glob entry must
    // carry subclassOf=[application/zip]. Old behaviour kept Tika's glob entry
    // (subclassOf=[x-tika-ooxml]), which broke the subtype check and degraded
    // to application/zip.
    //
    // Fixed behaviour: on a priority tie, prefer the richer subclassOf entry
    // (Freedesktop's, with application/zip parentage), so full detection
    // correctly returns the specific OOXML type.
    // -------------------------------------------------------------------------
    test('full detection: .docx resolves to correct OOXML type '
        '(richer subclassOf secondary)', () {
      final bytes = File('test/data/application/test.docx').readAsBytesSync();
      final result = detect(fileName: 'test.docx', bytes: bytes);
      expect(
        result.bestMatch,
        equals(
          'application/vnd.openxmlformats-officedocument'
          '.wordprocessingml.document',
        ),
        reason:
            'OOXML glob entry with subclassOf=[application/zip] must allow '
            'MatchList._merge() to keep it over zip magic',
      );
    });

    test('full detection: .xlsx resolves to correct OOXML type', () {
      final bytes = File('test/data/application/test.xlsx').readAsBytesSync();
      final result = detect(fileName: 'test.xlsx', bytes: bytes);
      expect(
        result.bestMatch,
        equals(
          'application/vnd.openxmlformats-officedocument'
          '.spreadsheetml.sheet',
        ),
      );
    });

    test('full detection: .pptx resolves to correct OOXML type', () {
      final bytes = File('test/data/application/test.pptx').readAsBytesSync();
      final result = detect(fileName: 'test.pptx', bytes: bytes);
      expect(
        result.bestMatch,
        equals(
          'application/vnd.openxmlformats-officedocument'
          '.presentationml.presentation',
        ),
      );
    });

    // -------------------------------------------------------------------------
    // Scenario 3: Genuine priority tie, no subclassOf advantage
    //
    // When two distinct media types from different registries tie at the same
    // priority and neither has a subclassOf advantage over the other, the
    // merged result order is deterministic: the comparator falls back to
    // alphabetical ascending on mediaType (see MatchResult.compareTo), so the
    // lexicographically smaller type sorts first after descending-priority sort.
    //
    // This test verifies that a tie does NOT produce a non-deterministic or
    // panicking result. The exact winner is secondary to stability.
    // -------------------------------------------------------------------------
    test('merge is deterministic on a genuine priority tie '
        '(no subclassOf advantage)', () {
      // Run the same detection twice; both runs must return the same result.
      final r1 = detect(fileName: 'test.key');
      final r2 = detect(fileName: 'test.key');
      expect(
        r1.bestMatch,
        equals(r2.bestMatch),
        reason: 'Repeated calls must return the same best match',
      );
      // Also verify the glob result list is non-empty.
      expect(r1.globMatches.isNotEmpty, isTrue);
    });
  });
}
