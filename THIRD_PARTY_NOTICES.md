# Third-party code

RaySens includes the x86_64 `DisableTurboBoost.64bits.kext` executable from the Turbo Boost Switcher project by Rubén García Pérez and contributors. The executable is unmodified and its SHA-256 is pinned in RaySens' packaging script. The bundle metadata is changed to `dev.raysens.DisableTurboBoost` / `RaySens` so macOS identifies this bundled component with RaySens. Its GPLv2 license is included at `Resources/ThirdParty-GPLv2.txt`.

The kext originates from the `nanoant/DisableTurboBoost.kext` implementation. RaySens invokes the bundled extension through macOS's administrator authorization prompt, then checks the loaded-kext state with `kmutil`.
