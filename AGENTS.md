# Repository working rules

## Project

- The project is **Shackwright**, a continuation of HamPi by Dave Slotter,
  W3DJS. It was renamed from HamPi so this project's issues, releases and bug
  reports are not confused with his, which is dormant but still has an open
  issue tracker.
- Project maintainer and commit identity: `Dustpan95` (GitHub user ID
  `56422179`), callsign W0BTE. Commit as
  `56422179+Dustpan95@users.noreply.github.com`; do not use the maintainer's
  personal email address.
- Do not add tool, assistant, vendor or bot author, co-author or contributor
  credits anywhere: commits, documentation, code comments or metadata.
- Preserve the original HamPi authors' attribution and license notices. The
  project is GPL-3.0.

## Branches

- `BetaTesting` is the integration branch and carries both tracks. Develop
  there unless the owner says otherwise.
- Do not push to `master` or another branch without the owner's instruction.
- `master` and `Testing` are currently behind `BetaTesting` and still carry
  pre-rename HamPi naming; they need reconciling.

## The two tracks

This repository builds a ham radio station along two lines at once. Know which
one you are working in.

- `tasks/`, `library/`, `default/`, `files/` — the inherited HamPi playbooks.
  These install the full catalogue of a hundred-plus applications and are the
  only part that does so today. They target Raspberry Pi OS Trixie, Debian 13
  and Ubuntu, across Raspberry Pi, x86_64 PC and the Inovato Quadra. They are
  not the long-term installer, but they are the working one, so keep them
  correct rather than letting them rot.
- `dietpi/` — the newer installer targeting DietPi ARM64 on Raspberry Pi 4 and
  Pi 5, with selectable radio profiles and desktop operation. Keep its entry
  point in `dietpi/`. It does not yet install the application catalogue.
  Remote desktop integration and flashable images remain planned work.

Do not move work between the two trees without the owner's instruction.

## Engineering rules

- Keep live installation separate from image sealing. Do not erase station
  access credentials or user configuration as part of installation.
- Report automated checks separately from physical hardware validation. Do not
  describe an untested installer or image as a working station release. Nothing
  in this repository has been verified by an end-to-end hardware build.
- CI must stay green. Before pushing, run: `yamllint .`, `ansible-lint`,
  `ansible-playbook -i 'localhost,' --syntax-check tasks/main.yml`, and
  `./tests/run_tests.sh`. For the DietPi tree also run
  `python3 -m unittest discover -s dietpi/tests`.
- Do not pin Debian package names to a shared library soname
  (`libyaml-cpp0.7`, `libgfortran4`). Those names change with each Debian
  release and silently break the build. Prefer the stable `-dev` name.
- Do not add per-release branches that hardcode a value the target can be
  asked for, such as a Python version. That pattern is why Trixie builds
  failed.
