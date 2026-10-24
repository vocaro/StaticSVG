# StaticSVG contributor instructions

## Shared engineering guidance

Before work, run `python3 scripts/eng instructions` to read the common rules and enabled
capabilities, then follow the project-specific instructions below. `engineering.json` locates
the shared `vocaro-engineering` checkout; set `VOCARO_ENGINEERING_ROOT` for another location.
Before shared device, foreground or runner use, run `python3 scripts/eng policy refresh` and
read this project's current main instructions. Shipping Swift targets do not link the
engineering toolkit, which is public and MIT licensed.

Build and test procedures are in [doc/testing.md](doc/testing.md). How to rebuild, verify and
release the renderer binary is in [doc/maintenance.md](doc/maintenance.md).

## The renderer binary

- A release's `Package.swift` names its `Resvg.xcframework.zip` release asset by URL and
  checksum. Never replace or delete a published asset: a consumer pinned to that release would
  stop resolving. A changed binary is a new release.
- Rebuild only with `scripts/build-resvg.sh`, from the pinned sources, and record the library
  checksums in `Resvg/checksums.json` and the release notes. Keep a renderer upgrade, or a new
  patch to it, apart from any other change, in a release of its own.
- When resvg, usvg, svgtypes, simplecss, roxmltree or tiny-skia changes, read the screens'
  stated sources again before the release ([maintenance](doc/maintenance.md#when-resvg-changes)).

## Behavior and its consumers

- EPUBLib depends on an exact release. A change to what a drawing draws, refuses, discloses or
  costs reaches its readers when it next updates, so say in the release notes what changed,
  with the issue.
- Expectations come from the SVG and CSS specifications, the renderer's pinned sources and
  measurements recorded on issues, not from what the code happens to do. Keep a bound's tests
  at the bound and just past it.
- Tests are automated. Record what automation cannot reach as not verified.
- What was run goes on its issue, in a comment: the commit, the machine, the counts and what was
  left unverified. A document links to that comment and does not repeat it.
