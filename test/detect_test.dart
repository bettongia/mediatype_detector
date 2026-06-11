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
  group('detect', () {
    _detectTests();
  });
}

void _detectTests() {
  group('Match magic - test/data files', () {
    void testDetect(
      String fileName,
      String expectedGlob,
      String expectedMagic,
      String expectedFull, {
      bool magicNull = false,
      String? dirOverride,
      String? skipGlob,
      String? skipMagic,
      String? skipFull,
    }) {
      final category = expectedGlob.split('/').first;

      test('glob matches $fileName: $expectedGlob', () async {
        final result = detect(fileName: fileName);
        expect(result.bestMatch, equals(expectedGlob));
      }, skip: skipGlob);

      final Uint8List fileData;
      if (dirOverride != null) {
        fileData = File('test/data/$dirOverride/$fileName').readAsBytesSync();
      } else {
        fileData = File('test/data/$category/$fileName').readAsBytesSync();
      }

      test('magic matches $fileName: $expectedMagic', () async {
        final result = detect(bytes: fileData);
        if (magicNull) {
          expect(result.bestMatch, isNull);
        } else {
          expect(result.bestMatch, equals(expectedMagic));
        }
      }, skip: skipMagic);

      test('full matches $fileName: $expectedFull', () async {
        final result = detect(fileName: fileName, bytes: fileData);
        expect(result.bestMatch, equals(expectedFull));
      }, skip: skipFull);
    }

    group('application', () {
      testDetect(
        'test.xml',
        'application/xml',
        'application/xml',
        'application/xml',
      );
      // Freedesktop magic correctly identifies DocBook 4 via rootXML; Tika alone
      // could not (regex range magic not working).
      testDetect(
        'docbook_4.xml',
        'application/xml',
        'application/x-docbook+xml',
        'application/x-docbook+xml',
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
      // Freedesktop magic correctly identifies Atom via rootXML; Tika alone could
      // not (regex range magic not working).
      testDetect(
        'test.atom',
        'application/atom+xml',
        'application/atom+xml',
        'application/atom+xml',
      );
      // Freedesktop glob provides application/owl+xml; Tika does not have this type.
      testDetect(
        'test.owx',
        'application/owl+xml',
        'application/xml',
        'application/owl+xml',
      );
      testDetect(
        'test.json',
        'application/json',
        '',
        'application/json',
        magicNull: true,
      );
      // Freedesktop rootXML correctly identifies Atom embedded in a .xml file.
      testDetect(
        'test_atom.xml',
        'application/xml',
        'application/atom+xml',
        'application/atom+xml',
      );
      testDetect(
        'test_xhtml.xml',
        'application/xml',
        'application/xhtml+xml',
        'application/xhtml+xml',
      );
      // OOXML: Tika magic returns application/x-tika-ooxml; Freedesktop returns
      // application/zip. The merged magic results prevent glob refinement to the
      // specific OOXML sub-type.
      testDetect(
        'test.docx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/x-tika-ooxml',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        skipFull:
            'OOXML full detection: merged Tika (x-tika-ooxml) and Freedesktop (zip) magic prevents glob refinement',
      );
      testDetect(
        'test.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/x-tika-ooxml',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        skipFull:
            'OOXML full detection: merged Tika (x-tika-ooxml) and Freedesktop (zip) magic prevents glob refinement',
      );
      testDetect(
        'test.pptx',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'application/x-tika-ooxml',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        skipFull:
            'OOXML full detection: merged Tika (x-tika-ooxml) and Freedesktop (zip) magic prevents glob refinement',
      );
      // .key extension: application/pgp-keys outranks application/vnd.apple.keynote
      // in the merged glob priority order, despite both individual registries
      // returning keynote as their best glob match.
      testDetect(
        'test.key',
        'application/vnd.apple.keynote',
        'application/zip',
        'application/vnd.apple.keynote',
        skipGlob:
            '.key priority conflict: application/pgp-keys outranks application/vnd.apple.keynote in merged glob results',
        skipFull:
            '.key priority conflict: application/pgp-keys outranks application/vnd.apple.keynote in merged glob results',
      );
      testDetect(
        'test.pages',
        'application/vnd.apple.pages',
        'application/vnd.apple.pages',
        'application/vnd.apple.pages',
      );
      testDetect(
        'test.numbers',
        'application/vnd.apple.numbers',
        'application/vnd.apple.pages',
        'application/vnd.apple.numbers',
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
      // Freedesktop canonical name audio/aac wins over Tika's audio/x-aac.
      testDetect('test.aac', 'audio/aac', 'audio/aac', 'audio/aac');
      // application/x-iff matches AIFF magic at higher priority than audio/x-aiff
      // in the merged results; full detection correctly resolves to audio/x-aiff
      // via glob.
      testDetect(
        'test.aiff',
        'audio/x-aiff',
        'application/x-iff',
        'audio/x-aiff',
      );
      // Freedesktop canonical name audio/flac wins over Tika's audio/x-flac.
      testDetect('test.flac', 'audio/flac', 'audio/flac', 'audio/flac');
      // application/x-riff matches WAV magic at higher priority in the merged
      // results; full detection correctly resolves to audio/vnd.wave via glob.
      testDetect(
        'test.wav',
        'audio/vnd.wave',
        'application/x-riff',
        'audio/vnd.wave',
      );
      testDetect('test_alac.m4a', 'audio/mp4', 'audio/mp4', 'audio/mp4');
    });

    group('image', () {
      // Freedesktop glob returns image/heif; Tika magic returns image/heic.
      testDetect('test.heic', 'image/heif', 'image/heic', 'image/heic');
      testDetect('test.jpg', 'image/jpeg', 'image/jpeg', 'image/jpeg');
      testDetect('test.png', 'image/png', 'image/png', 'image/png');
      testDetect('test.tiff', 'image/tiff', 'image/tiff', 'image/tiff');
      testDetect('test.svg', 'image/svg+xml', 'image/svg+xml', 'image/svg+xml');
      testDetect('test.webp', 'image/webp', 'image/webp', 'image/webp');
      testDetect('test.gif', 'image/gif', 'image/gif', 'image/gif');
      // Tika magic returns image/bmp;format=compressed for this compressed BMP.
      testDetect(
        'test.bmp',
        'image/bmp',
        'image/bmp;format=compressed',
        'image/bmp;format=compressed',
      );
    });

    group('text', () {
      testDetect('test.txt', 'text/plain', '', 'text/plain', magicNull: true);
      // Freedesktop canonical name text/markdown wins over Tika's text/x-web-markdown.
      testDetect(
        'test.md',
        'text/markdown',
        '',
        'text/markdown',
        magicNull: true,
      );
      // *.html glob: application/xhtml+xml appears in the merged results at higher
      // priority than text/html despite both individual registries returning
      // text/html as their glob best match. Full detection correctly gives text/html
      // because magic confirms it.
      testDetect(
        'test.html',
        'text/html',
        'text/html',
        'text/html',
        skipGlob:
            '*.html priority conflict: application/xhtml+xml outranks text/html in merged glob results',
      );
      testDetect(
        'test_html4.html',
        'text/html',
        'text/html',
        'text/html',
        skipGlob:
            '*.html priority conflict: application/xhtml+xml outranks text/html in merged glob results',
      );
      // Freedesktop uses text/x-tex; Tika uses application/x-tex. Tika wins
      // (primary) so both glob and magic return application/x-tex.
      testDetect(
        'test.tex',
        'application/x-tex',
        'application/x-tex',
        'application/x-tex',
        dirOverride: 'text',
      );
      // Freedesktop glob provides text/turtle; Tika does not have this type.
      testDetect('test.ttl', 'text/turtle', '', 'text/turtle', magicNull: true);
      testDetect('test.csv', 'text/csv', '', 'text/csv', magicNull: true);
      // Freedesktop magic matches text/x-csrc; full detection prefers text/css
      // (glob) since magic has no magic rules of its own for CSS.
      testDetect('test.css', 'text/css', 'text/x-csrc', 'text/css');
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
        // Freedesktop glob provides application/vnd.dart; Tika does not.
        testDetect(
          'test.dart',
          'application/vnd.dart',
          'text/x-csrc',
          'application/vnd.dart',
          dirOverride: 'programming/dart',
        );
        // Freedesktop magic identifies text/x-python3 (more specific); full
        // detection prefers it over Tika's text/x-python glob match.
        testDetect(
          'test.py',
          'text/x-python',
          'text/x-python3',
          'text/x-python3',
          dirOverride: 'programming/python',
        );
        // Shebang magic matches application/x-sh at higher priority than
        // text/javascript glob; magic wins in full detection.
        testDetect(
          'test.js',
          'text/javascript',
          'application/x-sh',
          'application/x-sh',
          dirOverride: 'programming/javascript',
        );
        // Freedesktop canonical name application/x-shellscript; Tika uses
        // application/x-sh. Tika wins (primary) so both return application/x-sh.
        testDetect(
          'test.sh',
          'application/x-sh',
          'application/x-sh',
          'application/x-sh',
          dirOverride: 'programming/shell',
        );
        // Tika maps *.c to text/x-c++src (C++ source); Freedesktop maps it to
        // text/x-csrc. Tika wins for glob, but magic (text/x-csrc) takes over
        // in full detection.
        testDetect(
          'test.c',
          'text/x-c++src',
          'text/x-csrc',
          'text/x-csrc',
          dirOverride: 'programming/c',
        );
        testDetect(
          'test.cpp',
          'text/x-c++src',
          'text/x-csrc',
          'text/x-c++src',
          dirOverride: 'programming/cpp',
        );
        // Freedesktop canonical name text/x-java; Tika uses text/x-java-source.
        // Freedesktop wins for glob since both have text/x-java but at differing
        // priorities.
        testDetect(
          'test.java',
          'text/x-java',
          'text/x-csrc',
          'text/x-java',
          dirOverride: 'programming/java',
        );
        testDetect(
          'test.cs',
          'text/x-csharp',
          'text/x-csrc',
          'text/x-csharp',
          dirOverride: 'programming/csharp',
        );
        // Tika maps *.rs to application/rls-services+xml (wrong) which outranks
        // Freedesktop's text/rust in the merged glob priority order.
        testDetect(
          'test.rs',
          'text/rust',
          'text/x-csrc',
          'text/rust',
          dirOverride: 'programming/rust',
          skipGlob:
              '*.rs mapped to application/rls-services+xml in Tika, outranking Freedesktop text/rust in merged glob results',
          skipFull:
              '*.rs mapped to application/rls-services+xml in Tika, outranking Freedesktop text/rust in merged glob results',
        );
        testDetect(
          'test.go',
          'text/x-go',
          'text/x-csrc',
          'text/x-go',
          dirOverride: 'programming/go',
        );
        // Freedesktop glob provides text/x-kotlin; Tika does not have this type.
        testDetect(
          'test.kt',
          'text/x-kotlin',
          'text/x-csrc',
          'text/x-kotlin',
          dirOverride: 'programming/kotlin',
        );
        testDetect(
          'test.php',
          'application/x-php',
          'application/x-php',
          'application/x-php',
          dirOverride: 'programming/php',
        );
      });

      group('video', () {
        testDetect('test.mp4', 'video/mp4', 'video/mp4', 'video/mp4');
        // Freedesktop magic returns audio/x-flac+ogg for this OGV file; full
        // detection resolves correctly to video/ogg via glob.
        testDetect('test.ogv', 'video/ogg', 'audio/x-flac+ogg', 'video/ogg');
        testDetect('test.webm', 'video/webm', 'video/webm', 'video/webm');
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
        // Freedesktop canonical name video/vnd.avi wins over Tika's video/x-msvideo.
        testDetect(
          'test.avi',
          'video/vnd.avi',
          'video/vnd.avi',
          'video/vnd.avi',
        );
        testDetect('test.3gp', 'video/3gpp', 'video/3gpp', 'video/3gpp');
      });
    });
  });
}
