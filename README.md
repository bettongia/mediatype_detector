# betto_mediatype_detector

A Dart package for identifying media types (MIME types) from file content and
filenames. Merges the
[Freedesktop.org Shared MIME-info Database](https://specifications.freedesktop.org/shared-mime-info/latest/)
and the [Apache Tika](https://tika.apache.org/) database into a single
high-accuracy blended registry, with an override layer for known upstream
corrections and an extension point for caller-supplied registries.

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
- **Layered registry pipeline**: `detect()` consults registries in order,
  returning the first non-empty result:
  1. Caller-supplied `customRegistry` (optional, per-call).
  2. Built-in override registry — targeted corrections for known bad upstream
     mappings (e.g. Tika's incorrect `*.rs` → `application/rls-services+xml`).
  3. Blended Tika + Freedesktop registry — deduplicates by keeping the
     higher-priority entry so that glob weights and parent-child relationships
     from both databases are preserved.
- **Confidence-ranked results**: Returns a `MatchList` that exposes both a
  `bestMatch` string and the full ranked result set via `merged`, `combined`,
  and `candidates`.
- **Rich metadata**: Each matched `RegistryEntry` carries human-readable
  descriptions (with i18n support), subclass relationships, generic icons,
  acronyms, and aliases.
- **Two bundled databases**: Freedesktop and Apache Tika, also accessible
  individually via `freedesktopMimeInfoRegistry` and `tikaMimeInfoRegistry`.
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

Pass `bytes` for content-based matching, `fileName` for glob-based matching, or
both for the highest-confidence result.

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

### Caller-supplied custom registry

Pass any `MimeInfoRegistry` subclass as `customRegistry` to detect proprietary
or domain-specific types without modifying global state. The custom registry is
consulted first; if it returns a non-empty result, the override and blended
registries are not consulted.

```dart
import 'package:betto_mediatype_detector/mediatype_detector.dart';

final myRegistry = MyAppMimeInfoRegistry(myEntries);

final matches = detect(
  bytes: bytes,
  fileName: fileName,
  customRegistry: myRegistry,
);
```

### Using a bundled registry directly

```dart
import 'package:betto_mediatype_detector/mediatype_detector.dart';

// Freedesktop only
final fdMatches = freedesktopMimeInfoRegistry.detect(
  bytes: bytes,
  fileName: p.basename(filePath),
);

// Tika only
final tikaMatches = tikaMimeInfoRegistry.detect(
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

| Symbol | Description |
| --- | --- |
| `detect({bytes, fileName, caseSensitive, customRegistry})` | Top-level function; runs the layered pipeline (custom → override → blended) |
| `freedesktopMimeInfoRegistry` | Global Freedesktop MIME database registry |
| `tikaMimeInfoRegistry` | Global Apache Tika MIME database registry |
| `overrideMimeInfoRegistry` | Built-in override registry for upstream corrections |
| `OverrideMimeInfoRegistry` | Subclass backing the override registry; extend or instantiate with custom entries |
| `MimeInfoRegistry` | Abstract base class; extend to build custom registries |
| `MatchList` | Returned by `detect`; exposes `bestMatch`, `merged`, `candidates`, `globMatches`, `magicMatches`, `rootXmlMatches` |
| `MatchResult` | A single match: `mediaType`, `priority`, `subclassOf`, `hasMagic` |
| `RegistryEntry` | Full metadata for a MIME type: globs, magic rules, comments, aliases, icons |

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
