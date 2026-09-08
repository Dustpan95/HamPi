# Shackwright

Shackwright builds a complete amateur radio station from a stock Linux install.
It is an Ansible playbook, not a disk image: point it at a Raspberry Pi, an
x86_64 Linux PC, or an Inovato Quadra, and it installs a hundred-odd ham radio
applications with their dependencies, desktop menu entries and configuration —
with a heavy lean toward the digital modes.

A *wright* is a maker: a shipwright builds ships, a millwright builds mills.
Shackwright builds shacks. It is not the station; it is what puts the station
together.

Shackwright continues **HamPi**, created by **Dave Slotter, W3DJS**, whose last
release was April 2024. The playbooks are overwhelmingly his work. See
[Credits](#credits).

---

---

## Status

**Modernization in progress. Booted under emulation, not yet on hardware.**

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

What has **not** been done: a run on a real Raspberry Pi. Changes are verified
by syntax checks, linting and unit tests, by an image build that compiles the
source-built programs on a native arm64 runner, and by booting that image under
emulation. That catches a large class of defects. It cannot tell you whether
the Pi's own firmware will boot the card, or whether a radio on a serial port
will key up. The first end-to-end run on real hardware is the next milestone,
and it will find things. See [Known issues](#known-issues).

---

## Flashable image

Images are published under [Releases][releases], built by CI on a native arm64
runner and marked prerelease. Each one is booted under emulation before it is
published, and a build whose image does not come up does not get published at
all — see [Known issues](#known-issues) for exactly what that check covers and
what it cannot.

They are prereleases because **nobody has booted one on a Raspberry Pi**. That
is the remaining gap, and it is the single most useful thing anyone reading
this could close.

The process for producing one by hand, and the tooling to package and publish
it, are in [docs/IMAGE.md](docs/IMAGE.md).
`packaging_utilities/package_release.sh` compresses, checksums and splits an
image into parts under GitHub's 2 GiB per-asset limit, and verifies the parts
reassemble byte for byte before it will finish.

You can run the same boot check yourself on anything you download:

```bash
packaging_utilities/emulate_image.sh shackwright.img
```

To install onto an existing system instead of flashing a card, run the
playbook against a fresh Raspberry Pi OS install as below.

[releases]: https://github.com/Dustpan95/Shackwright/releases

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
git clone https://github.com/Dustpan95/Shackwright.git
cd Shackwright

# Control-node tooling. Debian and Ubuntu mark their system Python as
# externally managed, so use a virtual environment.
python3 -m venv ~/.venv/shackwright
~/.venv/shackwright/bin/pip install -r requirements.txt
. ~/.venv/shackwright/bin/activate

# Set up key-based SSH to the target, then describe it to Ansible.
ssh-copy-id <user>@shack.local
cp hosts.example hosts
$EDITOR hosts

./run_shackwright
```

`hosts` is git-ignored, so your inventory survives updates and your credentials
are never committed. The runner prompts for the target's sudo password rather
than storing it.

Expect the full build to take **several hours** — most of it is compiling from
source. Output is logged to `ansible-output/`.

Any extra arguments are passed straight through to `ansible-playbook`:

```bash
./run_shackwright --limit shack.local     # one host
./run_shackwright --check                 # dry run
```

---

## Known issues

What is still wrong, and what was wrong badly enough to be worth recording
after the fact. Most of the open items are recorded rather than fixed because
confirming them needs a real build. Help with any of them is welcome.

**Two defects made most of this tree unusable. Both are fixed and guarded.**

Every playbook that passed `warn:` to `command` or `shell` failed outright.
ansible-core removed that argument in 2.14, released November 2022, and it is
not ignored — the task dies with *Unsupported parameters*. It appeared 39
times across 31 files, 27 of them imported by `tasks/main.yml`, so a quarter
of a full run could not succeed on any Ansible newer than three years old.

Separately, 23 playbooks found "the latest version" by fetching a web page and
running `grep -Po` over the HTML. When this work started, 21 of the 27
testable lookups returned an empty string, which was interpolated straight
into a download URL. One was worse than broken: `install_flnet` matched a
number out of w1hkj.com's 404 page and reported flnet 7.0.4, a version that
has never existed. Lookups now use interfaces meant to be parsed — SourceForge
RSS, the GitHub releases API — and assert on the result before building a URL,
so a failed lookup stops with an explanation instead of a 404 or a fiction.

`tests/test_removed_ansible_args.sh` runs in CI and fails if either comes
back.

**The image boots under emulation. That is not the same as booting on a Pi.**
`.github/workflows/build-image.yml` boots every image it builds to a login
prompt before publishing it, and refuses to publish one that does not come
up. You can run the same check on a downloaded release yourself:

```bash
packaging_utilities/emulate_image.sh shackwright.img
```

Getting there meant going around QEMU rather than through it. QEMU's
`raspi3b` cannot boot Raspberry Pi OS to a login prompt: root mounts,
`/sbin/init` runs, systemd prints *Welcome to Debian GNU/Linux 13 (trixie)!*,
and about nine seconds later the board resets — no shutdown sequence, no
reboot request, no panic. That reproduces exactly on the stock, untouched
image, which is why `qemu-boot-probe.yml` exists: to keep a control behind
any claim about a built one. `raspi3b` does not model the Pi firmware; the
same boot logs `Failed to get GPIO 5 config` and carries a watchdog whose
emulated behaviour is not the hardware's. `raspi4b` needs QEMU 9.0, which the
runners do not have.

So the userland is booted under QEMU's `virt` machine with a generic kernel
instead. The Raspberry Pi kernel cannot be used there — its arm64 defconfigs
contain no virtio at all — and Debian's cloud arm64 kernel builds
`VIRTIO_BLK` as a module, which would mean shipping an initramfs. It builds
`BLK_DEV_NVME`, `EXT4_FS`, `MSDOS_PARTITION`, `PCI_HOST_GENERIC` and
`SERIAL_AMBA_PL011` in, so attaching the image as an NVMe namespace needs no
initramfs and nothing from the image. The image is booted through a QEMU
overlay and never written to, so what gets published is byte-for-byte what
was tested.

It takes two boots, and that is not laziness. Running a command at boot means
`systemd.run=`, whose generator does not add a unit so much as redirect
`default.target` at one of its own — so a boot carrying it never reaches
multi-user or graphical at all. One boot runs the programs and powers itself
off; a second, ordinary boot goes to the login prompt. The script reports on
both, and fails if either does not do its job.

**What that establishes:** the partition table and filesystem are sound, the
userland comes up far enough to offer a login prompt, and every program the
build manifest recorded is present with its shared libraries resolving — the
failure a chroot build hides, where a program links against something that
was there while building and is not there in the shipped image.

**What it does not:** anything about the Raspberry Pi firmware or kernel, the
GPU or display, audio, GPIO, Wi-Fi, or a radio on a serial or USB port. **No
image here has been booted on real hardware.** Reports from anyone who does
are still the single most useful thing this project could receive.

**17 applications are disabled.** `tasks/main.yml` imports 100 playbooks and
has 17 commented out, most marked "broken under Bookworm" by upstream —
including SDRAngel, SDR++, dump1090, rpitx, DroidStar, noaa-apt and the DRAWS
hat support. Each needs to be tried against Trixie and either repaired or
retired. They all still pass a syntax check, so re-enabling one is a one-line
change.

One of them cannot be repaired: `install_twhamqth` fetches from
`wa0eir.bcts.info`, which no longer exists, and no distribution packages it.
`install_twclock` fetched from the same dead site, but Debian still carries
`twclock`, so it is restored from the package rather than retired.

**No image has ever contained the whole tree.** The image build installs a
list of twelve playbooks chosen to exercise the repairs, not to assemble a
complete station — see `DEFAULT_PLAYBOOKS` in
`.github/workflows/build-image.yml`. A build of all 100 enabled playbooks has
never been attempted, so the published images are a working subset rather
than the full distribution, and the time and disk a full run needs are
unknown. The job's timeout is 350 minutes.

**`INJECT_FACTS_AS_VARS` will break this tree.** Playbooks here reference
gathered facts as bare names — `ansible_architecture`,
`ansible_distribution_release`, `ansible_userspace_bits` — rather than through
`ansible_facts`. That injection is deprecated and scheduled for removal in
ansible-core 2.24, at which point each becomes undefined. There are 61 such
references across 7 files. The `is_*` variables are unaffected: they come
from `set_fact` in `library/set_facts.yml`, not from fact injection.

**Images carry two kernels.** The build dist-upgrades the base image, which
installs a newer kernel without removing the one Raspberry Pi OS shipped. The
manifest from build 13 lists four module directories — 6.18.34 and 6.18.39,
each in `-2712` and `-v8` flavours. It costs image size and download size for
a kernel nothing will boot. Removing the superseded one is safe in principle
and untested here.

**SDR support is restored.** This was 12 of the 34. Every SoapySDR driver
module was disabled as "build broken under Bookworm", and an arm64 trial found
that diagnosis was wrong: each pulled in `gr-osmosdr`, which reaches
`xtrx-dkms`, which compiles a kernel module at install time. Where that fails,
apt fails, the task retries five times at thirty-second intervals, and the play
dies minutes later having compiled nothing. `gr-osmosdr` is a GNU Radio block a
SoapySDR device driver never needed.

They are now installed from Debian, which packages the core library, tools,
Python bindings and thirteen driver modules for arm64 and armhf. That restores
Airspy, bladeRF, HackRF, OsmoSDR, Red Pitaya, RTL-SDR and USRP, adds LimeSDR,
Mirics and RFspace which were never here before, and replaces well over an hour
of compiling with an apt install. Five devices remain unpackaged and still need
source builds: AirspyHF, FunCube Dongle Pro+, PlutoSDR, VOLK converters, and
SDRplay, whose API is proprietary.

**Ten enabled playbooks install dependencies only for old releases.** They
branch on Buster, Bullseye or Jammy and match nothing on Trixie, so the task
skips, Ansible reports success, and the application is built without its
dependencies:

`install_bluedv` · `install_gridtracker` · `install_logging_apps` ·
`install_miscellaneous_apps` · `install_antenna_modeling_apps` ·
`install_cygnusRFI` · `install_digital_apps` · `install_jtdx` ·
`install_tapr_wspr` · `install_morsecode_apps`

**Version-pinned package names.** Around 30 dependencies name a specific shared
library soname (`libgfortran4`, `libgnuradio-osmosdr0.2`, `libqcustomplot2.0`).
Those names change with each Debian release. `tools/list_apt_packages.py
--suspicious` lists them; run it against a Trixie target to find which no longer
resolve.

**A branch that can never run.** `install_jtdx.yml` guards a dependency install
with `is_rpi and is_bullseye and not is_arm`. A Raspberry Pi is always ARM, so
that task has never executed.

**The rename is not finished below the waterline.** Everything a person reads
says Shackwright, and the built system's bug-report URL now points here rather
than at W3DJS's tracker. Still carrying HamPi names, because each one changes
what lands on the target and cannot be verified without a build:

* The `is_hampi` / `is_hampc` / `is_hamiq` facts, and the conditionals in
  roughly fifteen playbooks that branch on them.
* `/etc/hampi-release` and friends, `about_hampi`, `HamPi.desktop`, the
  wallpapers, and the `files/home/hampi/` skeleton.
* `version_check.sh` polls SourceForge for new *HamPi* releases. Under this
  name that check can never succeed; it needs repointing or removing once
  there is a release channel.

None of that is user-visible branding you can't live with for now, but it
should land before a first tagged release.

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
./tests/test_packaging.sh                               # release packaging
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
* **APRS and packet** — Graywolf, Xastir, YAAC, aprx, AX.25 tooling, LinPac
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
2. **Repair a disabled application.** Pick one of the 17, get it building on
   Trixie, re-enable its import in `tasks/main.yml`.
3. **Confirm package availability** on Trixie with `tools/list_apt_packages.py`.

Please keep CI green: run the four commands under [Development](#development)
before opening a pull request.

---

## Credits

Shackwright is a continuation of **HamPi**, created and maintained for six
years by **Dave Slotter, W3DJS**, with contributions from many others — see
[CONTRIBUTORS.md](CONTRIBUTORS.md). The architecture, the application selection
and the overwhelming majority of this code are his and theirs. The rename is
not a claim on that work; it exists so this project's bugs and releases are not
confused with his.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).

Copyright 2020 - 2024, Dave Slotter (W3DJS).
Copyright 2024 - 2026, Shackwright contributors.
