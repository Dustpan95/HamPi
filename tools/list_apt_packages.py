#!/usr/bin/env python3
#
# Copyright 2024 - 2026, HamPi contributors.
# Licensed under the GNU General Public License v3.0. See LICENSE.
#
"""List every Debian package the playbooks install, so they can be checked
against a target release before a multi-hour build discovers a missing one.

Package names in this tree are frequently version-pinned (libyaml-cpp0.7,
libgfortran5, libgnuradio-osmosdr0.2). Those names change from one Debian
release to the next, and a name that no longer exists fails the task, and with
it the run. This lists them so availability can be confirmed up front.

Usage:
    tools/list_apt_packages.py                    # every package, one per line
    tools/list_apt_packages.py --with-source      # annotate with playbook name
    tools/list_apt_packages.py --suspicious       # only version-pinned names

Check them against a target release, on that machine:

    tools/list_apt_packages.py | xargs apt-cache policy 2>/dev/null \\
        | awk '/^[^ ]/ {pkg=$0} /Candidate: \\(none\\)/ {print pkg}'

or, without installing anything:

    tools/list_apt_packages.py > /tmp/pkgs.txt
    while read -r p; do
        apt-cache show "$p" >/dev/null 2>&1 || echo "MISSING: $p"
    done < /tmp/pkgs.txt
"""

import argparse
import pathlib
import re
import sys

# Matches a package module invocation and captures the block that follows.
PACKAGE_MODULE = re.compile(
    r'^\s*(?:ansible\.builtin\.)?(?:package|apt):\s*$', re.MULTILINE)

# A bare list entry: "- libfoo-dev"
LIST_ITEM = re.compile(r'^\s*-\s+([A-Za-z0-9][A-Za-z0-9+._-]*)\s*$')

# "name: libfoo-dev" (not a Jinja template)
INLINE_NAME = re.compile(r'^\s*name:\s*["\']?([A-Za-z0-9][A-Za-z0-9+._-]*)["\']?\s*$')

# A name carrying an embedded version, which is what breaks across releases.
VERSION_PINNED = re.compile(r'^(?:lib|python|gcc|g\+\+).*?[0-9]+(?:\.[0-9]+)*$')


def extract(path):
    """Yield package names referenced by package/apt tasks in one playbook."""
    text = path.read_text(encoding='utf-8', errors='replace')
    lines = text.splitlines()
    found = set()

    for index, line in enumerate(lines):
        if not PACKAGE_MODULE.match(line):
            continue

        # Scan forward for the name, and for a with_items/loop list feeding it.
        for candidate in lines[index + 1:index + 40]:
            stripped = candidate.strip()
            if stripped.startswith('#') or not stripped:
                continue
            # Stop at the next task.
            if re.match(r'^\s*-\s+name:\s', candidate):
                break

            inline = INLINE_NAME.match(candidate)
            if inline:
                found.add(inline.group(1))
                continue

            item = LIST_ITEM.match(candidate)
            if item:
                found.add(item.group(1))

    # "state: present" and friends look like inline names; drop the known keys.
    return found - {'present', 'latest', 'absent', 'yes', 'no', 'true', 'false',
                    'dist', 'build-dep'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--with-source', action='store_true',
                        help='annotate each package with the playbook using it')
    parser.add_argument('--suspicious', action='store_true',
                        help='only names carrying an embedded version number')
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent
    playbooks = sorted(root.glob('tasks/*.yml')) + sorted(root.glob('library/*.yml'))
    if not playbooks:
        print('error: no playbooks found; run from the repository', file=sys.stderr)
        return 1

    packages = {}
    for playbook in playbooks:
        for name in extract(playbook):
            packages.setdefault(name, []).append(playbook.name)

    for name in sorted(packages):
        if args.suspicious and not VERSION_PINNED.match(name):
            continue
        if args.with_source:
            print(f'{name}\t{",".join(sorted(packages[name]))}')
        else:
            print(name)

    return 0


if __name__ == '__main__':
    sys.exit(main())
