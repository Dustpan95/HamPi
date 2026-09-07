---
name: Bug report
about: Report something that fails during or after a build
title: ''
labels: bug
assignees: ''

---

**What went wrong**
A clear description of the failure. If a task failed during the playbook run,
paste the failing task name and Ansible's error.

**Which application**
Which playbook or application under `tasks/` is affected, if you know.
For example `install_hamlib.yml`, or "WSJT-X".

**To reproduce**
1. Target OS and version, freshly installed or upgraded from what
2. Command you ran, e.g. `./run_shackwright --limit shack.local`
3. Where it failed

**Expected behavior**
What you expected to happen instead.

**Target system**
 - Hardware: [Raspberry Pi 5 / Pi 4 / Pi 400 / Pi 500 / Pi Zero 2 W / x86_64 PC / Inovato Quadra]
 - OS and release: [e.g. Raspberry Pi OS Trixie 64-bit, Debian 13, Ubuntu 24.04]
 - 32-bit or 64-bit userland: output of `getconf LONG_BIT`
 - Shackwright commit or release: output of `git rev-parse --short HEAD`

**Control machine**
 - `ansible --version` (first line)
 - OS you ran the playbook from

**Log**
Attach the relevant part of the log from `ansible-output/`. The failing task
plus the fifty lines before it is usually enough. Please do not paste the
whole file inline — attach it if it is long.

**Additional context**
Anything else worth knowing.
