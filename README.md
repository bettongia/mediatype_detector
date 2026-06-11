# betto_mediatype_detector

A Dart package for identifying media types (MIME types) from file content and
filenames. Implements the
[Freedesktop.org Shared MIME-info Database](https://specifications.freedesktop.org/shared-mime-info/latest/)
specification and bundles an Apache Tika-derived database as an alternative
registry.

## Features

- **Spec-compliant**: Implements the Freedesktop.org Shared MIME-info Database
  specification version 2.4.
- **Multi-strategy detection**: Applies three complementary strategies in
  priority order:
  - **Magic matching** — byte-pattern inspection at specific offsets within file
    content.
  - **Glob matching** — filename pattern matching (e.g. `*.png`, `*.tar.gz`),
    with a fast O(1) extension index for simple patterns.
  - **RootXML matching** — namespace and local-name inspection of the root
    element for XML-based formats.
- **Confidence-ranked results**: Returns a `MatchList` that exposes both a
  `bestMatch` string and the full ranked result set via `merged`, `combined`,
  and `candidates`.
- **Rich metadata**: Each matched `RegistryEntry` carries human-readable
  descriptions (with i18n support), subclass relationships, generic icons,
  acronyms, and aliases.
- **Two bundled databases**: Freedesktop (default) and Apache Tika, accessible
  via `freedesktopMimeInfoRegistry` and `tikaMimeInfoRegistry` respectively.
- **CLI tool**: A `detect` executable is included for inspecting files from the
  command line.

> **Note**: TreeMagic (directory-level identification based on internal
> file/folder structures) is not implemented.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  betto_mediatype_detector: ^0.1.0-dev.1
```

Then run:

```bash
dart pub get
```

## Usage

### Detect from file content and name

```dart
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:betto_mediatype_detector/mediatype_detector.dart';
import 'package:path/path.dart' as p;

void main() {
  final filePath = 'document.pdf';
  final Uint8List bytes = File(filePath).readAsBytesSync();

  final matches = detect(bytes: bytes, fileName: p.basename(filePath));

  if (matches.isEmpty) {
    print('No media type found.');
  } else {
    print('Best match: ${matches.bestMatch}');
  }
}
```

`detect` is a convenience wrapper around `freedesktopMimeInfoRegistry.detect`.
Pass `bytes` for content-based matching, `fileName` for glob-based matching, or
both for the highest confidence result.

### Working with results

```dart
final matches = detect(bytes: bytes, fileName: 'index.html');

// Best single result
print(matches.bestMatch); // e.g. "text/html"

// Merged, deduplicated results ordered by confidence
for (final m in matches.merged) {
  print('${m.mediaType} [priority: ${m.priority}]');
}

// All candidates as plain strings
for (final candidate in matches.candidates) {
  print(candidate);
}

// Results broken down by strategy
for (final m in matches.globMatches)    { print('glob:  ${m.mediaType}'); }
for (final m in matches.magicMatches)   { print('magic: ${m.mediaType}'); }
for (final m in matches.rootXmlMatches) { print('xml:   ${m.mediaType}'); }
```

### Glob-only detection (no file content)

```dart
final matches = detect(fileName: 'archive.tar.gz');
print(matches.bestMatch); // "application/x-compressed-tar"
```

### Magic-only detection (no filename)

```dart
final Uint8List bytes = File('unknown_file').readAsBytesSync();
final matches = detect(bytes: bytes);
print(matches.bestMatch);
```

### Using the Tika registry directly

```dart
import 'package:betto_mediatype_detector/mediatype_detector.dart';

final matches = tikaMimeInfoRegistry.detect(
  bytes: bytes,
  fileName: p.basename(filePath),
);
```

### CLI tool

The package ships a `detect` executable that can be run with `dart run`:

```bash
dart run betto_mediatype_detector:detect path/to/file
```

## API overview

| Symbol                        | Description                                                                                                        |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `detect({bytes, fileName})`   | Top-level convenience function (uses Freedesktop registry)                                                         |
| `freedesktopMimeInfoRegistry` | Global Freedesktop MIME database registry                                                                          |
| `tikaMimeInfoRegistry`        | Global Apache Tika MIME database registry                                                                          |
| `MatchList`                   | Returned by `detect`; exposes `bestMatch`, `merged`, `candidates`, `globMatches`, `magicMatches`, `rootXmlMatches` |
| `MatchResult`                 | A single match: `mediaType`, `priority`, `subclassOf`, `hasMagic`                                                  |
| `RegistryEntry`               | Full metadata for a MIME type: globs, magic rules, comments, aliases, icons                                        |
| `MimeInfoRegistry`            | Base class; extend to build custom registries                                                                      |

## License

This package is licensed under the Apache License 2.0. See the
[LICENSE](LICENSE) file for details.

The bundled [Apache Tika](https://tika.apache.org/) MIME database is copyright
2011 The Apache Software Foundation and is distributed under the Apache License
2.0. See https://www.apache.org/licenses/LICENSE-2.0 for details.

The bundled Freedesktop.org Shared MIME database is distributed under the GNU
General Public License version 2 or later:

> The freedesktop.org shared MIME database was created by merging several
> existing MIME databases (all released under the GNU GPL). It comes with
> ABSOLUTELY NO WARRANTY, to the extent permitted by law.
>
> The latest version is available from:
> http://www.freedesktop.org/wiki/Software/shared-mime-info/
