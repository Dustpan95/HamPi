# Repository working rules

- Perform development on the existing `Testing` branch. Do not push to `master`, `BetaTesting`, or another branch without the owner's instruction.
- The project is named Shackwright. It was renamed from HamPi so its issues and releases are not confused with the original, which is dormant.
- Project maintainer and commit identity: `Dustpan95` (GitHub user ID `56422179`). Do not add tool, assistant, vendor or bot author/co-author/contributor credits.
- Preserve the original HamPi authors' attribution and license notices.
- The DietPi tree was removed from `master` and `BetaTesting` at the owner's direction. It remains on the `Testing` branch. Do not reintroduce it to `master` or `BetaTesting` without the owner saying so.
- On `master` and `BetaTesting`, the root-level playbooks are the installer. Shackwright targets Raspberry Pi OS Trixie on Raspberry Pi, and Debian or Ubuntu on a PC.
- Keep live installation separate from image sealing. Do not erase station access credentials or user configuration as part of installation.
- Report automated checks separately from physical hardware validation. Do not describe an untested installer or image as a working station release.
