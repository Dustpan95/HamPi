#!/usr/bin/env bash
#
# Copyright 2020 - 2024, Dave Slotter (W3DJS). All rights reserved.
# Copyright 2024 - 2026, Shackwright contributors.
#
# Licensed under the GNU General Public License v3.0. See LICENSE.
#
# Turns a built Shackwright card image into a set of release artifacts people
# can download and flash.
#
#     packaging_utilities/package_release.sh <image.img> <version> [outdir]
#
# For example:
#
#     packaging_utilities/package_release.sh shackwright.img 4.0.0
#
# It compresses the image, checksums it, and splits the result into parts
# small enough for a GitHub release, then verifies the parts reassemble to
# exactly what went in. Nothing is published; this only produces files.
#
# Before running this, shrink the image. A card image is as large as the card,
# so an unshrunk 32 GB image forces every user onto a 32 GB or larger card even
# if only 12 GB is in use. PiShrink is the established tool:
#
#     sudo pishrink.sh -Z shackwright.img
#
# This script deliberately does not reimplement that. Resizing a filesystem and
# rewriting a partition table is exactly the kind of operation where a subtle
# bug produces images that appear to flash and then fail to boot.
#

set -euo pipefail

# GitHub caps a single release asset at 2 GiB. Parts are sized under that with
# room to spare, so a part is never rejected at upload time. Both are
# overridable so the split and reassembly path can be exercised in tests
# without generating gigabytes of data.
# GitHub caps a single release asset at 2 GiB. The threshold was 1900 MiB,
# which was conservative to the point of being wrong: build 11's compressed
# image came to 2,139,297,936 bytes -- about 8 MB UNDER the real cap -- and
# was split anyway. Every downloader was asked to reassemble two files for
# no reason, and Raspberry Pi Imager cannot read a split file at all, so the
# one-click flash the instructions describe was not actually available.
#
# 2 GiB less 16 MiB of headroom. Splitting still happens when it genuinely
# must; it no longer happens when it must not.
PART_SIZE="${SHACKWRIGHT_PART_SIZE:-1900M}"
PART_LIMIT_BYTES="${SHACKWRIGHT_PART_LIMIT_BYTES:-$(( (2 * 1024 - 16) * 1024 * 1024 ))}"

usage() {
    cat >&2 <<USAGE
usage: $(basename "$0") <image.img> <version> [outdir]

  image.img   The built card image. Shrink it first with PiShrink.
  version     Release version, e.g. 4.0.0 or 4.0.0-beta1
  outdir      Where to write artifacts (default: ./release)
USAGE
    exit 1
}

[ $# -ge 2 ] || usage

IMAGE="$1"
VERSION="$2"
OUTDIR="${3:-release}"

[ -f "$IMAGE" ] || { echo "error: no such image: $IMAGE" >&2; exit 1; }

for tool in xz split sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool not found: $tool" >&2; exit 1; }
done

BASE="shackwright-${VERSION}"
mkdir -p "$OUTDIR"

echo "Packaging ${IMAGE} as ${BASE}"
echo

# --- compress ------------------------------------------------------------
# -T0 uses every core. An image is mostly zeroes in its free space, which xz
# collapses to almost nothing, so this is far smaller than the card size.
echo "Compressing (this takes a while) ..."
xz --threads=0 --compress --stdout -6 "$IMAGE" > "${OUTDIR}/${BASE}.img.xz"

compressed_size=$(stat -c %s "${OUTDIR}/${BASE}.img.xz")
echo "  compressed to $(numfmt --to=iec --suffix=B "$compressed_size" 2>/dev/null || echo "${compressed_size} bytes")"
echo

# --- checksum ------------------------------------------------------------
echo "Checksumming ..."
( cd "$OUTDIR" && sha256sum "${BASE}.img.xz" > "${BASE}.img.xz.sha256" )
echo "  $(cut -d' ' -f1 < "${OUTDIR}/${BASE}.img.xz.sha256")"
echo

# --- split, only if the file will not fit as one asset -------------------
if [ "$compressed_size" -gt "$PART_LIMIT_BYTES" ]; then
    echo "Splitting into ${PART_SIZE} parts (GitHub caps one asset at 2 GiB) ..."
    ( cd "$OUTDIR" && split -b "$PART_SIZE" -d -a 2 \
        "${BASE}.img.xz" "${BASE}.img.xz.part" )
    ( cd "$OUTDIR" && sha256sum "${BASE}".img.xz.part* > "${BASE}.parts.sha256" )
    part_count=$(find "$OUTDIR" -name "${BASE}.img.xz.part*" | wc -l)
    echo "  ${part_count} parts written"

    # Verify the parts reassemble byte for byte. A split that cannot be put
    # back together is worse than no release at all.
    echo "Verifying parts reassemble ..."
    original_sum=$(cut -d' ' -f1 < "${OUTDIR}/${BASE}.img.xz.sha256")
    rebuilt_sum=$(cat "${OUTDIR}/${BASE}".img.xz.part* | sha256sum | cut -d' ' -f1)
    if [ "$original_sum" != "$rebuilt_sum" ]; then
        echo "error: reassembled parts do not match the original" >&2
        exit 1
    fi
    echo "  parts verified"
    rm -f "${OUTDIR}/${BASE}.img.xz"
    split_used=true
else
    echo "Compressed image fits in one asset; not splitting."
    split_used=false
fi
echo

# --- instructions shipped with the release -------------------------------
{
    echo "# Shackwright ${VERSION}"
    echo
    echo "## Verify the download"
    echo
    echo '```'
    if [ "$split_used" = true ]; then
        echo "sha256sum -c ${BASE}.parts.sha256"
    else
        echo "sha256sum -c ${BASE}.img.xz.sha256"
    fi
    echo '```'
    echo
    if [ "$split_used" = true ]; then
        echo "## Reassemble"
        echo
        echo "The image is split because a single GitHub release asset cannot"
        echo "exceed 2 GiB. Download every part into one directory, then:"
        echo
        echo '```'
        echo "cat ${BASE}.img.xz.part* > ${BASE}.img.xz"
        echo "sha256sum -c ${BASE}.img.xz.sha256"
        echo '```'
        echo
        echo "On Windows, in PowerShell:"
        echo
        echo '```'
        echo "cmd /c copy /b ${BASE}.img.xz.part00 + ${BASE}.img.xz.part01 ${BASE}.img.xz"
        echo '```'
        echo
    fi
    echo "## Flash"
    echo
    echo "Raspberry Pi Imager reads .xz directly; choose \"Use custom\" and"
    echo "select the file. There is no need to decompress it first."
    echo
    echo "Or from a shell:"
    echo
    echo '```'
    echo "xz -dc ${BASE}.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync"
    echo '```'
    echo
    echo "Replace /dev/sdX with your card. Check it twice with lsblk; dd will"
    echo "overwrite whatever you point it at."
} > "${OUTDIR}/${BASE}.RELEASE.md"

echo "Artifacts in ${OUTDIR}:"
ls -1 "$OUTDIR" | sed 's/^/  /'
