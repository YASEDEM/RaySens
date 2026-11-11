# Third-party code

## DisableTurboBoost kernel extension

RaySens redistributes the x86_64 `DisableTurboBoost.64bits.kext` executable found in the Turbo Boost Switcher application by Rubén García Pérez and contributors. The executable is byte-for-byte identical to that bundled copy (SHA-256: `f81f003ccd5827122a41c39bddb78e4ffff37d84718a647dbd5fc3c6a92f987c`). RaySens changes only the kext bundle metadata (`CFBundleIdentifier` and `CFBundleName`) to identify the bundled component as RaySens.

The Turbo Boost Switcher project is distributed under GPLv2; its license is included at `Resources/ThirdParty-GPLv2.txt`. The underlying kext implementation is from Adam Strzelecki's `nanoant/DisableTurboBoost.kext` project. Its source file carries an MIT license notice; the corresponding source files and MIT notice are included under `Resources/ThirdPartySources/DisableTurboBoost.kext/`. The upstream source snapshot is commit `4f493b1927e0b62d5fab1f068302386c02317bc6` at <https://github.com/nanoant/DisableTurboBoost.kext>.

The Turbo Boost Switcher project source is available at <https://github.com/rugarciap/Turbo-Boost-Switcher>. RaySens does not include the Turbo Boost Switcher application code. The kext binary's SHA-256 is checked by `scripts/package-app.sh` so that the distributed binary cannot silently diverge from the reviewed copy.

RaySens invokes the bundled extension through macOS's administrator authorization prompt, then checks the loaded-kext state with `kmutil`.
