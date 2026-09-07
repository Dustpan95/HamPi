#!/usr/bin/env bash
#
# Copyright 2024 - 2026, HamPi contributors.
# Licensed under the GNU General Public License v3.0. See LICENSE.
#
# Exercises library/set_facts.yml against recorded /proc/device-tree/model
# fixtures, so the platform detection that every task file branches on can be
# verified on any machine -- no Raspberry Pi required.
#
# Usage: tests/run_tests.sh
#

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# slurp resolves relative paths against the remote home directory, not the
# playbook directory, so fixtures must be addressed absolutely.
FIXTURES="$(pwd)/tests/fixtures"
FACTS="library/set_facts.yml"
ASSERTIONS="tests/test_platform_detection.yml"

pass=0
fail=0

# run_case <name> <fixture> <expect_model> <expect_rpi> <expect_pi5> <expect_pi4> <expect_pi_zero>
run_case() {
  local name="$1" fixture="$2" model="$3" rpi="$4" pi5="$5" pi4="$6" pizero="$7"

  printf '  %-28s ' "$name"
  # Extra vars are passed as JSON: the key=value form splits on whitespace,
  # which would truncate a model string like "Raspberry Pi 5 Model B Rev 1.0".
  local extra
  extra=$(printf '{"pi_model_path":"%s","expect_model":"%s","expect_rpi":%s,"expect_pi5":%s,"expect_pi4":%s,"expect_pi_zero":%s}' \
    "$fixture" "$model" "$rpi" "$pi5" "$pi4" "$pizero")

  if output=$(ansible-playbook -i 'localhost,' -c local \
        -e "$extra" \
        "$FACTS" "$ASSERTIONS" 2>&1); then
    echo "PASS"
    pass=$((pass + 1))
  else
    echo "FAIL"
    echo "$output" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
}

echo "HamPi platform detection tests"
echo

run_case "Raspberry Pi 5"       "$FIXTURES/model_pi5"        "Raspberry Pi 5 Model B Rev 1.0" true  true  false false
run_case "Raspberry Pi 500"     "$FIXTURES/model_pi500"      "Raspberry Pi 500 Rev 1.0"       true  true  false false
run_case "Raspberry Pi 4"       "$FIXTURES/model_pi4"        "Raspberry Pi 4 Model B Rev 1.4" true  false true  false
run_case "Raspberry Pi 400"     "$FIXTURES/model_pi400"      "Raspberry Pi 400 Rev 1.0"       true  false true  false
run_case "Raspberry Pi Zero 2W" "$FIXTURES/model_pizero2w"   "Raspberry Pi Zero 2 W Rev 1.0"  true  false false true
# A host with no device tree must fall through to the PC branch, not abort.
run_case "non-Pi host"          "/nonexistent/device-tree"   ""                               false false false false

echo
echo "  passed: ${pass}  failed: ${fail}"
[ "$fail" -eq 0 ] || exit 1
