# HamPi

HamPi builds a complete amateur radio software environment on a Raspberry Pi,
an x86_64 Linux PC (as **HamPC**), or an Inovato Quadra (as **HamIQ**). It is an
Ansible playbook, not an image: it takes a stock operating system install and
adds a hundred-odd ham radio applications, their dependencies, desktop menu
entries and configuration.

Originally created by **Dave Slotter, W3DJS**. This repository continues the
project, which had its last upstream release in April 2024.

---

## Status

**Modernization in progress. Not yet verified on hardware.**

Upstream targeted Raspberry Pi OS Bookworm and stopped there. Raspberry Pi OS
moved to Debian 13 "Trixie" in October 2025, and a great deal of this tree
assumed the older release. Work so far has been to make the playbooks correct
for current hardware and current Raspberry Pi OS, and to put automated checks
in place so it does not silently rot again.

What has been done and verified automatically:

| Area | State |
|------|-------|
| Platform detection (OS, CPU, board) | Rewritten, unit tested |
| Debian 13 Trixie / Debian 14 Forky | Supported |
| Ubuntu 24.04 Noble / 26.04 Resolute | Supported |
| Raspberry Pi 5 / 500 detection | Added |
| Playbook syntax, all 130 playbooks | Passing in CI |
| ansible-lint (production profile) | Clean |
| Hamlib build on Trixie | Fixed (needs a hardware run) |

What has **not** been done: a full build on a real Raspberry Pi. Every change so
far is verified by syntax checks, linting and unit tests, which catch a large
class of defects but cannot tell you whether a package still compiles. The
first end-to-end run on real hardware is the next milestone, and it will find
things. See [Known issues](#known-issues).

---

## Requirements

* A target machine running **Raspberry Pi OS Trixie (64-bit)**, Debian 13, or
  Ubuntu 24.04 / 26.04. Raspberry Pi 4, 5, 400 or 500 recommended.
* A **32 GB or larger** SD card or SSD. The full install no longer fits on 16 GB.
* SSH access to the target from the machine you run the playbook on.
* `ansible-core` 2.16 or newer on the machine running the playbook.

Raspberry Pi OS Trixie still ships a 32-bit edition, but 64-bit is strongly
recommended. On 32-bit ARM several libraries changed ABI in the move to 64-bit
`time_t` without changing their names, so a binary built against Bookworm
libraries can link against Trixie libraries that look compatible and are not.

---

## Quick start

Run the playbook from a PC or a second Pi, against the machine you are building.

```bash
git clone https://github.com/Dustpan95/HamPi.git
cd HamPi

# Control-node tooling. Debian and Ubuntu mark their system Python as
# externally managed, so use a virtual environment.
python3 -m venv ~/.venv/hampi
~/.venv/hampi/bin/pip install -r requirements.txt
. ~/.venv/hampi/bin/activate

# Set up key-based SSH to the target, then describe it to Ansible.
ssh-copy-id <user>@hampi.local
cp hosts.example hosts
$EDITOR hosts

./run_HamPi_playbook
```

`hosts` is git-ignored, so your inventory survives updates and your credentials
are never committed. The runner prompts for the target's sudo password rather
than storing it.

Expect the full build to take **several hours** — most of it is compiling from
source. Output is logged to `ansible-output/`.

Any extra arguments are passed straight through to `ansible-playbook`:

```bash
./run_HamPi_playbook --limit hampi.local     # one host
./run_HamPi_playbook --check                 # dry run
```

---

## Known issues

These are recorded rather than fixed because confirming them needs a real
build. Help with any of them is welcome.

**34 applications are disabled.** `tasks/main.yml` has 34 commented-out imports,
most marked "broken under Bookworm" by upstream — including SDRAngel, GQRX,
CubicSDR, FreeDV, dump1090, TQSL, most of the SoapySDR driver modules, and the
DRAWS hat support. Each needs to be tried against Trixie and either repaired or
retired. They all still pass a syntax check, so re-enabling one is a one-line
change.

**Eleven enabled playbooks install dependencies only for old releases.** They
branch on Buster, Bullseye or Jammy and match nothing on Trixie, so the task
skips, Ansible reports success, and the application is built without its
dependencies:

`install_bluedv` · `install_gridtracker` · `install_logging_apps` ·
`install_miscellaneous_apps` · `install_antenna_modeling_apps` ·
`install_cmake` · `install_cygnusRFI` · `install_digital_apps` ·
`install_jtdx` · `install_tapr_wspr` · `install_morsecode_apps`

**Version-pinned package names.** Around 30 dependencies name a specific shared
library soname (`libgfortran4`, `libgnuradio-osmosdr0.2`, `libqcustomplot2.0`).
Those names change with each Debian release. `tools/list_apt_packages.py
--suspicious` lists them; run it against a Trixie target to find which no longer
resolve.

**A branch that can never run.** `install_jtdx.yml` guards a dependency install
with `is_rpi and is_bullseye and not is_arm`. A Raspberry Pi is always ARM, so
that task has never executed.

**Python packages install into the system interpreter.** Sixteen applications
are installed with pip's `--break-system-packages` override, centralized in
`default/main.yml`. The cleaner fix is a dedicated virtual environment with the
desktop launchers pointing at it; that changes where every one of those programs
lives, so it needs hardware testing first.

---

## Development

CI runs on every push and pull request. To run the same checks locally:

```bash
yamllint .                                              # style and real defects
ansible-lint                                            # Ansible correctness
ansible-playbook -i 'localhost,' --syntax-check tasks/main.yml
./tests/run_tests.sh                                    # platform detection
```

`tests/` exercises platform detection against recorded `/proc/device-tree/model`
fixtures, so board and OS detection can be verified on any machine without a Pi
attached. If you change `library/set_facts.yml`, add a case there.

A note on layout, which predates current Ansible conventions: files in `tasks/`
are complete playbooks with their own `hosts:` key, not task lists, and
`library/` holds playbooks rather than custom modules. `.ansible-lint` maps the
real file kinds so the linter does not apply the wrong schema. Renaming those
directories would break every existing bookmark, wiki page and documented
command, so the layout stays.

---

## Applications

Well over a hundred, across logging, digital modes, SDR, APRS, satellite work,
antenna modeling, Morse training and licence study. The full annotated list
lives in the [upstream wiki](https://github.com/dslotter/HamPi/wiki), which
remains an accurate description of what the playbooks install.

The broad categories:

* **Rig control and general** — Hamlib, grig, CHIRP, Gpredict, VOACAP, HamClock
* **FLDigi suite (W1HKJ)** — fldigi, flrig, flmsg, flamp, flnet, fllog, and the rest
* **Digital modes** — WSJT-X, JTDX, JS8Call, MSHV, GridTracker, QSSTV, fldigi
* **SDR** — SoapySDR and its driver modules, CubicSDR, GQRX, SDRAngel, quisk, OpenWebRX
* **APRS and packet** — Xastir, YAAC, DireWolf, aprx, AX.25 tooling, LinPac
* **Logging** — CQRlog, KLog, PyQSO, TrustedQSL, tlf, xlog
* **WinLink** — Pat, ARDOP, PMON
* **Morse** — aldo, cwcp, qrq, ebook2cw, morse2ascii
* **Antennas** — nec2c, xnecview, yagiuda, gsmc, antennavis, Fl_MoxGen

---

## Contributing

Issues and pull requests are welcome, particularly from anyone able to test on
real hardware. The most useful contributions right now:

1. **Run a full build on Trixie and report what breaks.** Attach the log from
   `ansible-output/`.
2. **Repair a disabled application.** Pick one of the 34, get it building on
   Trixie, re-enable its import in `tasks/main.yml`.
3. **Confirm package availability** on Trixie with `tools/list_apt_packages.py`.

Please keep CI green: run the four commands under [Development](#development)
before opening a pull request.

---

## Credits

HamPi was created and maintained for six years by **Dave Slotter, W3DJS**, with
contributions from many others — see [CONTRIBUTORS.md](CONTRIBUTORS.md). This
repository carries that work forward; the architecture, the application
selection and the overwhelming majority of the code are his and theirs.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).

Copyright 2020 - 2024, Dave Slotter (W3DJS).
Copyright 2024 - 2026, HamPi contributors.
