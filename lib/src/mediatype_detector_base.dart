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

import 'dart:typed_data' show Uint8List;

import 'tika_mimeinfo/registry.dart' show TikaMimeInfoRegistry;
import 'tika_mimeinfo/g/mimeinfo.dart' as tika;

import 'freedesktop_mimeinfo/registry.dart' show FreedesktopMimeInfoRegistry;
import 'freedesktop_mimeinfo/g/mimeinfo.dart' as fd;

import 'mimeinfo/base.dart';
export 'mimeinfo/base.dart';

// TIKA
final tikaMimeInfoRegistry = TikaMimeInfoRegistry(tika.mimeinfoDb);

// These two lines need to be swapped in if you have to completely
// clear out all 'g' files and start from scratch
//
// import 'package:betto_mediatype_detector/src/mimeinfo/registry.dart';
// final tikaMimeInfoRegistry = TikaMimeInfoRegistry(emptyRegistry);

// FreeDesktop
final freedesktopMimeInfoRegistry = FreedesktopMimeInfoRegistry(fd.mimeinfoDb);

// These two lines need to be swapped in if you have to completely
// clear out all 'g' files and start from scratch
//
// import 'package:betto_mediatype_detector/src/mimeinfo/registry.dart';
// final freedesktopMimeInfoRegistry = FreedesktopMimeInfoRegistry(emptyRegistry);

/// Detect the media type of the file
///
/// Use this as the main filetype detection function as this allows
/// for future work to improve and add to the detector.
MatchList detect({
  Uint8List? bytes,
  String? fileName,
  bool caseSensitive = false,
}) => freedesktopMimeInfoRegistry.detect(
  bytes: bytes,
  fileName: fileName,
  caseSensitive: caseSensitive,
);
