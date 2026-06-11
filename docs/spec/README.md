---
title: Technical Specification
subtitle: betto_mediatype_detector
toc-title: "Contents"
...

- **Package:** `betto_mediatype_detector`
- **Version:** 0.1.0-dev.1
- **Dart SDK:** ^3.12.0

# Purpose and scope

`betto_mediatype_detector` is a pure-Dart library that identifies the media type
(MIME type) of a file from its content and/or filename. It merges two upstream
MIME databases —
[Freedesktop.org Shared MIME-info](https://specifications.freedesktop.org/shared-mime-info/latest/)
and [Apache Tika](https://tika.apache.org/) — into a single blended registry,
applies the Freedesktop conflict-resolution rules to rank results, and exposes
an extension point for caller-supplied and built-in override registries.

The library has no Flutter dependency and no runtime I/O — all databases are
compiled into static Dart maps at code-generation time.

# Repository layout

```
lib/
  betto_mediatype_detector.dart        # Public barrel (re-exports base)
  src/
    mediatype_detector_base.dart       # Top-level detect() + _mergeResults()
    mimeinfo/                          # Core domain types and detection logic
      base.dart                        # Re-exports for all public mimeinfo types
      registry.dart                    # MimeInfoRegistry abstract base class
      match.dart                       # MatchList + MatchResult
      entry.dart                       # RegistryEntry (per-type metadata)
      glob.dart / glob_index.dart      # Glob matching + fast extension index
      magic.dart                       # Binary magic-number matching
      xml.dart                         # Root XML element matching
      icon.dart                        # GenericIcon enum
    freedesktop_mimeinfo/
      registry.dart                    # FreedesktopMimeInfoRegistry subclass
      g/                               # Generated Dart code (do not edit)
    tika_mimeinfo/
      registry.dart                    # TikaMimeInfoRegistry subclass
      g/                               # Generated Dart code (do not edit)
    override_mimeinfo/
      registry.dart                    # OverrideMimeInfoRegistry subclass
      entries.dart                     # Hand-authored correction entries

tool/
  mimeinfo.dart                        # Shared code-generation helpers
  freedesktop_mimeinfo.dart            # Runs Freedesktop loader
  tika.dart                            # Runs Tika loader
  copyright.dart                       # Loads licence header for generated files
  data/                                # Cached upstream XML databases (checked in)

test/
  detect_test.dart                     # Integration tests for blended detect()
  freedesktop_test.dart                # Tests against Freedesktop registry
  tika_test.dart                       # Tests against Tika registry
  merge_dedup_test.dart                # Unit tests for _mergeResults() logic
  custom_registry_test.dart            # Unit tests for registry layering
  spot_test.dart                       # Targeted spot-check tests
  data/                                # Real sample files by media type category
```

Files under `g/` are **generated** — do not edit them by hand. Regenerate with
`make load` (or `make loader_tika` / `make loader_freedesktop_mimeinfo`
individually).

# Core types

| Type               | File                       | Role                                                                                 |
| ------------------ | -------------------------- | ------------------------------------------------------------------------------------ |
| `MimeInfoRegistry` | `mimeinfo/registry.dart`   | Abstract base; owns `detect`, `matchGlob`, `matchMagic`, `matchRootXML`              |
| `RegistryEntry`    | `mimeinfo/entry.dart`      | All metadata for one MIME type: globs, magic rules, rootXML rules, comments, aliases |
| `Glob`             | `mimeinfo/glob.dart`       | A single filename pattern rule with a match weight                                   |
| `GlobIndex`        | `mimeinfo/glob_index.dart` | Pre-built index for O(1) extension lookups                                           |
| `Magic`            | `mimeinfo/magic.dart`      | A magic rule with a priority and a list of `Match` conditions                        |
| `Match`            | `mimeinfo/magic.dart`      | A single byte-pattern condition (subclasses: `RegExpMatch`, `MinShouldMatch`)        |
| `RootXML`          | `mimeinfo/xml.dart`        | A root XML element match rule (namespace URI + local name)                           |
| `MatchList`        | `mimeinfo/match.dart`      | Detection result; per-strategy lists + conflict-resolved `merged` view               |
| `MatchResult`      | `mimeinfo/match.dart`      | A single match: `mediaType`, `priority`, `subclassOf`, `hasMagic`                    |
| `Registry`         | `mimeinfo/registry.dart`   | Type alias for `Map<String, List<RegistryEntry>>`                                    |

# Detection pipeline within a single registry

Each `MimeInfoRegistry` runs detection through three ordered stages.

## Stage 1 — Glob matching

`matchGlob(fileName)` checks the filename against all registered glob patterns
and returns a list of `MatchResult` objects ordered by weight descending.

**Fast path (O(1))**: Simple `*.ext` patterns are indexed at construction time
by `GlobIndex` into a `Map<String, List<IndexedGlob>>` keyed by lowercase
extension. Compound extensions (e.g. `tar.gz`) are tried from longest to
shortest — `tar.gz` is checked before `gz`.

**Slow path (linear scan)**: Complex patterns that cannot be indexed (e.g.
`README*`, patterns containing `?` or `[`) are stored in a separate
`complexPatterns` list and checked via a full scan.

A pattern is classified as a simple extension if it matches the form `*.ext`
where `ext` contains no glob metacharacters (`*`, `?`, `[`, `\`).

Glob matching is case-insensitive by default. The effective case sensitivity is
the logical OR of the `caseSensitive` argument passed to `matchGlob` and the
`caseSensitive` flag on the individual `Glob` rule.

## Stage 2 — Magic matching

`matchMagic(bytes)` scans every `RegistryEntry` in the registry against the
file's byte content. Each entry may carry multiple `Magic` rules; each rule
carries one or more `Match` conditions.

**Match types** (`MatchType`): `string`, `big16`, `big32`, `little16`,
`little32`, `host16`, `host32`, `byte`, `regex`, and the Tika-specific
`minShouldMatch`.

**Offset ranges**: Offsets are specified as `"N"` (exact) or `"N:M"` (range);
the match is attempted at each position in the range.

**Mask**: An optional hex bitmask is AND-ed to both the file byte and the
pattern byte before comparison.

**Sub-matches**: Each `Match` may carry child `Match` objects. If the parent
byte check succeeds and children are present, at least one child must also match
(OR semantics among children).

**MinShouldMatch**: Tika uses a special `minShouldMatch` rule type that requires
at least N of its children to succeed, independently of the normal OR child
semantics.

**Regex**: Tika also uses `type="regex"` matches (`RegExpMatch`). Inline flags
(`(?i)`, `(?m)`, `(?s)`) are parsed and mapped to Dart's `RegExp` parameters.
For a single offset, `matchAsPrefix` anchors the pattern to that position; for a
range, `hasMatch` is used over each candidate position in the range.

## Stage 3 — Root XML matching

`matchRootXML(bytes)` is only invoked when glob or magic results suggest an
XML-based type. The heuristic (`isLikelyXml`) is true when any current match has
a subtype ending in `+xml`, a top-level type of `xml`, or a `subclassOf` entry
of `application/xml`.

When invoked, `matchRootXML` parses the bytes as UTF-8 XML once, extracts the
root element's local name and namespace URI, and checks them against every
registered `RootXML` rule. Either field of a `RootXML` rule may be `null` to act
as a wildcard.

## MatchList conflict resolution

The three stage-result lists are combined by `MatchList._merge()` into a single
ranked list following the Freedesktop specification:

1. **Root XML is definitive.** If `rootXmlMatches` is non-empty, it is returned
   immediately without consulting glob or magic results.

2. **Glob-only mode** (no magic results). Without content inspection, specific
   subtypes cannot be confirmed. When a parent type and a child type both match
   by glob, the parent (more conservative) type is kept and the child is
   removed.

3. **Full mode** (magic results present). Glob entries are filtered to those
   that are consistent with the magic results:
   - A glob type with no magic rules of its own (`hasMagic == false`) is always
     kept — it is an extension-only type that cannot be magic-confirmed.
   - A glob type is kept if magic directly confirmed the same type.
   - A glob type is kept if magic confirmed one of its parent types
     (`subclassOf`).

   The surviving magic and glob results are merged, then sorted with
   **doubly-confirmed** types (present in both magic and glob) ranked first,
   followed by priority descending. Finally, a parent-child pass removes
   redundant entries:
   - If magic explicitly identified the child type → child wins, parent removed.
   - If the parent is doubly-confirmed and the child is not in magic → parent
     wins, child removed (e.g. `application/gzip` confirmed by both magic and
     glob beats `application/x-compressed-tar` that only matched by glob).
   - Otherwise → child wins (more specific identification).

# Blended registry and `_mergeResults()`

The top-level `detect()` function in `mediatype_detector_base.dart` runs each
stage independently against both the Tika and Freedesktop registries, then
merges each stage's two result lists with `_mergeResults()` before constructing
the `MatchList`.

## Merge deduplication rules

`_mergeResults(primary, secondary)` takes the Tika list as `primary` and the
Freedesktop list as `secondary`. For each media type that appears in both lists,
exactly one entry is kept using the following priority:

1. **Higher glob weight wins.** If the two entries have different priorities,
   the higher-priority entry is kept regardless of which list it came from.
2. **Richer parentage wins on a tie.** If the priorities are equal, the entry
   with the longer `subclassOf` list is preferred. This preserves Freedesktop's
   parent-chain information when Tika's entry for the same type carries a
   shallower or different ancestry (critical for OOXML types, whose Freedesktop
   entries declare `subclassOf: [application/zip]` while Tika's carry a
   Tika-internal supertype absent from Freedesktop).
3. **Primary wins if equal in both respects.** If priority and `subclassOf`
   length are identical, the primary (Tika) entry is retained.

The merged list is sorted by priority descending before being returned.

## Why this matters

Naively keeping the primary entry for every duplicate discards Freedesktop's
higher-weight glob entries (e.g. `text/html` at weight 80 vs. Tika's weight 50
for the same type), causing lower-priority types to sort first and producing
wrong best-match results. It also discards the `subclassOf` chains that
`MatchList._merge()` depends on to refine a generic type (e.g.
`application/zip`) identified by magic up to a specific OOXML subtype.

# Layered `detect()` pipeline

The top-level `detect()` function implements a three-layer registry pipeline
with **short-circuit semantics**: the first layer to return a non-empty
`MatchList` wins and lower layers are not consulted.

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 1: customRegistry  (optional, caller-supplied)        │
│  Layer 2: overrideMimeInfoRegistry  (built-in corrections)   │
│  Layer 3: blended Tika + Freedesktop  (default)              │
└──────────────────────────────────────────────────────────────┘
```

**Short-circuit caveat**: because each layer is consulted as a whole, a layer
that matches only by glob suppresses the blended registry's magic and root XML
stages for that file. Override and custom entries that cover magic-confirmable
types should therefore include magic rules if full-detection accuracy is
required.

## Layer 1 — Caller-provided registry

```dart
final result = detect(
  bytes: bytes,
  fileName: fileName,
  customRegistry: myRegistry,
);
```

`customRegistry` is any class extending `MimeInfoRegistry`. If its `detect()`
call returns a non-empty `MatchList`, that result is returned immediately.
Passing `null` (the default) is a no-op.

## Layer 2 — Override registry

The built-in `overrideMimeInfoRegistry` instance of `OverrideMimeInfoRegistry`
is backed by the hand-authored map in `lib/src/override_mimeinfo/entries.dart`.
It is consulted after the caller registry but before the blended registry.

Use the override registry when:

- An upstream database maps a glob to the wrong media type.
- A file format is absent from both databases.

To add a correction, edit `entries.dart` directly — no code generation is
involved. Set the glob weight high enough to beat the incorrect upstream entry
(typically 60, which beats the default 50 without reaching the 80 threshold
reserved for high-confidence upstream entries).

Example entry structure:

```dart
'text/rust': [
  RegistryEntry(
    mediaType: 'text/rust',
    comments: [IntlString.constant('Rust source code')],
    subclassOf: ['text/plain'],
    globs: [Glob(pattern: '*.rs', weight: 60, caseSensitive: false)],
  ),
],
```

## Layer 3 — Blended Tika + Freedesktop

The default detection path. Both registries are run for each stage and their
results are merged with `_mergeResults()` as described in section 5.

# Code generation

The Tika and Freedesktop MIME databases are compiled from upstream XML sources
into static Dart maps at development time. The generated files are checked in
under `lib/src/{tika,freedesktop}_mimeinfo/g/` and must not be edited by hand.

## Source data

Upstream XML databases are cached in `tool/data/`:

| File                  | Source                                |
| --------------------- | ------------------------------------- |
| `freedesktop.org.xml` | Freedesktop Shared MIME-info database |
| `tika-mimetypes.xml`  | Apache Tika MIME database             |

The loaders download a fresh copy from the upstream URL if the local cache is
absent; if the cached file is present, it is used directly.

## Generation pipeline

Running `make load` (or `make loader_freedesktop_mimeinfo` / `make loader_tika`
individually) executes:

```
dart run tool/freedesktop_mimeinfo.dart
dart run tool/tika.dart
```

Each loader calls `build()` in `tool/mimeinfo.dart`, which:

1. Downloads or reads the cached upstream XML.
2. Parses the XML with `package:xml`.
3. Groups `<mime-type>` elements by their top-level type category
   (`application`, `image`, `text`, etc.).
4. For each category, emits a `mimeinfo_<category>.dart` file containing a
   single `final Registry mimeinfoDb<Category>` constant. Each `<mime-type>`
   element is mapped to a `RegistryEntry(...)` constructor call by `mapEntry()`.
5. Emits a central `mimeinfo.dart` that imports all category files and merges
   them into a single `final Registry mimeinfoDb` using spread syntax
   (`{...mimeinfoDbApplication, ...mimeinfoDbImage, ...}`).

All generated files include the Apache 2.0 licence header from
`header_template.txt` and a `// GENERATED CODE` banner. The `code_builder`
package is used to construct the Dart AST; `dartfmt` formats the output before
writing.

## XML-to-Dart mapping

| XML element / attribute                     | Dart field                                          |
| ------------------------------------------- | --------------------------------------------------- |
| `<mime-type type="…">`                      | `RegistryEntry.mediaType`                           |
| `<comment>`                                 | `RegistryEntry.comments` (as `IntlString.constant`) |
| `<acronym>` / `<expanded-acronym>`          | `RegistryEntry.acronym` / `expandedAcronym`         |
| `<icon name="…">`                           | `RegistryEntry.icon`                                |
| `<generic-icon name="…">`                   | `RegistryEntry.genericIcon`                         |
| `<sub-class-of type="…">`                   | `RegistryEntry.subclassOf`                          |
| `<alias type="…">`                          | `RegistryEntry.alias`                               |
| `<glob pattern="…" weight="…">`             | `RegistryEntry.globs` → `Glob`                      |
| `<magic priority="…"><match …>`             | `RegistryEntry.magic` → `Magic` + `Match`           |
| `<root-XML namespaceURI="…" localName="…">` | `RegistryEntry.rootXML` → `RootXML`                 |

Magic `value` strings are decoded from C-style escape sequences (octal `\012`,
hex `\x0a`, named `\n`, `\r`, `\t`, etc.) into the corresponding characters,
then re-encoded as safe Dart string literals by `_quote()`.

## Rebuilding from scratch

If the generated files are deleted or corrupted, temporarily swap to the
`emptyRegistry` variant in `lib/src/mediatype_detector_base.dart` (the two
commented-out lines next to each registry instantiation), regenerate with
`make load`, then swap back.

# Adding a new registry subclass

All three concrete registries (`TikaMimeInfoRegistry`,
`FreedesktopMimeInfoRegistry`, `OverrideMimeInfoRegistry`) follow the same
pattern — extend `MimeInfoRegistry` and pass the entry map to `super`:

```dart
class MyRegistry extends MimeInfoRegistry {
  MyRegistry(super.entries);
}
```

The entire detection pipeline (glob index construction, magic matching, root XML
matching, and `MatchList` conflict resolution) is inherited from
`MimeInfoRegistry` with no additional code required.

New registry types intended for use with `detect(customRegistry:)` must be
exported from `lib/betto_mediatype_detector.dart` so callers can import and
instantiate them.

# Testing

Tests live in `test/`. The minimum coverage requirement is **90%**; coverage is
measured with `make coverage` (generates an HTML report in `site/coverage/`).

| File                        | Scope                                                                                         |
| --------------------------- | --------------------------------------------------------------------------------------------- |
| `detect_test.dart`          | Integration tests for the blended `detect()` pipeline; real sample files from `test/data/`    |
| `freedesktop_test.dart`     | Full detection tests against the Freedesktop registry in isolation                            |
| `tika_test.dart`            | Full detection tests against the Tika registry in isolation                                   |
| `merge_dedup_test.dart`     | Unit tests for the three `_mergeResults()` deduplication scenarios                            |
| `custom_registry_test.dart` | Unit tests for all three registry layers: custom wins, override wins, fallthrough, null no-op |
| `spot_test.dart`            | Targeted spot-check tests for specific edge cases                                             |

`detect_test.dart` uses `skipGlob` / `skipFull` string annotations to mark known
failures in the blended pipeline. Removing a skip annotation and making the test
pass is the standard acceptance criterion when fixing a detection bug.
