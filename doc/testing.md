# Testing

```sh
swift test
```

The suite runs on the Mac without network access once the renderer is resolved. Run the
optimized build as well: a test that passes in a debug build can fail there, where references
are dropped sooner and the stack is used differently.

```sh
swift test -c release -Xswiftc -enable-testing
```

For iOS, run the same tests on a simulator this run creates and deletes, giving its identifier
to every command and never the booted device, as the shared rules that
`python3 scripts/eng instructions` prints require:

```sh
udid=$(xcrun simctl create "StaticSVG-test-$(uuidgen)" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-27-2)
trap 'xcrun simctl shutdown "$udid" 2>/dev/null; xcrun simctl delete "$udid"' EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcodebuild test -scheme StaticSVG -destination "platform=iOS Simulator,id=$udid"
```

On the owner's shared host, builds and tests go through admission. The `tests` lane runs
`swift test`; arguments after `--` go to it, such as a filter or the optimized build's flags:

```sh
python3 scripts/eng run tests
python3 scripts/eng run tests -- --filter SVGDocumentTests
```

A filtered run proves something only when it ran tests: check the executed count. Some cases
measure thread CPU time with generous ceilings, to show a screen's work stays linear; a heavily
loaded machine can still slow them, so record the load beside a failure and run it again before
blaming a change.

The renderer is a release asset, so a checkout tests the released framework unless
`STATICSVG_LOCAL_RESVG=1` points `Package.swift` at a local build in `Resvg/Resvg.xcframework`
([maintenance](maintenance.md#rebuilding-the-renderer)).

## The release gate

A release is tagged only on a commit whose gate passed ([maintenance](maintenance.md#releasing)).
The `gate` lane runs, at one commit and through admission, everything this page asks of a
release:

```sh
python3 scripts/eng run gate
```

`scripts/gate.py` runs its own tests, `python3 scripts/eng docs check` and
`python3 scripts/eng spelling`, then the suite three times: with `swift test`, with
`swift test -c release -Xswiftc -enable-testing`, each in its own scratch directory under
`.build/gate`, and with `xcodebuild test -scheme StaticSVG` on an iPhone 17 Pro simulator of the
iOS 27.2 runtime, which it creates under a unique name, boots to `simctl bootstatus -b` and
deletes by its identifier however the run ends. Each run must execute at least 155 tests with
none failed. The only test allowed to skip is
`SVGFontSizeCostTests.testGeneratedProbeFixturesMatchScreen`, the opt-in
[font-size cost probe](#font-size-cost-probe), which needs generated inputs; any other skip
fails the run. Each run must also have linked the renderer this commit records: the copy of
`libresvg.a` its build leaves among its products, the macOS slice for `swift test` and the
simulator slice for `xcodebuild`, must have the SHA-256 that `Resvg/checksums.json` gives it,
whichever `Resvg.xcframework` `Package.swift` took; a run whose build left no copy is
unmeasured. Admission counts the gate as one job, so its builds take two jobs and the simulator
runs its tests in one process.

The gate exits 0 only when every step passed and 1 when any failed. It exits 3, never 0, when
none failed but one is unmeasured: the runtime is missing, the simulator did not finish booting
within ten minutes, a step gave no result within its hang bound, or an `eng` check could not
run, which it reports by exiting 2, as it does when it finds no toolkit. A step that changes the
checkout fails the gate. The lane's log, `.build/engineering/gate/run.log`, ends with the
commit, the framework `Package.swift` was told to take, and each step's outcome, a suite's with
the renderer it linked.

The gate finds the toolkit as `scripts/eng` does, from a session's worktree too, and runs its
checks against that checkout. From a clone that has no `apple-engineering` beside it or beside
its main checkout, set `VOCARO_ENGINEERING_ROOT`. The runtime is named in `scripts/gate.py`;
move it in a commit of its own when the host's Xcode moves on.

## What the tests cover

Most of the suite moved from EPUBLib, where each bound was set; the tests keep their names and
their links to the EPUBLib issues that record the measurements. EPUBLib keeps the tests that
need a book: archive resources, manifest fallbacks, inline SVG in XHTML, HTML-recovered SVG,
disclosures in a section's report, attachments and relayout.

- `SVGDocumentTests`: the parser's refusals (entity declarations, internal DTD subsets, the
  attribute cap, encodings that would read the bytes otherwise, malformed XML), its limits, and
  a built tree matching a parsed one.
- `SVGBoundsCoverageTests`, `SVGCopyBoundsCoverageTests`, `SVGRenderingCostCoverageTests`,
  `SVGFontSizeCostTests`, `SVGStyleScreenTests`, `SVGReferenceCoverageTests`,
  `SVGGeometryCostScreenTests`, `SVGRasterCostCoverageTests`: each screen at its bound and just
  past it, the work each screen itself does, and ordinary drawings that must still draw.
- `SVGSanitizerCSSTests`, `SVGCoverageTests`, `SVGImagePreparationTests`: serialization, filter
  omission, data and provider images, nested drawings and the shared image budgets.
- `SVGRenderingTests`, `SVGRendererPanicTests`: drawing, font export and databases, layer
  budgets, and every known renderer panic contained at the C boundary, through the raw C API as
  well as `SVGRenderer`.
- `ReadmeExampleTests`: the README's quick start.

## Probes

The probes measure the renderer itself, in child processes they cap; their results are
recorded on issues, never used as test thresholds. Both link the macOS library in
`Resvg/Resvg.xcframework`, so put the released framework there first
([maintenance](maintenance.md#rebuilding-the-renderer)).

### Rendering cost probe

`scripts/svg-cost-probe.py` links the unmodified bundled macOS library into a C child for each
generated SVG, measured as
[fresh-process memory metrics](https://github.com/vocaro/apple-engineering/blob/main/guides/measurement.md#fresh-process-memory-metrics)
describes for a third-party component: each child parses one drawing, reports its peak RSS and
parse duration and destroys its tree. The parent terminates a child exceeding 256 MiB RSS or
ten seconds. No fonts, markers or hostile maximal inputs are involved. Each
shape is a nonzero 1-by-1 rectangle; each referencing shape is 2-by-2, so conversion cannot be
dismissed as empty. These are parse and conversion measurements, not raster render measurements.

```sh
python3 scripts/svg-cost-probe.py --output /private/tmp/svg-cost-probe
```

The twelve measurements of 2026-10-13 are on
[EPUBLib#176](https://github.com/vocaro/EPUBLib/issues/176#issuecomment-6159294552).

### Font-size cost probe

`scripts/svg-font-size-probe.py` reproduces the padded-font-size dash-array case and generates
64-byte boundary inputs, maximal `em`/`ex` arrays at shallow and deep ancestry, text positioning
lists, and scalar stroke lengths. The commands screen the generated bytes with the current
Swift implementation and then measure the bundled renderer, as
[fresh-process memory metrics](https://github.com/vocaro/apple-engineering/blob/main/guides/measurement.md#fresh-process-memory-metrics)
describes:

```sh
python3 scripts/svg-font-size-probe.py --generate-only --output /private/tmp/svg-font-size-probe
STATICSVG_FONT_SIZE_PROBE_MANIFEST=/private/tmp/svg-font-size-probe/manifest.json swift test --filter SVGFontSizeCostTests/testGeneratedProbeFixturesMatchScreen
python3 scripts/svg-font-size-probe.py --output /private/tmp/svg-font-size-probe --screen-json /private/tmp/svg-font-size-probe/screen-verdicts.json --render-refused
```

The manifest and verdicts match by bytes and SHA-256; `STATICSVG_FONT_SIZE_PROBE_VERDICTS`
writes the verdicts elsewhere. The probe applies a 20-second CPU limit, a 30-second wall limit
and a 512 MiB resident-memory limit by default. `--render-refused` additionally measures the
original padded reproducer; all other refused inputs are skipped. Font lookup and shaping are not
measured: text positioning resolves before font selection. Measurements and the commit they
qualify belong on [EPUBLib#443](https://github.com/vocaro/EPUBLib/issues/443) or a StaticSVG issue.

[Documentation index](../README.md#documentation)
