#!/usr/bin/env bash
#
# Copyright 2024 - 2026, Shackwright contributors.
#
# Licensed under the GNU General Public License v3.0. See LICENSE.
#
# Boots a built Shackwright image under QEMU and reports what happens.
#
#     packaging_utilities/emulate_image.sh <image.img> [outdir]
#
# ---------------------------------------------------------------------------
# Why this is shaped the way it is
# ---------------------------------------------------------------------------
#
# The obvious approach -- "-M raspi3b with the image's own kernel8.img" -- does
# not work, and the reason is worth writing down so nobody spends another day
# on it. QEMU's raspi3b does not model the Raspberry Pi firmware. The kernel
# boots, systemd starts, and about nine seconds later the machine resets. That
# happens identically on the STOCK Raspberry Pi OS image, so it is not a defect
# in anything this project builds. raspi4b is no better and needs QEMU 9.0,
# which the runners do not have.
#
# So: boot the image's userland under QEMU's "virt" machine instead, with a
# generic kernel. That needs a kernel with drivers for virt's hardware, and
# the Raspberry Pi kernel has none -- grep the rpi defconfigs for VIRTIO and
# you get nothing at all.
#
# Debian's cloud arm64 kernel is the answer, but not over virtio: it builds
# VIRTIO_BLK as a module, which would mean shipping an initramfs to load it.
# It builds BLK_DEV_NVME, EXT4_FS, MSDOS_PARTITION, PCI_HOST_GENERIC and
# SERIAL_AMBA_PL011 in. Attaching the image as an NVMe namespace therefore
# needs no initramfs and no modules from the image at all.
#
# Three things have to be told to stand down:
#
#   boot-firmware.mount   /boot/firmware is vfat and this kernel has VFAT as a
#                         module it cannot load. Unmasked, the mount fails,
#                         local-fs.target fails with it, and the system drops
#                         into emergency mode. Measured, not guessed.
#   *-wait-online         Nothing here needs the network, and waiting for it
#                         costs minutes of emulated time.
#   display-manager       The desktop image defaults to graphical.target and
#                         there is no GPU under virt. Masking the display
#                         manager leaves graphical.target reachable -- it
#                         only Wants a display manager, it does not Require
#                         one.
#
# What NOT to do here: set systemd.unit=multi-user.target to dodge the
# desktop. It works, and it silently disables the smoke test. systemd.run=
# is implemented by a generator that hangs its unit off default.target, so
# overriding which unit boots means the generated unit is never pulled in.
# The system comes up, reaches a login prompt, and reports nothing at all.
# Measured, after it happened here.
#
# ---------------------------------------------------------------------------
# What a pass here does and does not mean
# ---------------------------------------------------------------------------
#
# It proves: the partition table and filesystem are sound, the userland is
# consistent enough for systemd to reach multi-user, and the installed
# programs are present and their libraries resolve.
#
# It does not prove: that the Raspberry Pi firmware and kernel will boot this
# card, or anything about the GPU, audio, GPIO, USB or a radio on a serial
# port. Those need a Raspberry Pi. This runs a generic kernel on emulated
# hardware; it tests what we built, not what it will be built on.
set -uo pipefail

# mkfs.ext4, blkid and parted live in /usr/sbin, which is not on a normal
# user's PATH. None of them need root to work on a plain file.
PATH="${PATH}:/usr/sbin:/sbin"

IMG=${1:?usage: emulate_image.sh <image.img> [outdir]}
OUT=${2:-qemu-emulation}

# A kernel that has aged out of the pool is a broken test, so the pin is a
# preference rather than a requirement: if it is gone, take the newest one and
# say loudly which was used.
PINNED_DEB='linux-image-6.12.96+deb13-cloud-arm64-unsigned_6.12.96-1_arm64.deb'
PINNED_SHA='3e8e53f584fd5315dc47b551a81dadfe051117fe1f15cb581110afa767bacf76'
POOL='https://deb.debian.org/debian/pool/main/l/linux'

TIMEOUT=${SW_TIMEOUT:-2400}
MEM=${SW_MEM:-2048}
SMP=${SW_SMP:-2}
MANIFEST=${SW_MANIFEST:-image-manifest.txt}


say() { printf '%s\n' "== $*"; }

# Turns the build's manifest into the list smoke_test.sh walks. Kept in a
# function so tests/test_emulation_harness.sh can drive the real code rather
# than a copy of it -- a generated list that quietly comes out empty is a
# failure mode this project has already been bitten by once.
write_programs_list() {
  local manifest=$1
  local reqs=""

  if [ -f "$manifest" ]; then
    # Everything the build recorded as source-built must be present. Those are
    # the ones a chroot build can get wrong.
    reqs=$(awk '/^== Built from source/{f=1;next} /^==/{f=0} f && /^  \//{print "req " $1}' \
      "$manifest")
    if [ -z "$reqs" ]; then
      echo "manifest ${manifest} exists but lists no source-built programs;" >&2
      echo "either the build installed none or the manifest format changed." >&2
      return 1
    fi
  fi

  echo "# Generated by emulate_image.sh -- what to look for inside the image."
  if [ -n "$reqs" ]; then
    printf '%s\n' "$reqs"
  else
    echo "# no manifest at ${manifest}; checking the packaged programs only"
  fi

  # Packaged programs. Optional because which ones are present depends on
  # which playbooks the build was asked to run.
  local c
  for c in chirp qdmr dmrconf quisk voacapl SoapySDRUtil pat hamrs \
           rigctl rotctl fldigi flarq flnet flrig flamp flmsg; do
    echo "opt ${c}"
  done
}

# Used by the test suite to exercise the list generation on its own, without
# an image, a kernel download, or a boot. Deliberately ahead of the checks
# below: those are about booting, and this path does not boot anything.
if [ "${SW_PROGRAMS_ONLY:-0}" = "1" ]; then
  write_programs_list "$MANIFEST"
  exit $?
fi

[ -f "$IMG" ] || { echo "no such image: $IMG" >&2; exit 1; }
mkdir -p "$OUT"

# --------------------------------------------------------------------------
say "Fetching a generic arm64 kernel"
# --------------------------------------------------------------------------
deb="${OUT}/kernel.deb"
if curl -fsSL --retry 3 -o "$deb" "${POOL}/${PINNED_DEB}"; then
  got=$(sha256sum "$deb" | cut -d' ' -f1)
  if [ "$got" != "$PINNED_SHA" ]; then
    echo "kernel checksum mismatch for ${PINNED_DEB}" >&2
    echo "  expected ${PINNED_SHA}" >&2
    echo "  got      ${got}" >&2
    exit 1
  fi
  echo "using pinned ${PINNED_DEB}"
else
  newest=$(curl -fsSL "${POOL}/" \
    | grep -oE 'linux-image-6\.[0-9.]+\+deb13-cloud-arm64-unsigned_[^"]*\.deb' \
    | sort -V | tail -1)
  [ -n "$newest" ] || { echo "no cloud-arm64 kernel found in the pool" >&2; exit 1; }
  echo "NOTE: pinned kernel ${PINNED_DEB} is gone from the pool."
  echo "NOTE: falling back to ${newest} -- update the pin in this script."
  curl -fsSL --retry 3 -o "$deb" "${POOL}/${newest}" || exit 1
fi

rm -rf "${OUT}/kroot"
mkdir -p "${OUT}/kroot"
# Only /boot is wanted. Unpacking the whole package would drop about 250 MB
# of modules for a kernel whose drivers we deliberately need built in, and
# the runners this has to fit on have well under 30 GB free with a grown
# image and a compressed release already on the disk.
if ! dpkg-deb --fsys-tarfile "$deb" | tar -x -C "${OUT}/kroot" ./boot 2>/dev/null; then
  dpkg-deb -x "$deb" "${OUT}/kroot"
fi
KERNEL=$(find "${OUT}/kroot/boot" -name 'vmlinuz-*' | head -1)
[ -n "$KERNEL" ] || { echo "no vmlinuz in the kernel package" >&2; exit 1; }
echo "kernel: $(basename "$KERNEL")"

# --------------------------------------------------------------------------
say "Reading the image's partition table"
# --------------------------------------------------------------------------
# Name the root by PARTUUID rather than by device. With two NVMe controllers
# attached, controller numbering is not guaranteed to follow the order the
# devices were given on the command line, and naming /dev/nvme0n1p2 hangs the
# boot at "Waiting for root device" whenever the race goes the other way.
ptuuid=$(blkid -o value -s PTUUID "$IMG" 2>/dev/null || true)
if [ -z "$ptuuid" ]; then
  # Bytes 440..443 of the MBR are the disk signature, little-endian.
  b=$(dd if="$IMG" bs=1 skip=440 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
  ptuuid="${b:6:2}${b:4:2}${b:2:2}${b:0:2}"
fi
[ -n "$ptuuid" ] || { echo "could not read the disk identifier" >&2; exit 1; }

rootnum=$(parted -sm "$IMG" unit s print 2>/dev/null \
  | awk -F: '/ext4/ {print $1}' | tail -1)
rootnum=${rootnum:-2}
ROOT="PARTUUID=${ptuuid}-0${rootnum}"
echo "root: ${ROOT}"

# --------------------------------------------------------------------------
say "Building the smoke-test disk"
# --------------------------------------------------------------------------
# The test script travels on its own disk. Nothing is written into the image:
# what gets shipped has to be what got tested.
here=$(cd "$(dirname "$0")" && pwd)
rm -rf "${OUT}/smoke"
mkdir -p "${OUT}/smoke"
cp "${here}/smoke_test.sh" "${OUT}/smoke/smoke.sh"
chmod +x "${OUT}/smoke/smoke.sh"

write_programs_list "$MANIFEST" > "${OUT}/smoke/programs.txt"
echo "programs to check: $(grep -c '^req\|^opt' "${OUT}/smoke/programs.txt")"

rm -f "${OUT}/smoke.img"
mkfs.ext4 -q -F -L SWSMOKE -d "${OUT}/smoke" "${OUT}/smoke.img" 32M

# --------------------------------------------------------------------------
say "Booting"
# --------------------------------------------------------------------------
run='/bin/sh -c '"'"'mkdir -p /run/sw && mount -o ro -L SWSMOKE /run/sw && /run/sw/smoke.sh'"'"''
APPEND="root=${ROOT} rootfstype=ext4 rw rootwait console=ttyAMA0,115200 \
loglevel=7 fsck.mode=skip systemd.show_status=1 \
systemd.mask=boot-firmware.mount \
systemd.mask=display-manager.service \
systemd.mask=systemd-networkd-wait-online.service \
systemd.mask=NetworkManager-wait-online.service \
systemd.run=\"${run}\""

: > "${OUT}/console.log"
echo "append: ${APPEND}"
started=$(date +%s)

# -snapshot so every write lands in a throwaway overlay. The image on disk is
# byte-for-byte what it was before this ran, and is what gets published.
qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -smp "$SMP" \
  -m "$MEM" \
  -kernel "$KERNEL" \
  -append "$APPEND" \
  -drive "file=${IMG},format=raw,if=none,id=hd0,cache=unsafe" \
  -device nvme,drive=hd0,serial=shackwright \
  -drive "file=${OUT}/smoke.img,format=raw,if=none,id=hd1" \
  -device nvme,drive=hd1,serial=smoke \
  -netdev user,id=n0 \
  -device virtio-net-pci,netdev=n0 \
  -serial "file:${OUT}/console.log" \
  -snapshot \
  -display none \
  -no-reboot > "${OUT}/qemu.stdout" 2>&1 &
qpid=$!

# Shut the machine down from out here rather than from inside it. The guest
# cannot power itself off at the right moment: the smoke test runs inside the
# boot transaction, so a poweroff there would stop the boot before it reached
# a login prompt -- and reaching one is half of what this is establishing.
#
# Done means the report has been printed AND a getty is offering a login.
# Note that "Reached target multi-user.target" is NOT a marker to wait for:
# systemd never prints it. getty.target and the prompt itself are what appear.
deadline=$(( started + TIMEOUT ))
timedout=0
while kill -0 "$qpid" 2>/dev/null; do
  if grep -qa 'SHACKWRIGHT-SMOKE-END' "${OUT}/console.log" 2>/dev/null &&
     grep -qaE 'login:|Reached target getty' "${OUT}/console.log" 2>/dev/null; then
    sleep 3                    # let the last console writes land
    kill "$qpid" 2>/dev/null
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    timedout=1
    echo "gave up after ${TIMEOUT}s"
    kill "$qpid" 2>/dev/null
    break
  fi
  sleep 5
done
wait "$qpid" 2>/dev/null
elapsed=$(( $(date +%s) - started ))
echo "qemu stopped after ${elapsed}s (timed out: ${timedout})"

# Strip the terminal control sequences systemd writes, so grep sees text.
sed -e 's/\x1b\[[0-9;:?]*[A-Za-z]//g' -e 's/\r//g' \
  "${OUT}/console.log" > "${OUT}/console-clean.log"

# --------------------------------------------------------------------------
say "Result"
# --------------------------------------------------------------------------
clean="${OUT}/console-clean.log"
echo "console: $(stat -c%s "${OUT}/console.log") bytes"

fail=0
check() {
  if grep -qa "$2" "$clean"; then
    printf '  yes  %s\n' "$1"
  else
    printf '  NO   %s\n' "$1"
    fail=1
  fi
}
check "kernel started"                 'Linux version'
check "root filesystem mounted"        'Mounted root'
check "handed off to init"             'Run /sbin/init as init process'
check "systemd came up"                'systemd\[1\]: Detected architecture'
check "offered a login prompt"         'login:'
check "smoke test ran"                 'SHACKWRIGHT-SMOKE-BEGIN'
check "smoke test finished"            'SHACKWRIGHT-SMOKE-END'

if grep -qa 'Kernel panic' "$clean"; then
  echo "  NO   no kernel panic"
  fail=1
fi
if grep -qa 'emergency mode' "$clean"; then
  echo "  NO   did not fall into emergency mode"
  fail=1
fi

echo
echo "--- units that failed during the boot ---"
# Read off the console rather than asked for from inside the image: by the
# time the smoke test runs, the boot is not finished, so anything it could
# report would be a partial list. Some of these are expected -- there is no
# Raspberry Pi hardware here for the Pi-specific units to talk to.
if grep -qa '\[FAILED\]' "$clean"; then
  grep -a '\[FAILED\]' "$clean" | sed 's/^/  /' | sort -u
else
  echo "  none"
fi

echo
echo "--- what the image reported about itself ---"
sed -n '/SHACKWRIGHT-SMOKE-BEGIN/,/SHACKWRIGHT-SMOKE-END/p' "$clean" || true

verdict=$(grep -a 'SMOKE-RESULT:' "$clean" | tail -1)
echo
# Free the kernel package and its unpacked copy. Whatever runs after this --
# compressing a multi-gigabyte image, normally -- needs the disk more than
# these do. The console logs stay; they are the point of the exercise.
rm -rf "${OUT}/kroot" "$deb" "${OUT}/smoke.img"

if [ "$fail" -eq 0 ] && grep -qa 'SMOKE-RESULT: PASS' "$clean"; then
  echo "EMULATION: PASS  (booted to a login prompt in ${elapsed}s of wall clock)"
  exit 0
fi
echo "EMULATION: FAIL  (${verdict:-no verdict reported})"
echo "Full console: ${OUT}/console-clean.log"
exit 1
