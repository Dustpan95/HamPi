#!/usr/bin/env bash
#
# Copyright 2024 - 2026, Shackwright contributors.
# Licensed under the GNU General Public License v3.0. See LICENSE.
#
# Exercises packaging_utilities/package_release.sh end to end on a synthetic
# image, including the split-and-reassemble path.
#
# A release that cannot be put back together by the person downloading it is
# worse than no release, and the failure would only surface after someone had
# downloaded several gigabytes. So the round trip is checked here: split the
# archive, reassemble it exactly as the generated instructions tell a user to,
# decompress, and compare against the original bytes.
#
# Usage: tests/run_tests.sh, or tests/test_packaging.sh directly.
#

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

SCRIPT="$(pwd)/packaging_utilities/package_release.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

check() {
    local name="$1" result="$2"
    printf '  %-44s ' "$name"
    if [ "$result" = "0" ]; then echo "PASS"; pass=$((pass + 1))
    else echo "FAIL"; fail=$((fail + 1)); fi
}

echo "Shackwright packaging tests"
echo

# Incompressible data, so the compressed size is predictable and the split
# path can be triggered with a small threshold.
head -c 3000000 /dev/urandom > "${WORK}/source.img"

# --- single-asset path ---------------------------------------------------
out=$("$SCRIPT" "${WORK}/source.img" 0.0.0-test "${WORK}/single" 2>&1)
check "single-asset run succeeds" $?
[ -f "${WORK}/single/shackwright-0.0.0-test.img.xz" ]
check "unsplit archive produced" $?
[ -f "${WORK}/single/shackwright-0.0.0-test.img.xz.sha256" ]
check "checksum produced" $?
[ -f "${WORK}/single/shackwright-0.0.0-test.RELEASE.md" ]
check "release instructions produced" $?
echo "$out" | grep -q "not splitting"
check "correctly declines to split a small image" $?

# --- split path ----------------------------------------------------------
SHACKWRIGHT_PART_SIZE=1M SHACKWRIGHT_PART_LIMIT_BYTES=$((1024 * 1024)) \
    "$SCRIPT" "${WORK}/source.img" 0.0.0-test "${WORK}/split" >/dev/null 2>&1
check "split run succeeds" $?

part_count=$(find "${WORK}/split" -name '*.img.xz.part*' | wc -l)
[ "$part_count" -gt 1 ]
check "produced more than one part" $?

# The unsplit archive must be gone: shipping both wastes the uploader's
# bandwidth and confuses the person downloading.
[ ! -f "${WORK}/split/shackwright-0.0.0-test.img.xz" ]
check "unsplit archive removed after splitting" $?

# Every part must be under the GitHub asset ceiling.
oversize=$(find "${WORK}/split" -name '*.img.xz.part*' -size +2048M | wc -l)
[ "$oversize" -eq 0 ]
check "no part exceeds the 2 GiB asset limit" $?

# The reassembly a user actually performs.
( cd "${WORK}/split" && cat shackwright-0.0.0-test.img.xz.part* > rebuilt.img.xz )
check "parts concatenate" $?

expected=$(cut -d' ' -f1 < "${WORK}/split/shackwright-0.0.0-test.img.xz.sha256")
actual=$(sha256sum "${WORK}/split/rebuilt.img.xz" | cut -d' ' -f1)
[ "$expected" = "$actual" ]
check "reassembled archive matches published checksum" $?

xz -dc "${WORK}/split/rebuilt.img.xz" > "${WORK}/split/rebuilt.img" 2>/dev/null
check "reassembled archive decompresses" $?

cmp -s "${WORK}/split/rebuilt.img" "${WORK}/source.img"
check "decompressed image is byte-identical to source" $?

# --- argument handling ---------------------------------------------------
"$SCRIPT" >/dev/null 2>&1
[ $? -ne 0 ]
check "rejects missing arguments" $?

"$SCRIPT" "${WORK}/does-not-exist.img" 0.0.0 >/dev/null 2>&1
[ $? -ne 0 ]
check "rejects a nonexistent image" $?

echo
echo "  passed: ${pass}  failed: ${fail}"
[ "$fail" -eq 0 ] || exit 1
