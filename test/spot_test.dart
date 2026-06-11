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
  final expectedMediaType = 'application/ogg';
  final fileName = 'test/data/video/test.ogv';

  final Uint8List fileData = File(fileName).readAsBytesSync();
  test('magic matches $fileName: $expectedMediaType', () {
    final magicMatches = tikaMimeInfoRegistry.detect(bytes: fileData);

    expect(magicMatches.bestMatch, equals(expectedMediaType));
  });
}
