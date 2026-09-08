#!/usr/bin/env bash
#
# Copyright 2024 - 2026, Shackwright contributors.
# Licensed under the GNU General Public License v3.0. See LICENSE.
#
# Checks the emulation harness without emulating anything -- no QEMU, no
# kernel download, no image. What it guards is the part that can fail
# quietly: turning the build's manifest into the list of programs the smoke
# test looks for.
#
# That matters because an empty list is not an obvious failure. Every check
# would pass, the summary would say the boot was clean, and the reason would
# be that nothing was checked at all. This project has already shipped one
# generated file that was silently wrong, so the list generation gets a test.
#
# Usage: tests/test_emulation_harness.sh

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

EMULATE="packaging_utilities/emulate_image.sh"
SMOKE="packaging_utilities/smoke_test.sh"

pass=0
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ok()   { printf '  %-46s PASS\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  %-46s FAIL\n' "$1"; shift; printf '      %s\n' "$@"; fail=$((fail + 1)); }

echo "Shackwright emulation harness tests"
echo

# --- the scripts themselves -------------------------------------------------

for f in "$EMULATE" "$SMOKE"; do
  if [ -x "$f" ]; then ok "$f is executable"; else bad "$f is executable" "not executable"; fi
done

if bash -n "$EMULATE" 2>"$tmp/err"; then
  ok "$EMULATE parses"
else
  bad "$EMULATE parses" "$(cat "$tmp/err")"
fi

# smoke_test.sh runs under the image's /bin/sh, so it must be POSIX shell.
if sh -n "$SMOKE" 2>"$tmp/err"; then
  ok "$SMOKE parses as POSIX sh"
else
  bad "$SMOKE parses as POSIX sh" "$(cat "$tmp/err")"
fi

# It runs where bash may not exist, so it must not ask for one.
if head -1 "$SMOKE" | grep -q '^#!/bin/sh$'; then
  ok "$SMOKE does not require bash"
else
  bad "$SMOKE does not require bash" "shebang is $(head -1 "$SMOKE")"
fi

# --- the manifest -> programs.txt conversion --------------------------------

cat > "$tmp/manifest.txt" <<'FIXTURE'
Shackwright image contents
Build 99

== Base ==
  PRETTY_NAME="Debian GNU/Linux 13 (trixie)"

== Amateur radio packages from Debian ==
  chirp	1:20250502-1
  voacapl	0.7.6-3

== Built from source, not managed by apt ==
  /usr/bin/fldigi
  /usr/bin/flnet
  /usr/bin/hamrs-pro-2.52.0-linux-arm64.AppImage
  /usr/local/bin/rigctl
  (4 executables)

== Totals ==
  packages installed: 1908
FIXTURE

if out=$(SW_MANIFEST="$tmp/manifest.txt" SW_PROGRAMS_ONLY=1 "$EMULATE" ignored 2>"$tmp/err"); then
  reqs=$(printf '%s\n' "$out" | grep -c '^req ')
  if [ "$reqs" -eq 4 ]; then
    ok "manifest yields its 4 source-built programs"
  else
    bad "manifest yields its 4 source-built programs" "got ${reqs}" "$out"
  fi

  # The paths, not just the count -- a parse that shifted a field would still
  # produce four lines.
  missing=""
  for want in /usr/bin/fldigi /usr/bin/flnet /usr/local/bin/rigctl \
              /usr/bin/hamrs-pro-2.52.0-linux-arm64.AppImage; do
    printf '%s\n' "$out" | grep -qx "req ${want}" || missing="${missing} ${want}"
  done
  if [ -z "$missing" ]; then
    ok "each source-built path appears verbatim"
  else
    bad "each source-built path appears verbatim" "missing:${missing}"
  fi

  # The "(4 executables)" tally and the packaged-package section must not be
  # mistaken for programs.
  if printf '%s\n' "$out" | grep -q 'executables)'; then
    bad "the manifest's own tally is not treated as a program" "tally leaked in"
  else
    ok "the manifest's own tally is not treated as a program"
  fi
  if printf '%s\n' "$out" | grep -qx 'req chirp'; then
    bad "packaged programs are not marked required" "chirp marked req"
  else
    ok "packaged programs are not marked required"
  fi

  if printf '%s\n' "$out" | grep -qx 'opt chirp'; then
    ok "packaged programs are listed as optional"
  else
    bad "packaged programs are listed as optional" "$out"
  fi
else
  bad "programs list generates from a manifest" "$(cat "$tmp/err")"
fi

# A manifest that parses to nothing must be an error, not an empty list that
# makes the smoke test vacuously pass.
cat > "$tmp/empty.txt" <<'FIXTURE'
Shackwright image contents

== Built from source, not managed by apt ==
  (0 executables)

== Totals ==
  packages installed: 12
FIXTURE

if SW_MANIFEST="$tmp/empty.txt" SW_PROGRAMS_ONLY=1 "$EMULATE" ignored >/dev/null 2>&1; then
  bad "an empty manifest section is refused" "it was accepted"
else
  ok "an empty manifest section is refused"
fi

# With no manifest at all the harness still checks the packaged programs.
if out=$(SW_MANIFEST="$tmp/does-not-exist" SW_PROGRAMS_ONLY=1 "$EMULATE" ignored 2>/dev/null); then
  if [ "$(printf '%s\n' "$out" | grep -c '^opt ')" -gt 0 ]; then
    ok "no manifest still yields the packaged programs"
  else
    bad "no manifest still yields the packaged programs" "$out"
  fi
else
  bad "no manifest still yields the packaged programs" "exited non-zero"
fi

# --- the ELF classifier -----------------------------------------------------

# smoke_test.sh decides pass or fail partly on what elf_kind() says, and the
# first version of that decision was wrong in a way that mattered: it called
# ldd's non-zero exit "unlinked" for a Python script, a static binary and a
# wrong-architecture binary alike. The first reported a healthy program as
# broken; the third was a genuine defect described in useless words.
#
# The headers below are synthesised rather than taken from real binaries, so
# this runs anywhere. Bytes 0-3 are the ELF magic, byte 4 the class, and
# bytes 18-19 the machine, little endian.
# Synthesised ELF headers, so this runs anywhere without needing real
# binaries of three architectures. Written as explicit byte escapes rather
# than built from arguments: e_ident is 16 bytes (0-15), e_type is 16-17 and
# e_machine is 18-19, and a fixture that is two bytes short puts the machine
# where the type belongs and quietly tests nothing.
#                    magic     cls ord ver  <-------- pad 9 -------->  type   machine
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\267\000' > "$tmp/aarch64.elf"
printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\002\000\050\000' > "$tmp/arm32.elf"
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\076\000' > "$tmp/amd64.elf"
printf '#!/usr/bin/python3\nprint(1)\n' > "$tmp/script.py"

# Pull the function out of the guest script and run it against a pretend
# aarch64 host, which is what it will actually be running on.
awk '/^elf_kind\(\) \{/,/^\}/' "$SMOKE" > "$tmp/elf_kind.sh"
if [ -s "$tmp/elf_kind.sh" ]; then
  ok "elf_kind() can be extracted from $SMOKE"

  classify() (
    # shellcheck disable=SC1090
    . "$tmp/elf_kind.sh"
    uname() { echo aarch64; }
    elf_kind "$1"
  )

  for case_ in "aarch64.elf:elf-native" "arm32.elf:elf-foreign" \
               "amd64.elf:elf-foreign" "script.py:notelf"; do
    f=${case_%%:*}; want=${case_#*:}
    got=$(classify "$tmp/$f")
    if [ "$got" = "$want" ]; then
      ok "on aarch64, ${f} is ${want}"
    else
      bad "on aarch64, ${f} is ${want}" "got ${got}"
    fi
  done
else
  bad "elf_kind() can be extracted from $SMOKE" "function not found"
fi

# A wrong-architecture binary must fail the run, not be filed under ok.
if grep -q 'wrongarch=$((wrongarch + 1))' "$SMOKE" &&
   grep -q '\[ "\$wrongarch" -eq 0 \]' "$SMOKE"; then
  ok "a wrong-architecture program fails the smoke test"
else
  bad "a wrong-architecture program fails the smoke test" \
      "wrongarch is counted but not part of the verdict"
fi

# --- the guest script's contract with the harness ---------------------------

for marker in SHACKWRIGHT-SMOKE-BEGIN SHACKWRIGHT-SMOKE-END "SMOKE-RESULT: PASS" \
              "SMOKE-RESULT: FAIL"; do
  if grep -q "$marker" "$SMOKE" && grep -q "$marker" "$EMULATE"; then
    ok "both sides agree on '${marker}'"
  elif grep -q "$marker" "$SMOKE"; then
    # FAIL is emitted by the guest and matched loosely by the harness.
    case "$marker" in
      "SMOKE-RESULT: FAIL") ok "guest can report '${marker}'" ;;
      *) bad "both sides agree on '${marker}'" "harness does not look for it" ;;
    esac
  else
    bad "both sides agree on '${marker}'" "guest never prints it"
  fi
done

echo
echo "  passed: ${pass}  failed: ${fail}"
[ "$fail" -eq 0 ] || exit 1
