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
# ---------------------------------------------------------------------------
# Why two boots
# ---------------------------------------------------------------------------
#
# systemd.run= cannot be combined with booting to a login prompt. Its
# generator does not merely add a unit; it redirects default.target at a
# target of its own. From run-generator.c:
#
#     /* And now redirect default.target to our new target */
#     return generator_add_symlink(arg_dest, SPECIAL_DEFAULT_TARGET, ...)
#
# A boot carrying systemd.run= therefore never goes to multi-user or
# graphical at all. It reaches a target containing only the command, and then
# -- because the generator defaults SuccessAction to "exit" -- powers off.
# Every attempt to have one boot do both jobs failed in a different way: the
# system deadlocked at sysinit, or powered off at 68 seconds having never
# offered a login prompt.
#
# One observation is unexplained. On the Lite image the generator took effect
# as the source says it should; on the desktop image the same command line
# produced no kernel-command-line.service at all and an ordinary boot to a
# login prompt. Neither image pins default.target in /etc, so the obvious
# explanation is wrong and no other has been established. Naming the boot
# goal explicitly in pass one sidesteps it rather than relying on it.
#
#   Pass 1  systemd.run= plus systemd.unit=kernel-command-line.target. Runs
#           the report, powers itself off. Short: it never boots the system.
#   Pass 2  no systemd.run at all. An ordinary boot, to a login prompt.
#
# Three things have to be told to stand down in both:
#
#   boot-firmware.mount   /boot/firmware is vfat and this kernel has VFAT as a
#                         module it cannot load. Unmasked, the mount fails,
#                         local-fs.target fails with it, and the system drops
#                         into emergency mode. Measured, not guessed.
#   *-wait-online         Nothing here needs the network, and waiting for it
#                         costs minutes of emulated time.
#   display-manager       There is no GPU under virt. Masking it leaves
#                         graphical.target reachable, since that target only
#                         wants a display manager rather than requiring one.
#
# ---------------------------------------------------------------------------
# What a pass here does and does not mean
# ---------------------------------------------------------------------------
#
# It proves: the partition table and filesystem are sound, the userland is
# consistent enough to reach a login prompt, and the installed programs are
# present and their libraries resolve.
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
# --max-time as well as --retry: retry covers a connection that fails, not one
# that is accepted and then stalls, and a hung mirror should not hang the job.
CURL=(curl -fsSL --retry 3 --connect-timeout 30 --max-time 600)

deb="${OUT}/kernel.deb"
if "${CURL[@]}" -o "$deb" "${POOL}/${PINNED_DEB}"; then
  got=$(sha256sum "$deb" | cut -d' ' -f1)
  if [ "$got" != "$PINNED_SHA" ]; then
    echo "kernel checksum mismatch for ${PINNED_DEB}" >&2
    echo "  expected ${PINNED_SHA}" >&2
    echo "  got      ${got}" >&2
    exit 1
  fi
  echo "using pinned ${PINNED_DEB}"
else
  newest=$("${CURL[@]}" "${POOL}/" \
    | grep -oE 'linux-image-6\.[0-9.]+\+deb13-cloud-arm64-unsigned_[^"]*\.deb' \
    | sort -V | tail -1)
  [ -n "$newest" ] || { echo "no cloud-arm64 kernel found in the pool" >&2; exit 1; }
  echo "NOTE: pinned kernel ${PINNED_DEB} is gone from the pool."
  echo "NOTE: falling back to ${newest} -- update the pin in this script."
  "${CURL[@]}" -o "$deb" "${POOL}/${newest}" || exit 1
fi

rm -rf "${OUT}/kroot"
mkdir -p "${OUT}/kroot"
# Only /boot is wanted. Unpacking the whole package would drop about 250 MB
# of modules for a kernel whose drivers we deliberately need built in, and
# the runners this has to fit on have well under 30 GB free with a grown
# image and a compressed release already on the disk.
if ! dpkg-deb --fsys-tarfile "$deb" | tar -x -C "${OUT}/kroot" ./boot 2>/dev/null; then
  dpkg-deb -x "$deb" "${OUT}/kroot" || exit 1
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
# The suffix the kernel expects is two hex digits, and parted counts in
# decimal. They agree up to 9 and stop agreeing after it.
ROOT=$(printf 'PARTUUID=%s-%02x' "$ptuuid" "$rootnum")
echo "root: ${ROOT}"

# --------------------------------------------------------------------------
say "Building the smoke-test disk"
# --------------------------------------------------------------------------
# The test script travels on its own disk. Nothing is written into the image:
# what gets shipped has to be what got tested.
here=$(cd "$(dirname "$0")" && pwd)
rm -rf "${OUT}/smoke"
mkdir -p "${OUT}/smoke"
cp "${here}/smoke_test.sh" "${OUT}/smoke/smoke.sh" || exit 1
chmod +x "${OUT}/smoke/smoke.sh"

# The exit status matters. write_programs_list refuses a manifest it cannot
# parse, and without this check the redirection would leave an empty file, the
# in-image loop would run zero times, and the run would report PASS having
# checked nothing at all.
if ! write_programs_list "$MANIFEST" > "${OUT}/smoke/programs.txt"; then
  echo "refusing to boot with an empty program list" >&2
  exit 1
fi
nprog=$(grep -c '^req \|^opt ' "${OUT}/smoke/programs.txt")
if [ "${nprog:-0}" -lt 1 ]; then
  echo "the generated program list is empty; nothing would be checked" >&2
  exit 1
fi
echo "programs to check: ${nprog}"

rm -f "${OUT}/smoke.img"
mkfs.ext4 -q -F -L SWSMOKE -d "${OUT}/smoke" "${OUT}/smoke.img" 32M \
  || { echo "could not build the smoke-test disk" >&2; exit 1; }

# --------------------------------------------------------------------------
# One boot. Returns 0 if the machine stopped because it was finished, 1 if it
# had to be killed at the deadline.
#
#   boot_vm <tag> <extra-append> <done-regex|"">
#
# An empty done-regex means "wait for the machine to power itself off", which
# is what pass one does.
# --------------------------------------------------------------------------
boot_vm() {
  local tag=$1 extra=$2 donere=$3
  local log="${OUT}/${tag}-console.log"
  : > "$log"

  local append="root=${ROOT} rootfstype=ext4 rw rootwait console=ttyAMA0,115200 \
loglevel=7 fsck.mode=skip systemd.show_status=1 \
systemd.mask=boot-firmware.mount \
systemd.mask=display-manager.service \
systemd.mask=systemd-networkd-wait-online.service \
systemd.mask=NetworkManager-wait-online.service ${extra}"

  echo "append: ${append}"
  local started
  started=$(date +%s)

  # -snapshot so every write lands in a throwaway overlay. The image on disk
  # is byte-for-byte what it was before this ran, and is what gets published.
  qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a72 \
    -smp "$SMP" \
    -m "$MEM" \
    -kernel "$KERNEL" \
    -append "$append" \
    -drive "file=${IMG},format=raw,if=none,id=hd0,cache=unsafe" \
    -device nvme,drive=hd0,serial=shackwright \
    -drive "file=${OUT}/smoke.img,format=raw,if=none,id=hd1" \
    -device nvme,drive=hd1,serial=smoke \
    -netdev user,id=n0 \
    -device virtio-net-pci,netdev=n0 \
    -serial "file:${log}" \
    -snapshot \
    -display none \
    -no-reboot > "${OUT}/${tag}-qemu.stdout" 2>&1 &
  local qpid=$!

  local deadline=$(( started + TIMEOUT ))
  local killed=0
  while kill -0 "$qpid" 2>/dev/null; do
    if [ -n "$donere" ] && grep -qaE "$donere" "$log" 2>/dev/null; then
      sleep 3                       # let the last console writes land
      kill "$qpid" 2>/dev/null
      break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      killed=1
      echo "gave up after ${TIMEOUT}s"
      kill "$qpid" 2>/dev/null
      break
    fi
    sleep 5
  done

  # SIGTERM is a request. Give it ten seconds, then insist -- otherwise a QEMU
  # wedged on host I/O would leave the wait below blocking with no deadline at
  # all, and the job would hang rather than fail.
  local waited=0
  while kill -0 "$qpid" 2>/dev/null && [ "$waited" -lt 10 ]; do
    sleep 1
    waited=$(( waited + 1 ))
  done
  kill -9 "$qpid" 2>/dev/null
  wait "$qpid" 2>/dev/null

  echo "${tag}: stopped after $(( $(date +%s) - started ))s"
  return "$killed"
}

# --------------------------------------------------------------------------
say "Pass 1 of 2: running the programs"
# --------------------------------------------------------------------------
# systemd.unit= names the generator's target explicitly rather than trusting
# it to have captured default.target. The generator's SuccessAction default
# of "exit" is left alone here: it is exactly what is wanted, and it is why
# this pass is short.
run='/bin/sh -c '"'"'mkdir -p /run/sw && mount -o ro -L SWSMOKE /run/sw && /run/sw/smoke.sh'"'"''
boot_vm programs \
  "systemd.unit=kernel-command-line.target systemd.run=\"${run}\"" \
  'SHACKWRIGHT-SMOKE-END'

# --------------------------------------------------------------------------
say "Pass 2 of 2: booting to a login prompt"
# --------------------------------------------------------------------------
boot_vm login "" 'login:|Reached target getty'

# --------------------------------------------------------------------------
say "Result"
# --------------------------------------------------------------------------
# Strip the terminal control sequences systemd writes, so grep sees text.
for tag in programs login; do
  sed -e 's/\x1b\[[0-9;:?]*[A-Za-z]//g' -e 's/\r//g' \
    "${OUT}/${tag}-console.log" > "${OUT}/${tag}-clean.log"
done
cat "${OUT}/programs-clean.log" "${OUT}/login-clean.log" > "${OUT}/console-clean.log"
prog="${OUT}/programs-clean.log"
login="${OUT}/login-clean.log"

fail=0
check() {                             # check <label> <file> <regex>
  if grep -qaE "$3" "$2"; then
    printf '  yes  %s\n' "$1"
  else
    printf '  NO   %s\n' "$1"
    fail=1
  fi
}
check "kernel started"          "$prog"  'Linux version'
check "root filesystem mounted" "$prog"  'Mounted root'
check "handed off to init"      "$prog"  'Run /sbin/init as init process'
check "systemd came up"         "$prog"  'systemd\[1\]: Detected architecture'
check "smoke test ran"          "$prog"  'SHACKWRIGHT-SMOKE-BEGIN'
check "smoke test finished"     "$prog"  'SHACKWRIGHT-SMOKE-END'
check "offered a login prompt"  "$login" 'login:|Reached target getty'

for f in "$prog" "$login"; do
  if grep -qa 'Kernel panic' "$f"; then
    echo "  NO   no kernel panic"; fail=1
  fi
  if grep -qa 'emergency mode' "$f"; then
    echo "  NO   did not fall into emergency mode"; fail=1
  fi
done

echo
echo "--- units that failed during the ordinary boot ---"
# Read off the console rather than asked for from inside the image. Some of
# these are expected: there is no Raspberry Pi hardware here for the
# Pi-specific units to talk to.
if grep -qa '\[FAILED\]' "$login"; then
  grep -a '\[FAILED\]' "$login" | sed 's/^/  /' | sort -u
else
  echo "  none"
fi

echo
echo "--- what the image reported about itself ---"
sed -n '/SHACKWRIGHT-SMOKE-BEGIN/,/SHACKWRIGHT-SMOKE-END/p' "$prog" || true

# Free the kernel package and its unpacked copy. Whatever runs after this --
# compressing a multi-gigabyte image, normally -- needs the disk more than
# these do. The console logs stay; they are the point of the exercise.
rm -rf "${OUT}/kroot" "$deb" "${OUT}/smoke.img"

echo
if [ "$fail" -eq 0 ] && grep -qa 'SMOKE-RESULT: PASS' "$prog"; then
  echo "EMULATION: PASS"
  exit 0
fi
echo "EMULATION: FAIL  ($(grep -a 'SMOKE-RESULT:' "$prog" | tail -1 || echo 'no verdict reported'))"
echo "Full console: ${OUT}/console-clean.log"
exit 1
