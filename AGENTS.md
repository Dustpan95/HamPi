# Repository working rules

- Perform development on the `BetaTesting` branch. Do not push to `master` or another branch without the owner's instruction. (`Testing` no longer exists on the remote; this rule named it until 2026-09-08.)
- The project is named Shackwright. It was renamed from HamPi so its issues and releases are not confused with the original, which is dormant.
- Project maintainer and commit identity: `Dustpan95` (GitHub user ID `56422179`). Do not add tool, assistant, vendor or bot author/co-author/contributor credits.
- Preserve the original HamPi authors' attribution and license notices.
- The DietPi tree was removed at the owner's direction and must not be reintroduced. It is gone from `BetaTesting`. It is **still present on `master`** -- 19 files including `dietpi/` and two workflows -- because `master` has not been updated since. `master` is the default branch, so that tree is what the repository's landing page still advertises.
- On `master` and `BetaTesting`, the root-level playbooks are the installer. Shackwright targets Raspberry Pi OS Trixie on Raspberry Pi, and Debian or Ubuntu on a PC.
- Keep live installation separate from image sealing. Do not erase station access credentials or user configuration as part of installation.
- Report automated checks separately from physical hardware validation. Do not describe an untested installer or image as a working station release.
