# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## General

Work is planned using specifications in the `docs/plans` directory. When working
on plans make sure you review `docs/plans/README.md` file for guidance. When
asked to plan something do not commence implementation until explicitly told to
do so.

The `docs/roadmap` directory is used to track future work items and their
priority. This is worth reviewing when working on the codebase as current work
may intersect with the roadmap.

We'll create plans for our work and place them in the `docs/plans/` directory.
When the planned work has been completed we'll move them to
`docs/plans/completed`.

Quality assurance is critical to this project and you need to maintain a minimum
of 90% test coverage at all times. You must also run all tests successfully
before considering a task to be complete.

Consider edge-cases and failure scenarios when preparing tests - it is critical
not just to focus on easy, "golden-path" tests.

All public classes, methods and properties must have appropriate doc comments.
You may include examples in doc comments if you believe it will help another
developer.

Any complex segments of code should be commented so as to describe the process
and rationale for the approach.

All code files must have a license at the top. The template file is
`header_template.txt`. You must add the comment syntax appropriate to the
programming language. Also replace `{{.Year}}` to match the current year.

## Repository Layout

```
lib/
  betto_mediatype_detector.dart  # Public library entry point
  src/
    mediatype_detector_base.dart # Global registry singletons + top-level detect()
    mimeinfo/                    # Core domain: data model, detection logic, registry base
      base.dart                  # Re-exports for all mimeinfo types
      registry.dart              # MimeInfoRegistry abstract class (detect, matchGlob, matchMagic, matchRootXML)
      match.dart                 # MatchList + MatchResult
      entry.dart                 # RegistryEntry (per-type metadata: globs, magic, rootXML)
      glob.dart / glob_index.dart  # Glob matching + fast O(1) extension index
      magic.dart                 # Binary magic-number matching
      xml.dart                   # Root XML element matching
      icon.dart                  # GenericIcon enum
    freedesktop_mimeinfo/
      registry.dart              # FreedesktopMimeInfoRegistry (extends MimeInfoRegistry)
      g/                         # Generated Dart code from freedesktop.org XML database
    tika_mimeinfo/
      registry.dart              # TikaMimeInfoRegistry (extends MimeInfoRegistry)
      g/                         # Generated Dart code from Apache Tika XML database
    override_mimeinfo/
      registry.dart              # OverrideMimeInfoRegistry (extends MimeInfoRegistry)
      entries.dart               # Hand-authored correction entries (not generated)

tool/
  mimeinfo.dart                  # Code-generation helpers (shared by both loaders)
  freedesktop_mimeinfo.dart      # Runs freedesktop.org loader → lib/src/freedesktop_mimeinfo/g/
  tika.dart                      # Runs Tika loader → lib/src/tika_mimeinfo/g/
  copyright.dart                 # Loads license header for generated files
  data/                          # Cached source XML databases (checked in)

test/
  detect_test.dart               # Integration tests for the blended detect() pipeline
  freedesktop_test.dart          # Full detection tests against the Freedesktop registry
  tika_test.dart                 # Full detection tests against the Tika registry
  merge_dedup_test.dart          # Unit tests for _mergeResults() deduplication logic
  custom_registry_test.dart      # Unit tests for the layered registry pipeline
  spot_test.dart                 # Targeted / spot-check tests
  data/                          # Real sample files organised by media type category

bin/
  detect.dart                    # CLI entry point (dart run betto_mediatype_detector:detect)

example/                         # Usage examples
```

The files under `lib/src/freedesktop_mimeinfo/g/` and `lib/src/tika_mimeinfo/g/`
are **generated** — do not edit them by hand. Regenerate with `make load` (or
`make loader_tika` / `make loader_freedesktop_mimeinfo` individually).

## Commands

The `Makefile` should contain all key development lifecycle commands. In
general, `make` should be preferred to directly running commands such as `dart`.

```bash
# Run tests
make test

# Analyze/lint
make analyze

# Format code
make format

# Coverage (generates HTML report in site/coverage/)
make coverage

# Build docs site (requires pandoc)
make site

# Run checks before committing code (format check + analyze + license check)
make pre_commit

# Regenerate both MIME databases from their upstream XML sources
make load

# Regenerate only the Freedesktop database
make loader_freedesktop_mimeinfo

# Regenerate only the Tika database
make loader_tika

# Add/check license headers (uses addlicense_config.txt)
make license_add
make license_check
```

To run a single test file directly:

```bash
dart test test/freedesktop_test.dart
dart test test/spot_test.dart
```

## Architecture

`betto_mediatype_detector` is a pure Dart library (no Flutter dependency) that
identifies MIME types using three complementary strategies applied in priority
order:

1. **Magic matching** — byte-pattern inspection at specific offsets within file
   content.
2. **Glob matching** — filename pattern matching (e.g. `*.png`, `*.tar.gz`).
   Simple `*.ext` patterns are resolved via a pre-built extension index in O(1);
   complex patterns (e.g. `README*`, `*.tar.gz`) are checked with a linear scan.
3. **Root XML matching** — namespace and local-name inspection of the root
   element of XML-based formats. Only runs when magic or glob results suggest an
   XML-based type.

Detection results are wrapped in a `MatchList` that applies the Freedesktop
MIME-info spec's conflict-resolution rules (`_merge()`):

- Root XML results are definitive and returned immediately.
- Without magic, glob results are filtered to the most conservative (parent)
  type.
- When magic runs: types confirmed by both magic and glob are sorted first
  ("doubly confirmed"), followed by the parent-child filtering rules in
  `match.dart`.

The top-level `detect()` function runs a **layered registry pipeline** with
short-circuit semantics — the first layer to return a non-empty `MatchList`
wins:

1. **Caller registry** — optional `MimeInfoRegistry? customRegistry` parameter.
2. **Override registry** — `OverrideMimeInfoRegistry` backed by
   `override_mimeinfo/entries.dart`; hand-authored corrections for known bad
   upstream mappings (e.g. Tika's incorrect `*.rs` mapping).
3. **Blended registry** — Tika + Freedesktop results merged by `_mergeResults()`,
   which keeps the higher-priority duplicate (and on a tie, the entry with the
   richer `subclassOf` chain).

### Key types

| Type | Location | Role |
|---|---|---|
| `MimeInfoRegistry` | `lib/src/mimeinfo/registry.dart` | Abstract base; owns `detect`, `matchGlob`, `matchMagic`, `matchRootXML` |
| `RegistryEntry` | `lib/src/mimeinfo/entry.dart` | Per-type metadata: globs, magic rules, rootXML rules, comments, aliases |
| `MatchList` | `lib/src/mimeinfo/match.dart` | Result container; exposes `bestMatch`, `merged`, `candidates`, per-strategy lists |
| `MatchResult` | `lib/src/mimeinfo/match.dart` | Single match: `mediaType`, `priority`, `subclassOf`, `hasMagic` |
| `GlobIndex` | `lib/src/mimeinfo/glob_index.dart` | Fast extension index built once per registry instance |
| `OverrideMimeInfoRegistry` | `lib/src/override_mimeinfo/registry.dart` | Hand-authored corrections; consulted before the blended registry |

### Database code generation

The MIME databases are compiled from upstream XML sources into static Dart maps
(see `lib/src/{freedesktop,tika}_mimeinfo/g/`). The generation pipeline in
`tool/mimeinfo.dart` downloads the XML (or reads the cached file in `tool/data/`),
parses it, and emits one Dart file per top-level media type category
(`mimeinfo_application.dart`, `mimeinfo_image.dart`, etc.) plus a central
`mimeinfo.dart` that merges them.

If the generated files need to be rebuilt from scratch (e.g. after modifying the
generator), temporarily swap to the `emptyRegistry` variant in
`lib/src/mediatype_detector_base.dart` (the two commented-out lines next to each
registry instantiation).

## Documentation

Full specification is in [docs/spec/](docs/spec/) (Pandoc Markdown). The built
HTML lives in [site/](site/) and is generated via `make site`. The API reference
is generated into `site/api/` via `dart doc`.
