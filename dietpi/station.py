#!/usr/bin/env python3
"""Plan or install the DietPi station foundation. Planning is fully offline."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent


def make_plan(config, catalog):
    if not isinstance(config, dict):
        raise ValueError("Station configuration must be a JSON object")
    allowed = {"station_user", "mode", "profiles", "package_versions"}
    if set(config) - allowed:
        raise ValueError("Unknown station settings: " + ", ".join(sorted(set(config) - allowed)))
    user = config.get("station_user")
    if not isinstance(user, str) or not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", user) or user == "root":
        raise ValueError("station_user must name an existing non-root Linux account")
    mode = config.get("mode", "desktop")
    if mode not in ("desktop", "services"):
        raise ValueError("mode must be desktop or services; remote session setup is still pending")
    profiles = config.get("profiles", ["digital"])
    if not isinstance(profiles, list) or any(not isinstance(p, str) for p in profiles):
        raise ValueError("profiles must be a list of profile names")
    selected = sorted(set(profiles))
    packages = set(catalog["base"])
    for name in selected:
        if name not in catalog["profiles"]:
            raise ValueError(f"Unknown profile: {name}")
        profile = catalog["profiles"][name]
        if mode == "services" and profile["requires_desktop"]:
            raise ValueError(f"Profile {name} requires desktop mode")
        packages.update(profile["packages"])
    versions = config.get("package_versions", {})
    if not isinstance(versions, dict) or set(versions) - packages:
        raise ValueError("package_versions must map selected package names to exact versions")
    for name, version in versions.items():
        if not isinstance(version, str) or not re.fullmatch(r"[0-9][A-Za-z0-9.+:~\-]*", version):
            raise ValueError(f"Invalid exact package version for {name}")
    return {
        "station_user": user,
        "station_mode": mode,
        "station_profiles": selected,
        "station_packages": sorted(packages),
        "station_package_specs": [p + ("=" + versions[p] if p in versions else "") for p in sorted(packages)],
        "station_desktop_software_id": 25 if mode == "desktop" else None,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("plan", "check", "install"))
    parser.add_argument("--config", type=Path, default=ROOT / "station.example.json")
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--ask-become-pass", action="store_true")
    args = parser.parse_args(argv)
    try:
        plan = make_plan(json.loads(args.config.read_text()), json.loads((ROOT / "profiles.json").read_text()))
    except (ValueError, OSError) as exc:
        parser.error(str(exc))
    if args.action == "plan":
        print(json.dumps(plan, indent=2))
        return 0
    if args.inventory is None or not args.inventory.is_file():
        parser.error("check/install requires --inventory pointing to an explicit inventory file")
    executable = shutil.which("ansible-playbook")
    if not executable:
        parser.error("ansible-playbook is missing; install dietpi/requirements.txt in a controller virtual environment")
    # TemporaryDirectory uses a private directory; command arguments never pass through a shell.
    with tempfile.TemporaryDirectory(prefix="station-plan-") as directory:
        variables = Path(directory) / "plan.json"
        variables.write_text(json.dumps(plan))
        command = [executable, "-i", str(args.inventory.resolve()), str(ROOT / "install.yml"),
                   "--extra-vars", "@" + str(variables)]
        if args.action == "check":
            command += ["--check", "--diff"]
        if args.ask_become_pass:
            command += ["--ask-become-pass"]
        env = dict(os.environ, ANSIBLE_CONFIG=str(ROOT / "ansible.cfg"))
        try:
            return subprocess.run(command, cwd=ROOT, env=env, check=False).returncode
        except KeyboardInterrupt:
            return 130


if __name__ == "__main__":
    sys.exit(main())
