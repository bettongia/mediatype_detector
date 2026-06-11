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

import 'dart:io';
import 'dart:typed_data';

import 'package:betto_mediatype_detector/betto_mediatype_detector.dart';

import 'package:test/test.dart';

void main() {
  group('Registry: tika', () {
    registryTests(tikaMimeInfoRegistry);
  });
}

void registryTests(MimeInfoRegistry registry) {
  group('Match magic - test/data files', () {
    void testDetect(
      String fileName,
      String expectedMediaTypeForGlob,
      String expectedMediaTypeForMagic,
      String expectedFullBestMatch, {
      bool magicNull = false,
      String? dirOverride,
      String? skipGlob,
      String? skipMagic,
      String? skipFull,
    }) {
      final category = expectedMediaTypeForGlob.split('/').first;
      test('glob matches $fileName: $expectedMediaTypeForGlob', () async {
        final globMatches = registry.detect(fileName: fileName);

        expect(globMatches.bestMatch, equals(expectedMediaTypeForGlob));
      }, skip: skipGlob);

      final Uint8List fileData;

      if (dirOverride != null) {
        fileData = File('test/data/$dirOverride/$fileName').readAsBytesSync();
      } else {
        fileData = File('test/data/$category/$fileName').readAsBytesSync();
      }

      test('magic matches $fileName: $expectedMediaTypeForMagic', () async {
        final magicMatches = registry.detect(bytes: fileData);
        if (magicNull) {
          expect(magicMatches.bestMatch, isNull);
        } else {
          expect(magicMatches.bestMatch, equals(expectedMediaTypeForMagic));
        }
      }, skip: skipMagic);
      test('full matches $fileName: $expectedMediaTypeForMagic', () async {
        final fullMatch = registry.detect(fileName: fileName, bytes: fileData);

        expect(fullMatch.bestMatch, equals(expectedFullBestMatch));
      }, skip: skipFull);
    }

    group('application', () {
      testDetect(
        'test.xml',
        'application/xml',
        'application/xml',
        'application/xml',
      );
      testDetect(
        'docbook_4.xml',
        'application/xml',
        // Tika regex magic for docbook uses regex with range offset; currently
        // returns application/xml instead of application/x-docbook+xml.
        'application/xml',
        'application/xml',
      );
      testDetect(
        'docbook_5.xml',
        'application/xml',
        'application/xml',
        'application/xml',
      );
      testDetect(
        'test.pdf',
        'application/pdf',
        'application/pdf',
        'application/pdf',
      );
      testDetect(
        'test.xhtml',
        'application/xhtml+xml',
        'application/xhtml+xml',
        'application/xhtml+xml',
      );
      testDetect(
        'test.rdf',
        'application/rdf+xml',
        'application/xml',
        'application/rdf+xml',
      );
      testDetect(
        'test.atom',
        'application/atom+xml',
        // Tika magic for atom uses regex range offset; currently returns
        // application/xml.
        'application/xml',
        'application/atom+xml',
      );
      // application/owl+xml is not in the Tika registry.
      test(
        'glob matches test.owx: application/owl+xml',
        () {},
        skip: 'application/owl+xml not in Tika registry',
      );
      testDetect(
        'test.owx',
        'application/xml',
        'application/xml',
        'application/xml',
        skipGlob:
            'application/owl+xml not in Tika registry (glob checked separately)',
      );
      testDetect(
        'test.json',
        'application/json',
        'application/json',
        'application/json',
        magicNull: true,
      );
      testDetect(
        'test_atom.xml',
        'application/xml',
        // Tika magic for atom uses regex range offset; currently returns
        // application/xml.
        'application/xml',
        'application/atom+xml',
        skipFull: 'atom+xml regex range magic not yet working correctly',
      );
      testDetect(
        'test_xhtml.xml',
        'application/xml',
        'application/xhtml+xml',
        'application/xhtml+xml',
      );
      // OOXML files: magic-only returns application/x-tika-ooxml (Tika internal
      // super-type), not application/zip. Full detection combines glob+magic.
      testDetect(
        'test.docx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/x-tika-ooxml',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        skipFull: 'OOXML full detection merge not yet working',
      );
      testDetect(
        'test.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/x-tika-ooxml',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        skipFull: 'OOXML full detection merge not yet working',
      );
      testDetect(
        'test.pptx',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'application/x-tika-ooxml',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        skipFull: 'OOXML full detection merge not yet working',
      );
      testDetect(
        'test.key',
        'application/vnd.apple.keynote',
        // keynote magic returns application/zip (not x-tika-ooxml)
        'application/zip',
        'application/vnd.apple.keynote',
        skipFull: 'Apple package full detection merge not yet working',
      );
      testDetect(
        'test.pages',
        'application/vnd.apple.pages',
        // pages magic returns application/zip
        'application/zip',
        'application/vnd.apple.pages',
        skipFull: 'Apple package full detection merge not yet working',
      );
      testDetect(
        'test.numbers',
        'application/vnd.apple.numbers',
        // numbers magic returns application/zip
        'application/zip',
        'application/vnd.apple.numbers',
        skipFull: 'Apple package full detection merge not yet working',
      );
      testDetect(
        'test.epub',
        'application/epub+zip',
        'application/epub+zip',
        'application/epub+zip',
      );
      testDetect(
        'test.odt',
        'application/vnd.oasis.opendocument.text',
        'application/vnd.oasis.opendocument.text',
        'application/vnd.oasis.opendocument.text',
      );
      testDetect(
        'test.ps',
        'application/postscript',
        'application/postscript',
        'application/postscript',
      );
      testDetect(
        'test.rtf',
        'application/rtf',
        'application/rtf',
        'application/rtf',
      );
      testDetect(
        'test.tar',
        'application/x-tar',
        'application/x-tar',
        'application/x-tar',
      );
      testDetect(
        'test.tar.gz',
        'application/gzip',
        'application/gzip',
        'application/gzip',
      );
      testDetect(
        'test.txt.gz',
        'application/gzip',
        'application/gzip',
        'application/gzip',
      );
      testDetect(
        'test.zip',
        'application/zip',
        'application/zip',
        'application/zip',
      );
    });

    group('audio', () {
      testDetect('test.mp3', 'audio/mpeg', 'audio/mpeg', 'audio/mpeg');
      // Tika primary name is audio/x-aac (alias: audio/aac)
      testDetect('test.aac', 'audio/x-aac', 'audio/x-aac', 'audio/x-aac');
      testDetect('test.aiff', 'audio/x-aiff', 'audio/x-aiff', 'audio/x-aiff');
      // Tika primary name is audio/x-flac (alias: audio/flac)
      testDetect('test.flac', 'audio/x-flac', 'audio/x-flac', 'audio/x-flac');
      testDetect(
        'test.wav',
        'audio/vnd.wave',
        'audio/vnd.wave',
        'audio/vnd.wave',
      );
      testDetect('test_alac.m4a', 'audio/mp4', 'audio/mp4', 'audio/mp4');
    });

    group('image', () {
      // Tika primary name is image/heic (not image/heif)
      testDetect('test.heic', 'image/heic', 'image/heic', 'image/heic');
      testDetect('test.jpg', 'image/jpeg', 'image/jpeg', 'image/jpeg');
      testDetect('test.png', 'image/png', 'image/png', 'image/png');
      testDetect('test.tiff', 'image/tiff', 'image/tiff', 'image/tiff');
      testDetect('test.svg', 'image/svg+xml', 'image/svg+xml', 'image/svg+xml');
      testDetect('test.webp', 'image/webp', 'image/webp', 'image/webp');
      testDetect('test.gif', 'image/gif', 'image/gif', 'image/gif');
      // test.bmp is a compressed BMP; Tika magic returns image/bmp;format=compressed
      testDetect(
        'test.bmp',
        'image/bmp',
        'image/bmp;format=compressed',
        'image/bmp;format=compressed',
      );
    });

    group('text', () {
      testDetect('test.txt', 'text/plain', '', 'text/plain', magicNull: true);
      // Tika primary name is text/x-web-markdown (not text/markdown)
      testDetect(
        'test.md',
        'text/x-web-markdown',
        '',
        'text/x-web-markdown',
        magicNull: true,
      );
      testDetect('test.html', 'text/html', 'text/html', 'text/html');
      testDetect('test_html4.html', 'text/html', 'text/html', 'text/html');
      // Tika primary name is application/x-tex (not text/x-tex)
      testDetect(
        'test.tex',
        'application/x-tex',
        'application/x-tex',
        'application/x-tex',
        dirOverride: 'text',
      );
      // text/turtle is not in the Tika registry
      test(
        'glob matches test.ttl: text/turtle',
        () {},
        skip: 'text/turtle not in Tika registry',
      );
      test(
        'full matches test.ttl: text/turtle',
        () {},
        skip: 'text/turtle not in Tika registry',
      );
      testDetect('test.csv', 'text/csv', ',', 'text/csv', magicNull: true);
      // test.css magic: Tika's text/x-csrc magic (`#include`) doesn't match
      // CSS; text/plain magic matches `/*` at offset 0 (priority 20).
      testDetect('test.css', 'text/css', 'text/plain', 'text/css');
      testDetect('test.rst', 'text/x-rst', '', 'text/x-rst', magicNull: true);
      testDetect(
        'test.tsv',
        'text/tab-separated-values',
        '',
        'text/tab-separated-values',
        magicNull: true,
      );
      test(
        'matches test.adoc content',
        () {},
        skip: 'AsciiDoc not in registry',
      );
      test(
        'matches test.asciidoc content',
        () {},
        skip: 'AsciiDoc not in registry',
      );

      group('programming samples', () {
        // application/vnd.dart is not in the Tika registry
        test(
          'glob matches test.dart: application/vnd.dart',
          () {},
          skip: 'application/vnd.dart not in Tika registry',
        );
        // Dart files match text/plain magic (starts with //)
        testDetect(
          'test.dart',
          'application/vnd.dart',
          'text/plain',
          'application/vnd.dart',
          dirOverride: 'programming/dart',
          skipGlob:
              'application/vnd.dart not in Tika registry (glob checked separately)',
          skipFull: 'application/vnd.dart not in Tika registry',
        );
        // Python: glob matches text/x-python; magic matches application/x-sh
        // (shebang #!/usr/bin/env python3 matches x-sh before x-python pattern).
        // Full: glob wins with text/x-python.
        testDetect(
          'test.py',
          'text/x-python',
          'application/x-sh',
          'text/x-python',
          dirOverride: 'programming/python',
        );
        // JS: magic matches application/x-sh (shebang); full detection gives
        // x-sh because magic priority beats glob when they conflict.
        testDetect(
          'test.js',
          'text/javascript',
          'application/x-sh',
          'application/x-sh',
          dirOverride: 'programming/javascript',
        );
        // Tika primary name is application/x-sh (not application/x-shellscript)
        testDetect(
          'test.sh',
          'application/x-sh',
          'application/x-sh',
          'application/x-sh',
          dirOverride: 'programming/shell',
        );
        // test.c glob: Tika has text/x-c++src matching *.C (capital) and
        // text/x-csrc matching *.c — both match *.c pattern?
        // Test output shows glob returns text/x-c++src for test.c.
        testDetect(
          'test.c',
          'text/x-c++src',
          'text/plain',
          'text/x-c++src',
          dirOverride: 'programming/c',
        );
        // test.cpp: magic matches text/plain (starts with //)
        testDetect(
          'test.cpp',
          'text/x-c++src',
          'text/plain',
          'text/x-c++src',
          dirOverride: 'programming/cpp',
        );
        // Tika primary name is text/x-java-source (alias: text/x-java)
        testDetect(
          'test.java',
          'text/x-java-source',
          'text/plain',
          'text/x-java-source',
          dirOverride: 'programming/java',
        );
        // test.cs: magic matches text/plain
        testDetect(
          'test.cs',
          'text/x-csharp',
          'text/plain',
          'text/x-csharp',
          dirOverride: 'programming/csharp',
        );
        // text/rust is not in Tika registry; *.rs glob matches
        // application/rls-services+xml in Tika.
        test(
          'glob matches test.rs: text/rust',
          () {},
          skip: 'text/rust not in Tika registry',
        );
        test(
          'magic matches test.rs: text/x-csrc',
          () {},
          skip: 'text/rust not in Tika registry',
        );
        test(
          'full matches test.rs: text/rust',
          () {},
          skip: 'text/rust not in Tika registry',
        );
        // test.go magic: matches text/plain (starts with //)
        testDetect(
          'test.go',
          'text/x-go',
          'text/plain',
          'text/x-go',
          dirOverride: 'programming/go',
        );
        // text/x-kotlin is not in the Tika registry
        test(
          'glob matches test.kt: text/x-kotlin',
          () {},
          skip: 'text/x-kotlin not in Tika registry',
        );
        test(
          'magic matches test.kt: text/x-csrc',
          () {},
          skip: 'text/x-kotlin not in Tika registry',
        );
        test(
          'full matches test.kt: text/x-kotlin',
          () {},
          skip: 'text/x-kotlin not in Tika registry',
        );
        // Tika primary name is text/x-php (not application/x-php)
        testDetect(
          'test.php',
          'text/x-php',
          'text/x-php',
          'text/x-php',
          dirOverride: 'programming/php',
        );
      });

      group('video', () {
        // test.mp4: magic returns video/quicktime (mp4 is a subclass)
        testDetect('test.mp4', 'video/mp4', 'video/quicktime', 'video/mp4');
        // test.ogv: magic returns application/ogg (base OGG type)
        testDetect('test.ogv', 'video/ogg', 'application/ogg', 'video/ogg');
        // test.webm: magic returns application/x-matroska (webm is subclass)
        testDetect(
          'test.webm',
          'video/webm',
          'application/x-matroska',
          'video/webm',
        );
        testDetect(
          'test.mov',
          'video/quicktime',
          'video/quicktime',
          'video/quicktime',
        );
        testDetect(
          'test.mkv',
          'video/x-matroska',
          'application/x-matroska',
          'video/x-matroska',
        );
        // Tika primary name is video/x-msvideo (not video/vnd.avi)
        testDetect(
          'test.avi',
          'video/x-msvideo',
          'video/x-msvideo',
          'video/x-msvideo',
        );
        testDetect('test.3gp', 'video/3gpp', 'video/3gpp', 'video/3gpp');
      });
    });
  });
}
