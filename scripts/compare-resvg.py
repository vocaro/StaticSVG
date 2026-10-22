#!/usr/bin/env python3
"""Compare two Resvg.xcframeworks object by object, for a rebuild that maps its paths onto a
release's (doc/maintenance.md, "Reproducing a released binary").

Usage: python3 scripts/compare-resvg.py RELEASED.xcframework REBUILT.xcframework

Each slice is thinned to each architecture and unpacked, and every member is compared by its
SHA-256. Since the standard library has been built from source (0.1.1), `RUSTFLAGS` enters the
hash cargo puts in the name of its `compiler_builtins` unit, so a rebuild whose `RUSTFLAGS` remap
its paths names that member differently, and the archive's symbol table, which records names,
differs with it. Members are therefore matched by name with that hash left out, and the symbol
table is not compared. Exit status 0 when every member's content is identical.
"""
import hashlib
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def members(archive, arch, fat, scratch):
    """Each member's name without a crate hash, with its full name and SHA-256."""
    with tempfile.TemporaryDirectory(dir=scratch) as directory:
        directory = Path(directory)
        thin = directory / 'thin.a'
        if fat:
            subprocess.run(['lipo', str(archive), '-thin', arch, '-output', str(thin)], check=True,
                           capture_output=True)
        else:
            thin.write_bytes(archive.read_bytes())
        subprocess.run(['ar', '-x', thin.name], cwd=directory, check=True)
        found = {}
        for member in directory.iterdir():
            if member.name in (thin.name, '__.SYMDEF', '__.SYMDEF SORTED'):
                continue
            key = re.sub(r'^([A-Za-z0-9_]+)-[0-9a-f]{16}\.', r'\1.', member.name)
            found[key] = (member.name, hashlib.sha256(member.read_bytes()).hexdigest())
        return found


released, rebuilt = map(Path, sys.argv[1:3])
identical = True
with tempfile.TemporaryDirectory() as scratch:
    for archive in sorted(released.glob('*/libresvg.a')):
        other = rebuilt / archive.parent.name / 'libresvg.a'
        result = subprocess.run(['lipo', '-archs', str(archive)], capture_output=True, text=True, check=True)
        archs = result.stdout.split()
        for arch in archs:
            fat = len(archs) > 1
            ours, theirs = members(archive, arch, fat, scratch), members(other, arch, fat, scratch)
            same = {key: value[1] for key, value in ours.items()} == {key: value[1] for key, value in theirs.items()}
            renamed = [f'{ours[key][0]} -> {theirs[key][0]}' for key in ours
                       if key in theirs and ours[key][0] != theirs[key][0]]
            print(f'{archive.parent.name} {arch}: {len(ours)} members, '
                  f'{"content identical" if same else "CONTENT DIFFERS"}'
                  + (f'; renamed {", ".join(renamed)}' if renamed else ''))
            identical = identical and same
sys.exit(0 if identical else 1)
