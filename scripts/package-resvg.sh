#!/usr/bin/env bash
# Zip the renderer as a release asset, check the libraries in the zip against
# Resvg/checksums.json, and print the checksum Package.swift names (doc/maintenance.md).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
framework=${1:-"$root/Resvg/Resvg.xcframework"}
zip=${2:-"$root/Resvg/Resvg.xcframework.zip"}
python3 "$root/scripts/verify-resvg.py" "$framework" > /dev/null
rm -f "$zip"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$framework" "$zip"
check=$(mktemp -d)
trap 'rm -rf "$check"' EXIT
ditto -x -k "$zip" "$check"
python3 "$root/scripts/verify-resvg.py" "$check/Resvg.xcframework"
swift package --package-path "$root" compute-checksum "$zip"
