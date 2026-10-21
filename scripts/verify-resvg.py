#!/usr/bin/env python3
"""Check an XCFramework's libraries against Resvg/checksums.json, and that it has the slices a
release needs. Usage: python3 scripts/verify-resvg.py [path/to/Resvg.xcframework]"""
import hashlib
import json
from pathlib import Path
import plistlib
import sys

root = Path(__file__).resolve().parents[1]
framework = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Resvg/Resvg.xcframework"
expected = json.loads((root / "Resvg/checksums.json").read_text())
actual = {f"Resvg.xcframework/{path.parent.name}/libresvg.a": hashlib.sha256(path.read_bytes()).hexdigest()
          for path in sorted(framework.glob("*/libresvg.a"))}
slices = {(item["LibraryIdentifier"], tuple(sorted(item["SupportedArchitectures"])))
          for item in plistlib.loads((framework / "Info.plist").read_bytes())["AvailableLibraries"]}
required = {("ios-arm64", ("arm64",)), ("ios-arm64_x86_64-simulator", ("arm64", "x86_64")),
            ("macos-arm64_x86_64", ("arm64", "x86_64"))}
problems = []
if actual != expected:
    for key in sorted(set(actual) | set(expected)):
        if actual.get(key) != expected.get(key):
            problems.append(f"{key}: expected {expected.get(key)}, found {actual.get(key)}")
if slices != required:
    problems.append(f"slices: expected {sorted(required)}, found {sorted(slices)}")
headers = {path.read_bytes() for path in framework.glob("*/Headers/resvg.h")}
if len(headers) != 1 or b"resvg_render_checked" not in next(iter(headers), b""):
    problems.append("headers: the three slices must share one patched resvg.h")
if problems:
    print("\n".join(problems), file=sys.stderr)
    raise SystemExit(1)
for key, digest in sorted(actual.items()):
    print(f"{digest}  {key}")
