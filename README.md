# RaySens

> **Beta software.** RaySens is experimental and has only been tested on an Intel Hackintosh with an **Intel Core i7-11800H**. Other CPUs and Hackintosh configurations are unverified.

RaySens is a macOS menu bar utility for monitoring CPU frequency and controlling Intel Turbo Boost. It can also show CPU temperature when the system exposes a readable CPU sensor through AppleSMC/VirtualSMC. RaySens does not use or monitor the GPU.

## Features

- Shows the current nominal or sampled CPU frequency in the menu bar.
- Reports when a live frequency sample is above the nominal frequency, indicating that turbo frequency was observed.
- Enables or disables Turbo Boost using the bundled x86_64 legacy kernel extension.
- Optionally disables Turbo Boost during macOS startup.
- Provides a menu bar popover and can launch at user login.
- Reads CPU temperature from VirtualSMC CPU temperature keys when those keys are available.

## Known issues

- **CPU temperature may be unavailable.** RaySens reads CPU temperature keys such as `TC0D` and `TC0P` from AppleSMC/VirtualSMC. Some Hackintosh configurations do not expose these keys, even when `VirtualSMC.kext` is loaded. The `SMCProcessor.kext` sensor provider must publish a readable CPU temperature key. RaySens reports this as unavailable instead of estimating or fabricating a value.
- A frequency sample below the nominal frequency does not prove that Turbo Boost is disabled. A normal app process cannot read the CPU's turbo-enable MSR directly.
- macOS may reject the legacy kernel extension because of the system's boot security policy or macOS version. RaySens reports the system command error; changing SIP or OpenCore settings may be required and should only be done with a known recovery path.
- The release app is built for **Intel x86_64 macOS** and is ad-hoc signed. Gatekeeper may require opening the app from Finder or building it locally.

## Requirements

- macOS 13 or later on an Intel Mac or Intel Hackintosh.
- Swift 6 to build from source.
- For CPU temperature, a working VirtualSMC setup that publishes a CPU temperature key through `SMCProcessor.kext`.
- For Turbo Boost control, macOS must permit loading the included legacy x86_64 kernel extension.

## Build

```sh
swift build -c release
```

To create a launchable app bundle:

```sh
./scripts/package-app.sh
open .build/RaySens.app
```

## Beta download

**Beta 1 has been withdrawn and should not be redistributed.** Use the corrected Beta 2 archive below.

[Download RaySens 0.2.0 Beta 2 for Intel x86_64 macOS](https://github.com/YASEDEM/RaySens/raw/refs/heads/main/release-assets/RaySens-macOS-x86_64-0.2.0-beta.2.zip). The app is ad-hoc signed and not notarized.

Choose **Open RaySens at login** in the popover to start the menu bar app after sign-in.

## Monitoring and permissions

At launch, RaySens shows the nominal CPU frequency reported by `hw.cpufrequency`; this does not require administrator authorization. Choose **Start live frequency monitor** to install and run the background monitor. macOS requests administrator authorization for the LaunchDaemon, which samples CPU frequency and reads available SMC temperature keys. Use the same control to stop the monitor.

An observed live frequency above nominal means turbo frequency occurred during that sample. Turbo status is reported separately from observed frequency.

## Turbo Boost control

RaySens redistributes the x86_64 `DisableTurboBoost.64bits.kext` executable found in [Turbo Boost Switcher](https://github.com/rugarciap/Turbo-Boost-Switcher). The Turbo Boost Switcher project is GPLv2-licensed. The underlying kext source is from [nanoant/DisableTurboBoost.kext](https://github.com/nanoant/DisableTurboBoost.kext) and carries an MIT notice. RaySens includes both notices and the corresponding kext source files in the repository and app bundle; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). RaySens does not include the Turbo Boost Switcher app code. Disabling Turbo Boost asks macOS for administrator authorization to load the extension; enabling it unloads the extension. RaySens checks whether the extension is loaded before reporting the state.

**Disable Turbo on system startup** installs an optional LaunchDaemon that loads the same extension during macOS startup, before a user signs in. This only applies after macOS begins loading and does not affect BIOS or firmware startup. Turn the option off to remove the LaunchDaemon.

RaySens does not install `CPUTuneCore.kext`, edit the OpenCore EFI, or control the GPU. The application is not notarized.

## Tested hardware

The beta has been tested only on an Intel Hackintosh with an **Intel Core i7-11800H**. All other CPUs, macOS releases, and Hackintosh configurations are unverified. CPU temperature was not available on the current VirtualSMC configuration during development.

## Third-party code

The bundled Turbo Boost extension's binary comes from the [Turbo Boost Switcher](https://github.com/rugarciap/Turbo-Boost-Switcher) app bundle; its underlying source and MIT notice are from [nanoant/DisableTurboBoost.kext](https://github.com/nanoant/DisableTurboBoost.kext). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the included GPLv2 and MIT notices.
