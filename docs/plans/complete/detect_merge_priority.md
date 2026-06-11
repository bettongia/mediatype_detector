# Merge priority bugs and registry extensibility in blended detect()

**Status**: Complete

**PR link**: —

## Problem statement

This plan covers two related concerns: fixing merge-ordering bugs in the blended
`detect()` function, and extending `detect()` with a layered registry model so
that callers can supplement or override built-in detection.

### Detection pipeline

Once all items are implemented, `detect()` should resolve media types through
the following ordered pipeline, stopping as soon as a match is found:

1. **Caller registry** — an optional `MimeInfoRegistry` supplied by the caller
   at the point of calling `detect()`. Allows per-call overrides without
   touching global state.
2. **Override registry** — a built-in registry maintained in this package for
   file types not yet covered by either Tika or Freedesktop, or to correct known
   bad mappings (e.g. the `.rs` / `.key` / `.html` priority issues below).
3. **Blended registry** — the merged Tika + Freedesktop result as implemented
   today.

The first registry that produces a non-empty `MatchList` wins; its result is
returned directly without merging with lower-priority registries.

### 5. Override registry

There is currently no mechanism to correct known bad mappings or add coverage
for file types absent from both Tika and Freedesktop without modifying the code
generator. An override registry — a hand-authored `RegistryEntry` map loaded
into a `MimeInfoRegistry` subclass — would allow targeted fixes (e.g. correcting
the `.rs`, `.key`, and `.html` priority bugs below) and forward-looking entries
for emerging formats, without waiting for upstream databases to be updated.

### 6. Caller-provided custom registry

`detect()` currently offers no extension point. Callers who need to detect
proprietary or domain-specific media types must implement their own detection
from scratch. Adding an optional `MimeInfoRegistry? customRegistry` parameter to
`detect()` lets callers supply their own registry (any class extending
`MimeInfoRegistry`) that is consulted first, before the override and blended
registries.

---

The following four bugs affect the existing blended registry (pipeline step 3).
Some may be resolved by entries in the override registry (step 2) rather than
changes to the merge logic.

### 1. `.html` glob — priority contamination

Both registries individually return `text/html` as the best glob match for
`*.html` files. In the merged results, `application/xhtml+xml` appears at a
higher combined priority and sorts first. Full detection is unaffected (magic
correctly confirms `text/html`), but glob-only detection returns the wrong type.

### 2. `.key` glob — extension ambiguity

Both registries individually return `application/vnd.apple.keynote` as the best
glob match for `*.key` files. In the merged results, `application/pgp-keys`
appears at a higher combined priority and sorts first, producing the wrong glob
and full detection result.

### 3. OOXML full detection — conflicting magic supertypes

Freedesktop alone correctly identifies `.docx`, `.xlsx`, and `.pptx` files in
full detection (glob wins over `application/zip` magic). Tika's magic returns
`application/x-tika-ooxml` for these files, which is a Tika-internal supertype
not present in Freedesktop. When the two magic result lists are merged, the
`MatchList._merge()` logic can no longer reconcile the OOXML glob type against
either magic supertype, so the glob refinement fails and the result degrades to
`application/zip`.

### 4. `.rs` glob — wrong Tika mapping bleeds through

Freedesktop alone correctly maps `*.rs` to `text/rust`. Tika erroneously maps
`*.rs` to `application/rls-services+xml` (a higher-priority entry in its
database). Because Tika is the primary source in `_mergeResults()`, the wrong
type sorts first and `text/rust` is suppressed in both glob and full detection.

## Open questions

These questions materially affect the implementation approach and should be
resolved before moving to `Investigated`.

- [x] **Are the four bugs a merge-logic problem or an override-registry
      problem?** **Decision: fix the merge logic.** Bugs 1–3 (`.html`, `.key`,
      OOXML) will be resolved by correcting `_mergeResults()` dedup — keeping
      the higher-priority / richer duplicate rather than blindly keeping the
      Tika primary. The override registry is reserved for genuinely
      missing/incorrect upstream data only.
- [x] **Should the override registry exist at all in v1, or is it scope creep?**
      **Decision: ship it now.** The override registry will be implemented in
      this plan. Initial content is the `.rs` correction; it is designed as a
      hand-authored `RegistryEntry` map for future targeted fixes without
      upstream dependency.
- [x] **What is the precedence model — "first non-empty registry wins" or "merge
      across layers"?** **Decision: short-circuit.** The first registry to
      return a non-empty `MatchList` wins; lower layers are not consulted.
      Override and custom entries that cover magic-confirmable types must
      include their own magic rules (not an issue for `.rs`, the current sole
      override entry).
- [x] **Does the override registry participate in the existing blend, or sit in
      front of it?** **Decision: in front (short-circuit).** The override
      registry is consulted before the blended Tika+Freedesktop result, in the
      same short-circuit fashion.
- [x] **Public API shape for the caller registry.** **Decision:**
      `MimeInfoRegistry? customRegistry` — a single named optional parameter. No
      provenance field in the result for now.

## Investigation

### Where detection happens

The blended pipeline lives entirely in `lib/src/mediatype_detector_base.dart`.
The top-level `detect()` calls `matchGlob` / `matchMagic` / `matchRootXML` on
each registry, then combines each stage's two lists with the local
`_mergeResults()` helper, and finally constructs a `MatchList`
(`lib/src/mimeinfo/match.dart`) which applies the Freedesktop
conflict-resolution rules in `MatchList._merge()`.

Two distinct merge steps are involved and it is important not to conflate them:

1. `_mergeResults(primary, secondary)` in `mediatype_detector_base.dart` —
   concatenates Tika (primary) + Freedesktop (secondary), **dedups by media type
   keeping the first occurrence**, then sorts by priority descending.
2. `MatchList._merge()` in `match.dart` — applies parent/child and
   doubly-confirmed logic across the already-merged glob/magic/rootXML lists.

### Root-cause analysis of the four bugs

I reproduced each bug against the real registries. The observed glob/magic
priorities are below.

**1. `.html` (glob).** Tika: `text/html`=50. Freedesktop: `text/html`=80,
`application/xhtml+xml`=50. In `_mergeResults`, Tika is primary, so the
`text/html` kept is **Tika's priority-50 entry** — Freedesktop's priority-80
`text/html` is discarded by the dedup. `text/html`(50) now ties with
`application/xhtml+xml`(50); after `MatchList._merge` glob-only filtering and
the comparator tie-break, `application/xhtml+xml` sorts first. **Root cause:
`_mergeResults` dedup keeps the lower-priority duplicate.** The plan's framing
("both registries individually return text/html") is true but incomplete — the
defect is the dedup throwing away the higher-priority duplicate, not anything
intrinsic to the two databases.

**2. `.key` (glob).** Identical mechanism. Tika: `keynote`=50. Freedesktop:
`keynote`=80, `pgp-keys`=50. Dedup keeps Tika's `keynote`(50); it ties with
`pgp-keys`(50) and loses the tie-break. Same root cause as `.html`.

**3. OOXML full detection.** docx/xlsx/pptx glob entries have `hasMagic=false`
in both registries, so `MatchList._merge` correctly _keeps_ the glob entry (rule
a). The failure is in parentage: Freedesktop's docx glob carries
`subclassOf=[application/zip]`; Tika's carries
`subclassOf=[application/x-tika- ooxml]`. `_mergeResults` keeps **Tika's** docx
entry, so the merged glob entry's parent is `x-tika-ooxml`, not `zip`. Magic
results are `application/zip`(60, from FD) and `x-tika-ooxml`(50, from Tika).
Because the surviving docx glob no longer declares `zip` as a parent, the
parent-child rule that would let docx win over `application/zip` magic never
fires, and `application/zip`(60) stays on top. **Root cause: same dedup, now
discarding the richer `subclassOf` chain.** This is _not_ an
irreconcilable-supertype problem as the plan states; it is the dedup dropping
the Freedesktop entry that carried the usable parent.

**4. `.rs` (glob).** Tika: `application/rls-services+xml`=50. Freedesktop:
`text/rust`=50. Genuine tie at priority 50. Tika is primary, so its (incorrect)
`rls-services+xml` is emitted first and wins. This is the only bug that is a
real upstream-data defect rather than a merge artefact — Tika's `*.rs` → XML
mapping is simply wrong. It can be fixed either by an override entry, by a
correctness-priority tweak, or by demoting `+xml` glob matches that conflict
with a non-XML text type.

### Implications for the proposed solution

- Bugs 1–3 are fixable by making `_mergeResults` **keep the higher-priority /
  richer duplicate** rather than blindly keeping the primary. The minimal change
  is: when the same media type appears in both lists, keep the entry with the
  greater glob weight (and, on a tie, prefer the entry with a non-empty / longer
  `subclassOf` chain so OOXML retains its `zip` parentage). This is a ~10-line
  change to one private function and is covered by the existing skipped tests in
  `test/detect_test.dart`.
- Only bug 4 needs data correction. Whether that justifies the full override
  registry is the central open question.
- The existing test suite already encodes the _correct_ expectations: every one
  of the four bugs has a `skip*` annotation in `test/detect_test.dart` with the
  right `expected` values inline. Removing the relevant `skipGlob` / `skipFull`
  strings is the acceptance criterion — no new assertions are required, which is
  a strong signal the fix is well-scoped.

### Extension points for the registry layering

- `MimeInfoRegistry` (`lib/src/mimeinfo/registry.dart`) is already an abstract
  base taking a `Map<String, List<RegistryEntry>>`. A hand-authored override
  registry is a trivial subclass (cf. `FreedesktopMimeInfoRegistry` /
  `TikaMimeInfoRegistry`, each ~5 lines) fed a static map. No new infrastructure
  is needed beyond the entry data itself and a way to author it (hand-written
  Dart map, or a small XML + generator pass mirroring `tool/mimeinfo.dart`).
- The caller-registry parameter is a pure additive change to the top-level
  `detect()` signature. It must remain a named optional parameter to preserve
  source compatibility for existing callers (`bin/detect.dart`,
  `example/main.dart`, all tests).
- **Short-circuit semantics caveat:** the proposed "first non-empty MatchList
  wins" means a caller/override registry that matches only by _glob_ will
  suppress the blended registry's _magic_ and _rootXML_ stages for that file.
  For the `.html`/`.key` override entries this would regress full detection
  unless the override entries also carry the magic rules. This is the strongest
  argument for fixing `_mergeResults` instead of overriding.

### Architecture / library-architecture check

This package is pure-Dart core only (no Flutter, no Presentation/App layers), so
the `library-architecture` skill's layer-boundary concerns do not apply. The
public barrel is `lib/betto_mediatype_detector.dart`, which re-exports
`src/mediatype_detector_base.dart`. The changes here are confined to the core
layer and the public `detect()` surface. Points to preserve:

- Any new override registry class and the `customRegistry` parameter type must
  be exported from the barrel, or callers cannot construct/pass them.
- The override entry map, if hand-authored, is a _source_ file (not generated)
  and needs the Apache licence header from `header_template.txt` (`{{ Year }}` →
  2026). If it is generated, it belongs under a `g/` directory and must not be
  hand-edited.
- `design` / `inclusivity` skills are not applicable — there is no UI.

### Spec and roadmap alignment

- `docs/spec/` contains only an empty `README.md`; there is no written
  specification to contradict. However, adding a public extension point and a
  third detection layer is exactly the kind of behaviour the spec should
  document. The spec is currently a stub, so "update the spec" cannot be a
  concrete task — but the detection-precedence model (including the
  short-circuit rule) should be written down somewhere durable as part of this
  work, even if only in the README or dartdoc on `detect()`.
- `docs/roadmap/` contains only the template `README.md` — no versioned roadmap
  exists, so there is no roadmap item to link or mark complete. If this work is
  intended to be release-tracked, a roadmap file should be created; otherwise
  note explicitly that this plan is roadmap-independent.

### Test coverage

The 90% coverage bar applies. New tests required:

- Unit tests for the revised `_mergeResults` dedup behaviour (duplicate with
  higher secondary priority; duplicate with richer `subclassOf`; genuine tie).
- For the override registry (if built): tests that an override entry wins over
  the blended result, and that absence of an override falls through.
- For the caller registry: a custom `MimeInfoRegistry` passed to `detect()`
  short-circuits correctly; passing `null` is a no-op; the existing blended
  results are unchanged when no custom registry is supplied.
- Un-skip the four bug cases in `test/detect_test.dart` and confirm they pass.

## Implementation plan

The plan is split into independently shippable phases. Phase 1 alone closes
three of the four bugs and is low-risk; later phases depend on the open
questions being resolved.

### Phase 1 — Fix the merge-dedup root cause (bugs 1, 2, 3)

- [x] Change `_mergeResults` in `mediatype_detector_base.dart` so that, for a
      duplicate media type, it keeps the entry with the higher glob weight; on a
      weight tie, prefer the entry with the richer `subclassOf` chain.
- [x] Add unit tests for the three dedup scenarios.
- [x] Remove `skipGlob` from `.html` / `test_html4.html` and `.key`, and
      `skipFull` from `.docx` / `.xlsx` / `.pptx` and `.key` in
      `test/detect_test.dart`; confirm they pass.
- [x] Run `make test` and `make coverage`; confirm ≥ 90%.

### Phase 2 — Resolve `.rs` (bug 4)

- [x] Decide per open questions: targeted tie-break/priority rule vs. override
      registry entry.
- [x] Implement the chosen fix; remove the `.rs` `skipGlob`/`skipFull`.
- [x] Add a regression test.

### Phase 3 — Override registry (only if approved)

- [x] Decide hand-authored map vs. XML + generator pass.
- [x] Add the override `MimeInfoRegistry` subclass + entry data with licence
      header; export from the barrel.
- [x] Wire it into `detect()` ahead of the blended registry per the agreed
      precedence model.
- [x] Tests: override-wins, fall-through, and no-regression of blended results.

### Phase 4 — Caller-provided registry

- [x] Add `MimeInfoRegistry? customRegistry` (or agreed signature) to the
      top-level `detect()`.
- [x] Implement the agreed precedence (short-circuit vs. per-stage merge).
- [x] Document the precedence model in `detect()` dartdoc (and spec/README).
- [x] Tests for custom-registry precedence, null no-op, and provenance if added.

### Cross-cutting

- [x] Update dartdoc on `detect()` to describe the layered pipeline.
- [x] Run `make pre_commit` (now includes `test`).
- [ ] Update the summary section of this document.

## Reviews

### Review 1: 2026-06-12

**Problem Statement Assessment.** The four bugs are real and reproducible — I
confirmed each against the live registries, and the existing test suite already
encodes the correct expectations behind `skip` flags, which is a strong sign the
problems are well-understood. However, the problem statement _mis-attributes the
root cause_ of three of them. The plan treats `.html`, `.key`, and OOXML as
separate phenomena (priority contamination, extension ambiguity, irreconcilable
magic supertypes) and proposes the override registry as the remedy. In fact all
three are one bug: `_mergeResults()` dedups duplicates by keeping the _primary_
(Tika) entry and discarding the secondary (Freedesktop) entry even when the
secondary has a higher glob weight (`.html` 80 vs 50, `.key` 80 vs 50) or a
richer `subclassOf` chain (OOXML's `application/zip` parentage). One ~10-line
fix to that function closes all three, with no override entries at all. Only
`.rs` is a genuine upstream-data defect. I'd push back firmly on framing these
as a motivation for the override registry — that conflates a cheap merge fix
with a substantial new subsystem.

**Proposed Solution Assessment.** The caller-registry extension point is clean,
additive, and low-risk: `MimeInfoRegistry` is already an abstract base designed
for subclassing, and adding a named optional parameter to `detect()` preserves
compatibility. The override registry is where I have reservations. It is being
justified almost entirely by bugs that don't need it, leaving a single one-line
correction (`.rs`) as its real workload. Building a hand-authored entry map plus
loader/generator/tests for one correction is poor cost/benefit _today_ — though
it is a reasonable forward-looking facility for formats absent from both
upstreams. I'd separate "fix the bugs" (cheap, now) from "introduce an override
layer" (deferrable, deserves its own plan).

**Architecture Fit.** This is a pure-Dart core package; the
`library-architecture` layer checks pass trivially (no Flutter, no
Presentation/App layers, single barrel). The changes stay in the core layer and
the public `detect()` surface. New types (override registry, custom-registry
parameter type) must be exported from `lib/betto_mediatype_detector.dart`.
`design`/`inclusivity` skills are not applicable — no UI. The spec
(`docs/spec/`) and roadmap (`docs/roadmap/`) are both empty stubs, so there is
nothing to contradict, but the detection-precedence model genuinely should be
written down as part of this work.

**Risk & Edge Cases.** The biggest risk is the proposed "first non-empty
MatchList wins" short-circuit. A caller or override registry that matches only
by _glob_ would suppress the blended registry's _magic_ and _rootXML_ stages for
that file. Concretely, an override `.html` entry without magic rules would
_reintroduce_ the full-detection regression Phase 1 just fixed. The
short-circuit semantics need to be confirmed and documented precisely, and
override entries that shadow magic-confirmable types must carry their own magic
rules — or the override registry must participate in the per-stage blend rather
than short-circuiting. Secondary risks: the tie-break direction in the
`_mergeResults` fix must be deterministic (Dart `sort` is not stable) so
`.rs`-style 50/50 ties resolve predictably; and changing `_mergeResults` is
global, so the full `detect_test.dart` matrix (not just the four un-skipped
cases) must stay green.

**Recommendations.**

1. Reframe the plan: bugs 1–3 are a single `_mergeResults` dedup defect, not an
   override-registry use case. Fix that function first (Phase 1) and un-skip the
   six affected test cases — this is the highest-value, lowest-risk change.
2. Treat `.rs` as the only data-correction case and decide deliberately whether
   it warrants the override registry or a smaller targeted rule.
3. Strongly consider splitting the override registry into its own plan. As
   specified it is scope creep relative to the bugs it claims to solve.
4. Pin down the precedence model (short-circuit vs. per-stage merge) and the
   public `detect()` signature before any registry-layering code is written;
   both are load-bearing public-API decisions.
5. Add a short written description of the detection-precedence pipeline (dartdoc
   on `detect()` at minimum) since the spec is currently a stub.

This plan is **not yet ready for implementation** because the root-cause
mis-attribution changes the shape of the solution and several public-API/
precedence decisions are unresolved. Status set to **Questions**. Phase 1,
however, is well-understood and could proceed independently once the framing in
the problem statement is accepted.

Open questions from this review (also reflected in the top-level section):

- [x] Confirm bugs 1–3 are fixed via `_mergeResults` rather than the override
      registry. **Resolved: yes, fix via merge logic.**
- [x] Confirm whether the override registry ships now or is deferred to its own
      plan. **Resolved: ships in this plan.**
- [x] Confirm short-circuit vs. per-stage-merge precedence semantics.
      **Resolved: short-circuit.**
- [x] Finalise the public `detect()` signature for the caller registry.
      **Resolved: `MimeInfoRegistry? customRegistry`, no provenance.**

## Summary

- Fixed `_mergeResults()` in `lib/src/mediatype_detector_base.dart` to keep the
  higher-priority entry when the same media type appears in both Tika and
  Freedesktop results; on a priority tie, prefers the entry with the richer
  `subclassOf` chain. This single ~10-line change closed bugs 1–3 (`.html`,
  `.key`, OOXML full detection).
- Updated the audio dedup tests for `test.aiff` and `test.wav`: their magic
  expectations changed from the parent container types (`application/x-iff`,
  `application/x-riff`) to the correctly-resolved specific types
  (`audio/x-aiff`, `audio/vnd.wave`), which are the actual correct results now
  that the higher-priority Freedesktop entries are kept.
- Removed all `skipGlob`/`skipFull` annotations for `.html`, `test_html4.html`,
  `.key`, `.docx`, `.xlsx`, `.pptx` — all now pass without skips.
- Created `lib/src/override_mimeinfo/entries.dart` — hand-authored static map
  with one initial entry: `text/rust` for `*.rs` at glob weight 60, overriding
  Tika's wrong `application/rls-services+xml` mapping.
- Created `lib/src/override_mimeinfo/registry.dart` —
  `OverrideMimeInfoRegistry` subclass exported from the public barrel via
  `lib/src/mediatype_detector_base.dart`.
- Added `overrideMimeInfoRegistry` singleton and wired it as layer 2 in the
  `detect()` pipeline (short-circuit semantics: first non-empty `MatchList`
  wins). Removed `.rs` skip annotations — all four `.rs` tests now pass.
- Added `MimeInfoRegistry? customRegistry` named optional parameter to
  `detect()` as layer 1 of the pipeline. Existing callers are source-compatible.
- Wrote `test/merge_dedup_test.dart` (7 tests) covering the three dedup
  scenarios: higher-priority secondary, richer `subclassOf` secondary, and
  deterministic tie resolution.
- Wrote `test/custom_registry_test.dart` (10 tests) covering: override-wins,
  override fall-through, custom-wins, custom short-circuits override, null no-op,
  miss-falls-through-to-override, miss-falls-through-to-blended, and
  bytes-forwarded-to-custom-registry.
- All 611 tests pass; `make pre_commit` (format, analyze, license, test) is
  green. No deviations from the agreed implementation approach.
- No roadmap item exists for this plan; `docs/roadmap/` contains only the
  template README.
