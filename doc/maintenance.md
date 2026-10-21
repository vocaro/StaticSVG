# Maintenance

How the renderer binary is built, checked and released, how its notices are kept, and what to
review when resvg changes. What the binary is and what its patches do is in
[the bundled renderer](renderer.md).

## Rebuilding the renderer

On Apple Silicon or Intel macOS with Xcode installed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-resvg.sh
```

The script downloads the pinned resvg source archive and the tiny-skia 0.12.0 crate and checks
their SHA-256, applies `scripts/patch-resvg.py` (which applies `scripts/resvg-panic-boundary.py`),
downloads an isolated Rust 1.95.0 toolchain under the build directory, builds the five Apple
targets, assembles `Resvg/Resvg.xcframework`, and regenerates `Resvg/dependencies.json`,
`Resvg/Licenses/` and `Resvg/checksums.json`. An existing framework is moved aside into the build
directory, not deleted. The developer's own Rust installation, Cargo registry and settings are
not used or changed. `STATICSVG_RESVG_BUILD_DIR` (default `.build/resvg`) and
`STATICSVG_RESVG_OUTPUT` (default `Resvg/Resvg.xcframework`) redirect the outputs; the notices
and checksums are written beside the framework.

The framework is not in Git: `.gitignore` leaves out `Resvg/Resvg.xcframework` and its zip. To
test a rebuilt framework in this checkout, set `STATICSVG_LOCAL_RESVG=1`, which makes
`Package.swift` use the local framework in place of the release asset:

```sh
STATICSVG_LOCAL_RESVG=1 swift test
```

A released framework can be put back in place for that from its asset:

```sh
curl -L -o Resvg/Resvg.xcframework.zip https://github.com/vocaro/StaticSVG/releases/download/0.1.0/Resvg.xcframework.zip
ditto -x -k Resvg/Resvg.xcframework.zip Resvg
python3 scripts/verify-resvg.py
```

### Reproducing a released binary

Rust records the absolute paths of the sources it compiles in the panic locations it embeds, so
a library built in another directory differs from a released one by those strings even when
every input is the same. The 0.1.0 libraries were built by EPUBLib's copy of this script at
`/Users/trevorharmon/.codex/worktrees/priority-renderer-panics/EPUBLib/.build/resvg`. Mapping a
build directory onto that path reproduces them:

```sh
work=$PWD/.build/resvg-check
STATICSVG_RESVG_BUILD_DIR=$work STATICSVG_RESVG_OUTPUT=$work/out/Resvg.xcframework \
RUSTFLAGS="--remap-path-prefix=$work=/Users/trevorharmon/.codex/worktrees/priority-renderer-panics/EPUBLib/.build/resvg" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-resvg.sh
python3 scripts/verify-resvg.py "$work/out/Resvg.xcframework"
```

The result of that check for 0.1.0 is recorded on
[vocaro/EPUBLib#636](https://github.com/vocaro/EPUBLib/issues/636). A later release can set a
neutral prefix in the script itself, which changes the libraries once.

The comments the patches insert still say "EPUBLib:", as they did when the policies lived there,
so that the header in a rebuilt framework is the released one byte for byte.

## Checking a framework

```sh
python3 scripts/verify-resvg.py [path/to/Resvg.xcframework]
```

checks each library's SHA-256 against `Resvg/checksums.json`, that the framework has the iOS
device (arm64), iOS simulator (arm64, x86_64) and macOS (arm64, x86_64) slices, and that the
three share one patched header. A rebuild that changes a library changes `checksums.json` with
it; the diff then shows which.

## Releasing

1. With the framework in `Resvg/Resvg.xcframework` and `checksums.json` matching it, write the
   release asset and print its checksum:

   ```sh
   bash scripts/package-resvg.sh
   ```

   It zips the framework without extended attributes to `Resvg/Resvg.xcframework.zip`, unzips
   that into a temporary directory and checks the libraries there, and prints
   `swift package compute-checksum` for the zip.
2. In `Package.swift`, name the release's asset URL and that checksum. Add the release to
   [CHANGELOG.md](../CHANGELOG.md), with the library checksums when they changed.
3. Merge, tag the merge commit with the version, and publish a GitHub release for the tag with
   the zip as its asset, named `Resvg.xcframework.zip`.
4. From a fresh clone of the tag, with no local framework, resolve and run the tests on the Mac
   and on an iOS simulator ([testing](testing.md)). SwiftPM fetches the asset and checks its
   checksum; a mismatch fails the resolve.

Never replace or delete a published asset; a changed binary is a new release.

## Notices

`scripts/resvg-notices.py` collects, from the locked Cargo metadata, every normal (not build or
dev) dependency of `resvg-capi` built with the release's features, copies each crate's license,
copyright, notice and copying files into `Resvg/Licenses/<crate>-<version>/`, and writes the
inventory, with each crate's declared license and repository, to `Resvg/dependencies.json`.
resvg, usvg and resvg-capi take the workspace's own MIT and Apache-2.0 texts. Rust's
standard-library copyright and third-party notices come from the toolchain's documentation. A
crate with no license file stops the script. After a rebuild, review the diff of
`Resvg/dependencies.json` and `Resvg/Licenses/`: a new crate, version or license is a change to
what an application must retain ([third-party notices](../THIRD_PARTY_NOTICES.md)).

## When resvg changes

An upgrade of resvg, or of any crate the screens read (usvg, svgtypes, simplecss, roxmltree,
tiny-skia, kurbo), is a release of its own.

- Re-pin the source archive and its SHA-256 in `scripts/build-resvg.sh`, and the tiny-skia crate
  and its checksum where it changed. Each patch asserts the exact text it replaces and stops the
  build when upstream no longer matches; rewrite the patch against the new source, never loosen
  the assertion.
- Read again every upstream function a screen names as its source: the reference walks
  (`fix_recursive_links`, `HrefIter`, marker recursion, `convert_element`), svgtypes' `url(#…)`
  reading, simplecss's tokenizer, usvg's per-shape copies (`write_declaration`,
  `insert_attribute`, `paint_server.rs`, `units.rs`), kurbo's arc flattening and the raster
  layer sizes. Where the upstream behavior changed, change the screen and its tests with it, and
  keep each bound's tests at the bound and just past it.
- Run the probes in [testing](testing.md#probes) against the new build: a bound set from
  measurement is measured again.

### Retiring a patch or a screen

A patch or screen exists because the pinned upstream lacks something. When upstream provides it,
retire the patch or screen in its own change, with its tests kept as regression tests that now
pass through upstream's behavior:

- The image-resolver patch, when usvg's C API lets a caller refuse every non-data `href` and
  nested SVG.
- The font-method feature-gate patch, when upstream gates the filesystem font methods on
  `system-fonts`.
- The panic boundary, when the C API catches panics itself and reports them per call.
- The tiny-skia unwind guard, when its `SuperBlitter` drop no longer flushes during unwinding.
- A loop or depth screen, when usvg detects that loop or bounds that recursion itself. A
  stylesheet or copy screen, when usvg bounds that work. Keep a screen while any supported
  renderer version needs it.

[Documentation index](../README.md#documentation)
