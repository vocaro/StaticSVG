#!/usr/bin/env python3
"""Check an XCFramework's libraries against Resvg/checksums.json, that it has the slices a release
needs, and that no slice imports an API Apple requires an app to give a reason for.

Usage: python3 scripts/verify-resvg.py [path/to/Resvg.xcframework]

An app declares in its privacy manifest each use of an API that reads the system boot time, file
timestamps, disk space, the active keyboards or user defaults
(https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
The library's link-time optimization leaves in each archive only what the C API's functions
reach, so what an archive imports is all an app linking it could call (EPUBLib#685). Each member
carries LLVM bitcode, which Xcode's `nm` may not read; it reads the machine code alone, and every
slice must be read.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys

BOOT_TIME, FILE_TIMESTAMP, DISK_SPACE = 'system boot time', 'file timestamp', 'disk space'
FUNCTIONS = {
    'mach_absolute_time': BOOT_TIME,
    **dict.fromkeys(('stat', 'fstat', 'fstatat', 'lstat'), FILE_TIMESTAMP),
    **dict.fromkeys(('getattrlist', 'getattrlistbulk', 'fgetattrlist', 'getattrlistat'),
                    f'{FILE_TIMESTAMP} or {DISK_SPACE}'),
    **dict.fromkeys(('statfs', 'fstatfs', 'statvfs', 'fstatvfs'), DISK_SPACE),
}
CONSTANTS = {
    **dict.fromkeys(('NSFileCreationDate', 'NSFileModificationDate', 'NSURLCreationDateKey',
                     'NSURLContentModificationDateKey'), FILE_TIMESTAMP),
    **dict.fromkeys(('NSFileSystemFreeSize', 'NSFileSystemSize', 'NSURLVolumeAvailableCapacityKey',
                     'NSURLVolumeAvailableCapacityForImportantUsageKey',
                     'NSURLVolumeAvailableCapacityForOpportunisticUsageKey',
                     'NSURLVolumeTotalCapacityKey'), DISK_SPACE),
}
SELECTORS = {'systemUptime': BOOT_TIME, 'activeInputModes': 'active keyboards',
             'fileCreationDate': FILE_TIMESTAMP, 'fileModificationDate': FILE_TIMESTAMP}
CLASSES = {'NSUserDefaults': 'user defaults'}


def category(symbol):
    """The required-reason category of an undefined symbol, or None."""
    name = symbol.removeprefix('_')
    if name.startswith('objc_msgSend$'):
        return SELECTORS.get(name.removeprefix('objc_msgSend$'))
    if name.startswith('OBJC_CLASS_$_'):
        return CLASSES.get(name.removeprefix('OBJC_CLASS_$_'))
    # `stat$INODE64` and other variants are the function they are named for.
    return FUNCTIONS.get(name.split('$')[0]) or CONSTANTS.get(name)


def required_reason_findings(archive):
    """What one slice imports from the list, or why it could not be read."""
    result = subprocess.run(['xcrun', 'nm', '--no-llvm-bc', '-arch', 'all', '-u', '-A', str(archive)],
                            capture_output=True, text=True)
    lines, error = result.stdout.splitlines(), result.stderr.strip()
    if result.returncode or error or not lines:
        return [f'{archive.parent.name}: unread: {error.splitlines()[0] if error else "no symbols"}']
    found = []
    for line in lines:
        member, _, symbol = line.rpartition(': ')
        if kind := category(symbol):
            found.append(f'{archive.parent.name}: {member.rpartition("/")[2]}: {symbol} ({kind})')
    return found


root = Path(__file__).resolve().parents[1]
framework = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Resvg/Resvg.xcframework"
expected = json.loads((root / "Resvg/checksums.json").read_text())
archives = sorted(framework.glob("*/libresvg.a"))
actual = {f"Resvg.xcframework/{path.parent.name}/libresvg.a": hashlib.sha256(path.read_bytes()).hexdigest()
          for path in archives}
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
for archive in archives:
    problems += [f"required-reason API: {finding}" for finding in required_reason_findings(archive)]
if problems:
    print("\n".join(problems), file=sys.stderr)
    raise SystemExit(1)
for key, digest in sorted(actual.items()):
    print(f"{digest}  {key}")
print(f"No slice imports an API Apple requires a reason for ({len(archives)} read).")
