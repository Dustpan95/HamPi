#!/usr/bin/env python3
"""Read-only target checks. Does not open the radio or alter system settings."""

import argparse
import json
from pathlib import Path
import pwd
import re
import shlex
import subprocess


def read_text(path):
    try:
        return Path(path).read_text().replace("\x00", "").strip()
    except OSError:
        return ""


def parse_os_release(text):
    result = {}
    for line in text.splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        try:
            parts = shlex.split(value, comments=True)
        except ValueError:
            continue
        if len(parts) == 1:
            result[key] = parts[0]
    return result


def problems(facts):
    errors = []
    if not facts["dietpi_version_present"]:
        errors.append("DietPi version marker /boot/dietpi/.version is missing")
    if facts["install_stage"] != "2":
        errors.append("Finish DietPi's initial setup before installing station software")
    if facts["os_id"] != "debian" or facts["os_version"] != "13" or facts["os_codename"] != "trixie":
        errors.append("This foundation targets DietPi based on Debian 13 Trixie")
    if facts["package_architecture"] != "arm64":
        errors.append("The operating system must use native arm64 packages")
    if not re.fullmatch(r"Raspberry Pi (?:4|5) Model B(?: Rev [0-9.]+)?", facts["board_model"]):
        errors.append("Only Raspberry Pi 4 Model B and Pi 5 Model B are initial hardware targets")
    if not facts["station_user_exists"] or facts["station_user_uid"] == 0:
        errors.append("station_user must already exist and must not have UID 0")
    return errors


def inspect(user):
    os_release = parse_os_release(read_text("/etc/os-release"))
    try:
        architecture = subprocess.run(["dpkg", "--print-architecture"], capture_output=True,
                                      text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        architecture = "unknown"
    try:
        account = pwd.getpwnam(user)
    except KeyError:
        account = None
    version = read_text("/boot/dietpi/.version")
    fields = re.findall(r"^G_DIETPI_VERSION_(?:CORE|SUB|RC)=([0-9]+)$", version, re.M)
    return {
        "os_id": os_release.get("ID", ""),
        "os_version": os_release.get("VERSION_ID", ""),
        "os_codename": os_release.get("VERSION_CODENAME", ""),
        "package_architecture": architecture,
        "board_model": read_text("/proc/device-tree/model"),
        "dietpi_version_present": bool(version),
        "dietpi_version_fields": fields,
        "install_stage": read_text("/boot/dietpi/.install_stage"),
        "station_user_exists": account is not None,
        "station_user_uid": account.pw_uid if account else None,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", required=True)
    args = parser.parse_args()
    result = inspect(args.user)
    result["errors"] = problems(result)
    print(json.dumps(result, indent=2))
    raise SystemExit(2 if result["errors"] else 0)
