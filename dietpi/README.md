# DietPi station foundation

Development branch for an independent continuation of [HamPi by Dave Slotter, W3DJS](https://github.com/dslotter/HamPi).
Maintainer: [Dustpan95](https://github.com/Dustpan95).

**Status: installer foundation, awaiting physical station validation. There is no new flashable image yet.**
Use the `dietpi/` entry point for this work. The historical root-level playbooks are retained for reference and are not the DietPi installer.

## Initial target

- Raspberry Pi 4 Model B and Raspberry Pi 5 Model B.
- DietPi with Debian 13 Trixie and native `arm64` packages; complete DietPi first-boot setup first.
- Desktop operation with Xfce, installed using DietPi-Software item 25.
- An existing non-root station account, normally `dietpi`.

Board detection deliberately excludes other models until they have been tested. DietPi provides distinct base image entries for Pi 4 and Pi 5; a common installation recipe does not imply a universal boot image.

## Application profiles

| Profile | Initial packages | Desktop required |
| --- | --- | --- |
| `digital` | WSJT-X, FLDigi, FLRig | Yes |
| `packet` | Dire Wolf | No |
| `sdr` | RTL-SDR utilities, Gqrx | Yes |

Every selection includes ALSA diagnostics, USB diagnostics and Hamlib utilities. `profiles.json` is the catalog. An empty profile list installs only this common base. `desktop` and `services` are independent operating modes. Desktop is the default; services-only operation rejects GUI profiles.

These first recipes use packages available through the target's configured APT repositories. They do not claim to supply the latest upstream application versions. Packages such as JS8Call, CHIRP, Pat and GridTracker will be added as their install and validation paths are completed.

## Inspect a plan without installing anything

From the repository root, with Python 3:

```bash
python3 dietpi/station.py plan
cp dietpi/station.example.json dietpi/station.json
python3 dietpi/station.py plan --config dietpi/station.json
```

Edit `station.json` to select the existing station user, operating mode and profiles. For example, `"profiles": ["digital", "packet"]` combines them. `package_versions` can fix a selected package to an exact Debian version. APT rejects an unavailable version or a requested downgrade; it does not silently substitute another version.

## Check and install on an explicit target

Use a Linux controller with Python 3.11+ (the Pi itself can be the controller). Create an isolated environment:

```bash
python3 -m venv dietpi/.venv
. dietpi/.venv/bin/activate
python -m pip install -r dietpi/requirements.txt
cp dietpi/inventory.example.ini dietpi/inventory.ini
```

Edit the inventory for the intended Pi and SSH account. The example address is a documentation address and must be replaced. SSH host verification remains enabled; normal SSH keys or agent authentication are used. Local installation instead uses:

```ini
[station]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3
```

Then run:

```bash
python3 dietpi/station.py check --config dietpi/station.json --inventory dietpi/inventory.ini --ask-become-pass
python3 dietpi/station.py install --config dietpi/station.json --inventory dietpi/inventory.ini --ask-become-pass
```

Omit `--ask-become-pass` if the configured connection already supports the required privilege escalation. Dry-run mode probes the real target and asks Ansible to predict changes; it does not run DietPi-Software to simulate an Xfce installation. It therefore cannot prove that all desktop dependencies will install. The controller needs SSH access and the target needs its configured package repositories for a real installation.

To inspect a Pi without Ansible, run this directly on the Pi:

```bash
python3 dietpi/doctor.py --user dietpi
```

This reads platform information and account metadata without opening the radio. A rejected platform returns status 2. The launcher propagates Ansible's exit status so a failed installation cannot appear successful because its output was logged.

## Changes made during installation

The installer requests the selected packages, installs Xfce through DietPi when needed, appends the station account to `audio` and `dialout`, and writes installation records under `/var/lib/hamradio-station/`. Sign out and back in before relying on new group memberships. APT service starts for the radio package step are suppressed during the transaction; package installation is not radio configuration or authorization to transmit.

`packages.tsv` records exact installed versions and architectures for all packages. `installation.json` records the requested selection and detected platform, with hardware validation marked pending. These records are useful build evidence; they are not a complete reproducible-image lock. Release builds still need pinned base images and archived package/source inputs.

The installer does not choose a callsign, serial port, audio device, PTT method or radio frequency. It does not change SSH keys, passwords, hostname, networking or sudo policy. Image sealing belongs to the future image builder. DietPi's own desktop installer manages its desktop dependencies and settings.

## Desktop and remote operation

GUI applications will continue running on the Pi. A persistent remote desktop will provide monitorless access to that station session. VNC and optional browser access through noVNC are planned; this foundation does not yet install or configure them.

For digital modes, keep radio audio and CAT/PTT local to the Pi. Remote desktop should carry screen/input without redirecting modem audio. Remote voice audio will require a separate feature. The station session must avoid competing processes claiming the same radio port or sound device.

## Validation and next work

```bash
python3 -m unittest discover -s dietpi/tests -v
ANSIBLE_CONFIG=./dietpi/ansible.cfg ansible-playbook -i dietpi/inventory.example.ini dietpi/install.yml --syntax-check
```

See [ROADMAP.md](ROADMAP.md) for remaining work and physical acceptance criteria. Automated checks cannot certify USB audio, CAT/PTT, RF operation, monitorless graphics or Pi boot compatibility.

## Upstream and licensing

HamPi's original authors, notices and LICENSE are preserved. The source baseline is `4eed262339560ef3a9e6f58b1b261a5c6bb5ecb1` (3 April 2024). The original license includes custom additional terms; bundled components must also retain their own licensing and required source availability. The new image release process will account for these component by component.

Reference material used for this foundation:

- [DietPi supported hardware](https://dietpi.com/docs/hardware/)
- [DietPi desktop options](https://dietpi.com/docs/software/desktop/)
- [DietPi remote desktop options](https://dietpi.com/docs/software/remote_desktop/)
- [DietPi software-manager source at the reviewed revision](https://github.com/MichaIng/DietPi/blob/bfad9131fbf66e86182d8138af8f6578f882023e/dietpi/dietpi-software)
- [Debian Trixie WSJT-X](https://packages.debian.org/trixie/wsjtx), [FLRig](https://packages.debian.org/trixie/flrig), [Dire Wolf](https://packages.debian.org/trixie/direwolf), [Gqrx](https://packages.debian.org/trixie/gqrx-sdr)
