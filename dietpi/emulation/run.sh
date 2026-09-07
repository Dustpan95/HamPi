#!/bin/bash
# Disposable test container ONLY. Never source this script on a station.
set -euo pipefail
test "$(dpkg --print-architecture)" = arm64
test "$(id -u)" = 0
test -f /.dockerenv
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3 ansible-core xvfb xauth dbus-x11 xfce4 x11-utils
useradd --create-home --shell /bin/bash stationtest
cd /source/dietpi
python3 - <<'PY'
import json
from station import make_plan
catalog = json.load(open("profiles.json"))
plan = make_plan({"station_user": "stationtest", "mode": "desktop",
                  "profiles": list(catalog["profiles"])}, catalog)
with open("/tmp/emulation-plan.json", "w") as stream:
    json.dump(plan, stream)
PY
ansible-playbook -i localhost, emulation/install.yml -e @/tmp/emulation-plan.json
ansible-playbook -i localhost, emulation/install.yml -e @/tmp/emulation-plan.json | tee /tmp/second-pass.log
grep -Eq 'localhost[[:space:]]*:.*changed=0 .*unreachable=0 .*failed=0' /tmp/second-pass.log
python3 - <<'PY'
import json, subprocess
plan = json.load(open("/tmp/emulation-plan.json"))
record = json.load(open("/var/lib/hamradio-station/installation.json"))
assert record["hardware_validation"] == "pending"
assert record["platform"]["environment"] == "qemu-user-debian-container"
groups = subprocess.check_output(["id", "-nG", "stationtest"], text=True).split()
assert {"audio", "dialout"} <= set(groups)
for package in plan["station_packages"]:
    status = subprocess.check_output(["dpkg-query", "-W", "-f=${db:Status-Status} ${Architecture} ${Version}", package], text=True)
    assert status.startswith("installed arm64 ") or status.startswith("installed all "), (package, status)
    print(package, status)
print("PASS: all profile packages, station groups, records and second-pass idempotency")
PY
# Dummy rig only: no radio device is passed into this container.
rigctl -m 1 f
runuser -u stationtest -- xvfb-run -a -s '-screen 0 1280x800x24' \
  dbus-run-session -- python3 /source/dietpi/emulation/gui_smoke.py
