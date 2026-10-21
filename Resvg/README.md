# Resvg

The renderer library's records, kept beside the framework that `scripts/build-resvg.sh` writes
here as `Resvg.xcframework` (not in Git; a release distributes it as its
`Resvg.xcframework.zip` asset):

- `checksums.json`: the SHA-256 of each library slice, which `scripts/verify-resvg.py` checks.
- `dependencies.json`: the locked Rust crates linked into the library, with their versions,
  declared licenses and repositories.
- `Licenses/`: their complete license, copyright and notice texts, and Rust's standard-library
  notices, which an application shipping the library must retain.

What the library is and how it is patched is in [the bundled renderer](../doc/renderer.md); how
it is rebuilt, verified and released is in [maintenance](../doc/maintenance.md).
