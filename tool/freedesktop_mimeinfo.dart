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
import 'mimeinfo.dart';

/// The freedesktop.org shared MIME database
void main() {
  build(
    downloadUrl:
        'https://gitlab.freedesktop.org'
        '/xdg/shared-mime-info/-/archive/2.4'
        '/shared-mime-info-2.4.zip',
    codeOutputDir: Directory('lib/src/freedesktop_mimeinfo/g/'),
    dataOutputFile: File('tool/data/freedesktop/freedesktop.org.xml'),
  );
}
