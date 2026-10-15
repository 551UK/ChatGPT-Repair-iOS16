# ChatGPTRepair

Single rootless iOS 16 ChatGPT compatibility package by 551UK. Installs a clean, v53-derived history/pinning repair and the preserved full legacy compatibility component into one installable DEB.

## Build

The GitHub Actions workflow in `.github/workflows/build.yml` uses Theos with the iPhoneOS 16.5 SDK to compile all ChatGPTRepair Objective-C/assembly sources, restore and SHA-256 verify the bundled binary from `vendor/compatibility-2.3.5.deb.b64`, and create one final DEB using `scripts/package_combined.py`. Only `main` is needed to build. All installed files must be under `/var/jb`.

The legacy 2.3.5 component is an **unchanged precompiled dylib** whose full editable source was not published. Its existing functionality is included in the one-DEB installer, but that component cannot be rebuilt or edited from its source in this repository. Modifications to that component require a separate source reconstruction. Upstream authorship and licence obligations remain.

The production ChatGPTRepair source has no diagnostic log-file writers or passive task-observation probes. Six-hour per-account history page caching is essential functionality and is retained.

Target: ChatGPT 1.2024.200, Dopamine rootless iOS 16.
