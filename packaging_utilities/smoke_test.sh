#!/bin/sh
#
# Copyright 2024 - 2026, Shackwright contributors.
#
# Licensed under the GNU General Public License v3.0. See LICENSE.
#
# Runs INSIDE an emulated Shackwright image and reports what it finds.
#
# This script is never installed into the image. emulate_image.sh puts it on
# a small second disk, and the kernel command line asks systemd to run it once
# the system is up. The image under test is not modified in any way, which
# matters: the thing we ship has to be the thing we tested.
#
# Everything it prints goes to the serial console, which the harness on the
# outside captures and greps. The markers SHACKWRIGHT-SMOKE-BEGIN and
# SHACKWRIGHT-SMOKE-END bracket the report, and the last line is a verdict.
#
# What a failure here means:
#
#   missing   A program the manifest says was installed is not on the disk.
#   unlinked  The program is there but the dynamic linker cannot satisfy it.
#             This is the failure a chroot build hides: a program links
#             against a library that was present while building and is not
#             present in the shipped image.
#
# A program exiting non-zero from --version is NOT a failure. Several of these
# are GUI programs and there is no display attached.

exec >/dev/console 2>&1

SMOKE_DIR=$(dirname "$0")
missing=0
unlinked=0
checked=0

# This runs INSIDE the boot transaction: systemd.run= generates a unit that
# default.target pulls in, so the boot cannot finish until this script exits.
#
# That rules out waiting here for the system to come up. The first version of
# this script called `systemctl is-system-running --wait`, which deadlocks --
# the unit waits for the boot, the boot waits for the unit, and the machine
# sits at sysinit.target until the harness gives up.
#
# Detaching the work into a transient unit with systemd-run appeared not to
# help: the machine powered off at 72 seconds, before the boot had finished.
# That turned out to be a separate fault and not this script's. The
# run-generator defaults SuccessAction to "exit", so the unit systemd.run=
# creates shuts the machine down as soon as the command returns. It is
# suppressed from the kernel command line in emulate_image.sh, and once it
# was, detaching stopped being necessary at all.
#
# So do not coordinate with the boot at all. The checks below need nothing
# from a running system -- they are file, linker and --version checks, all of
# which are true the moment the root filesystem is mounted. Print the report
# and exit. Whether the machine ever reaches a login prompt is established by
# a second boot that does not run this script.
#
# Failed units are not reported from in here for the same reason: this early,
# the list would be a snapshot of a boot still in progress. The harness reads
# them off the console instead, which covers the whole boot.

echo "SHACKWRIGHT-SMOKE-BEGIN"
echo "uname: $(uname -srm)"
echo "os: $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
echo "boot-time-at-check: $(cut -d' ' -f1 /proc/uptime)s"

echo "--- programs ---"
# programs.txt is written by the harness from the image manifest, so this
# tests what was actually installed rather than a list baked in here.
while read -r kind target; do
  [ -n "$kind" ] || continue
  case "$kind" in \#*) continue ;; esac

  if [ "$kind" = "req" ]; then
    path="$target"
  else
    path=$(command -v "$target" 2>/dev/null)
  fi

  if [ -z "$path" ] || [ ! -e "$path" ]; then
    if [ "$kind" = "req" ]; then
      echo "missing: ${target}"
      missing=$((missing + 1))
    else
      echo "absent-optional: ${target}"
    fi
    continue
  fi

  checked=$((checked + 1))

  # AppImages carry their own runtime and are not linked like a normal
  # program; checking their libraries says nothing useful.
  case "$path" in
    *.AppImage)
      echo "ok: ${path} (AppImage, not link-checked)"
      continue
      ;;
  esac

  # ldd runs the program to resolve it, so it needs a timeout like anything
  # else here -- and this script runs inside the boot transaction, where a
  # hang would stop the boot rather than just this check.
  lddout=$(timeout 30 ldd -r "$path" 2>/dev/null)
  lddrc=$?
  if [ "$lddrc" -ne 0 ]; then
    # Distinguish "checked and clean" from "could not check". Without this
    # the empty output of a failed ldd counts as zero unresolved symbols and
    # the program is reported ok without its libraries ever being verified.
    echo "unlinked: ${path} (ldd could not run, exit ${lddrc})"
    unlinked=$((unlinked + 1))
    continue
  fi
  notfound=$(printf '%s\n' "$lddout" | grep -c 'not found')
  if [ "${notfound:-0}" -gt 0 ]; then
    echo "unlinked: ${path} (${notfound} unresolved)"
    printf '%s\n' "$lddout" | grep 'not found' | sed 's/^/    /'
    unlinked=$((unlinked + 1))
    continue
  fi

  ver=$(timeout 20 "$path" --version 2>&1 | head -1)
  [ -n "$ver" ] || ver=$(timeout 20 "$path" -v 2>&1 | head -1)
  echo "ok: ${path} :: ${ver}"
done < "${SMOKE_DIR}/programs.txt"

echo "--- summary ---"
echo "checked: ${checked}  missing: ${missing}  unlinked: ${unlinked}"
if [ "$missing" -eq 0 ] && [ "$unlinked" -eq 0 ]; then
  echo "SMOKE-RESULT: PASS"
else
  echo "SMOKE-RESULT: FAIL"
fi
echo "SHACKWRIGHT-SMOKE-END"

# Deliberately no poweroff. This runs in the harness's first pass, whose boot
# goal is the run-generator's own target; the generator defaults SuccessAction
# to "exit", so returning from here is what powers the machine off. Calling
# poweroff as well would race with that. Reaching a login prompt is a separate
# boot, without this script in it at all.
exit 0
