# DietPi continuation roadmap

Maintained by [Dustpan95](https://github.com/Dustpan95), continuing [HamPi by Dave Slotter, W3DJS](https://github.com/dslotter/HamPi).

## 1. Foundation — implemented, target installation pending

- Offline plan and explicit target inventory.
- DietPi/Trixie, Pi 4/5, native ARM64 and non-root station-account checks.
- Selectable digital, packet and SDR package profiles.
- Desktop installed through DietPi's software manager.
- Accurate failure status and installed-version records.
- Automated configuration, platform and syntax checks.

Package selection is currently a distribution-package baseline. Audit and package newer upstream releases where a station requirement needs them.

## 2. First complete desktop station

- Record the first Pi, transceiver and USB audio/CAT interface in a hardware support matrix.
- Validate a fresh installation on DietPi ARM64/Trixie.
- Verify Xfce login as the station user and persistent audio settings.
- Select stable device names that survive reboot and USB reconnect.
- Establish CAT ownership and explicit PTT behavior.
- Verify time synchronization, application launch and receive/decode operation.
- Perform the intended transmit test with the station operator and record its result.
- Repeat installation and verify existing station settings and access survive.

## 3. Remote desktop

- Provide a persistent station desktop on a Pi without HDMI connected.
- Add authenticated remote access; assess TigerVNC and browser access through noVNC.
- Validate existing-session reconnection, display resizing, keyboard/mouse and touch input.
- Keep modem audio local and verify device permissions without a local console login.
- Test connection loss, PTT release and duplicate-client behavior.
- Test SDR rendering/performance separately; a functional remote desktop does not prove GPU acceleration.

## 4. Application expansion

- Add JS8Call, CHIRP, Pat/Winlink and GridTracker after checking their current ARM64 installation paths.
- Add logging and SDR backends incrementally with visible support status.
- Keep source builds versioned and packaged; avoid replacing shared system libraries ad hoc.
- Add radio configuration only with hardware-specific examples and validation.

## 5. Flashable images

- Pin a DietPi base image URL, version and SHA256 for each board target.
- Use the same installation roles as a normal station installation.
- Separate image sealing from installation; handle machine identity and first-boot credentials only in the image workflow.
- Capture package versions, source references, licenses, build logs and test results.
- Pin and retain build inputs; recording installed versions alone is not reproducibility.
- Boot-test images on both claimed board models before publishing an alpha.
- Publish image checksums, matching sources, migration instructions and known limitations.
- Derive a services-only edition from the same roles when the supported background workloads justify it.

## Source audit carried forward

The historical playbooks assume usernames and hardware, mix image cleanup into live installation, contain disabled Bookworm integrations and include a forced failure before finishing. The new entry point deliberately has its own platform detection and configuration. Preserve the historical source and attribution while replacing the installation behavior in reviewable changes.
