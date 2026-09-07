# Repository working rules

- Perform development on the existing `Testing` branch. Do not push to `master`, `BetaTesting`, or another branch without the owner's instruction.
- The project is named Shackwright. It was renamed from HamPi so its issues and releases are not confused with the original, which is dormant.
- Project maintainer and commit identity: `Dustpan95` (GitHub user ID `56422179`). Do not add tool, assistant, vendor or bot author/co-author/contributor credits.
- Preserve the original HamPi authors' attribution and license notices.
- The new platform is DietPi ARM64 on Raspberry Pi 4 Model B and Pi 5 Model B. Desktop operation, selectable radio profiles and flashable images are project requirements.
- Keep the new installation entry point in `dietpi/`. The root-level historical playbooks are not the new installer.
- Keep live installation separate from image sealing. Do not erase station access credentials or user configuration as part of installation.
- Report automated checks separately from physical hardware validation. Do not describe an untested installer or image as a working station release.
