# Building and releasing a flashable image

Shackwright is a playbook, not an image. Running it against a fresh Raspberry
Pi OS install takes several hours because most applications are compiled from
source. Most people do not want to do that, so releases ship a ready-made card
image they can flash and boot.

This is how that image gets made. It is a manual process today; the automation
that exists covers packaging and publishing, not the build itself. See
[Why this is not fully automated](#why-this-is-not-fully-automated).

---

## 1. Build the station

Start from a clean, current Raspberry Pi OS so the image is reproducible and
carries no leftovers from a previous attempt.

1. Flash **Raspberry Pi OS Trixie, 64-bit**, to a card at least 32 GB.

   The board generation matters less than memory. Raspberry Pi OS 64-bit is a
   single image across Pi 3/4/400/5/500/Zero 2 W, so an image built on a Pi 4
   boots a Pi 5 and vice versa — build on whatever you have.

   | Board | Suitability |
   |-------|-------------|
   | Pi 5 / 500 | Best; roughly 2–3× a Pi 4 at compiling |
   | Pi 4 8 GB / Pi 400 | Fine, slower |
   | Pi 4 4 GB | Fine |
   | Pi 4 2 GB | Workable but slow; builds serially |
   | Pi 3 (1 GB), Zero 2 W (512 MB) | Not recommended |

   The playbook caps parallel compilation by memory and enlarges swap for the
   duration of the build, so small boards no longer die to the OOM killer part
   way through — they just take longer. 64-bit is not optional: Trixie no
   longer ships a 32-bit Pi 4 kernel, and 32-bit ARM changed several library
   ABIs without changing their names in the 64-bit `time_t` transition.
2. Boot it, complete first-run setup, enable SSH.
3. Update it fully: `sudo apt update && sudo apt full-upgrade`, then reboot.
4. From another machine, set up key-based SSH and run the playbook:

   ```bash
   cp hosts.example hosts
   $EDITOR hosts
   ./run_shackwright
   ```

Expect several hours. The log lands in `ansible-output/`. **Read it before
going further** — Ansible reports a skipped task as success, so a clean exit
does not mean every application installed. Search the log for `failed=` and for
skipped tasks in the playbooks listed under "Known issues" in the README.

## 2. Prepare the card for imaging

On the Pi, before powering down:

```bash
# Remove the SSH host keys, so every flashed card does not share one identity.
sudo rm -f /etc/ssh/ssh_host_*

# Clear the logs, shell history and package cache.
sudo apt clean
sudo journalctl --rotate && sudo journalctl --vacuum-time=1s
rm -f ~/.bash_history

# Zero the free space so it compresses to nothing.
sudo dd if=/dev/zero of=/zero.fill bs=4M status=progress || true
sudo rm -f /zero.fill
sudo sync
```

Then shut down: `sudo poweroff`.

Do not skip removing the host keys. Every user who flashes the image would
otherwise receive the same SSH host identity, which defeats the warning that
tells them when they are connecting to the wrong machine.

## 3. Capture the image

Move the card to another Linux machine. Identify it carefully with `lsblk` —
the next command reads a whole block device and it is easy to name the wrong
one.

```bash
sudo dd if=/dev/sdX of=shackwright.img bs=4M status=progress
```

## 4. Shrink it

A captured image is as large as the card. Without shrinking, a 32 GB image
forces every user onto a 32 GB or larger card even if only 12 GB is in use, and
the first boot cannot expand a filesystem that already fills the card.

[PiShrink](https://github.com/Drewsif/PiShrink) is the established tool:

```bash
sudo pishrink.sh -Z shackwright.img
```

`-Z` also compresses. If you let PiShrink compress, skip the compression in the
next step and adjust accordingly; the packaging script expects an uncompressed
`.img`.

Shackwright does not reimplement shrinking. Resizing a filesystem and rewriting
a partition table is exactly where a subtle bug yields images that appear to
flash and then will not boot.

## 5. Package it

```bash
packaging_utilities/package_release.sh shackwright.img 4.0.0
```

This compresses with `xz`, writes a SHA256, and splits the result into parts
under GitHub's 2 GiB per-asset limit if needed. It then **verifies the parts
reassemble to exactly what went in** and refuses to continue if they do not.
It also writes a `RELEASE.md` with verification, reassembly and flashing
instructions for the person downloading.

Artifacts land in `release/`.

## 6. Publish it

Create a GitHub release and upload every artifact from `release/`. Paste the
generated `RELEASE.md` into the release notes.

GitHub caps one asset at 2 GiB but allows up to 1000 assets per release, with
no cap on total size and no bandwidth charge, so a split image is a supported
way to distribute this. Historically HamPi used SourceForge and BitTorrent;
either remains a reasonable mirror, and a torrent spares the project's
bandwidth entirely.

**Do not publish an image built from a run you have not read the log of, and do
not describe an image as a release until it has been flashed and booted on real
hardware.**

---

## Why this is not fully automated

GitHub's `ubuntu-24.04-arm` runners are free for public repositories and are
native ARM64, so in principle the build could run in CI. Three things stop it
today:

- **A job is capped at 6 hours.** A full build takes several hours on a Pi 5
  and the runners are not faster at this than the hardware. The full
  application catalogue would very likely exceed the cap.
- **Runners have roughly 25–29 GB of free disk.** A 32 GB image plus build
  artifacts plus the compressed output does not comfortably fit.
- **Nothing has been validated on hardware yet.** Automating the production of
  an artifact nobody has confirmed boots would only produce broken images
  faster.

A reduced profile — a smaller application set aimed at the digital modes — may
well fit inside those limits, and is the obvious first target for automation
once a manual build has been proven.
