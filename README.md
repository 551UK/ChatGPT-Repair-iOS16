# ChatGPTRepair

Source-built compatibility tweak for the official legacy ChatGPT iOS app on jailbroken iOS 16.

## Features

- Restores chat history, longer conversations, and a pinned sidebar with pin/unpin actions.
- Protects the active conversation from sidebar refreshes and transient failed requests.
- Restores file downloads, clickable links, citations, and rich markup compatibility.
- Adds the original ChatGBeFree model, generated-image, copying, voice, and sunset-bypass compatibility modules.

## Source and credits

Every functional component is compiled directly from the files in this repository. The original ChatGBeFree project is preserved under `upstream/chatgbefree/` with its licence, README, and build files. Original upstream project: https://github.com/liamschwie/ChatGBeFree .

This repository is distributed under GNU GPLv3. The single `ChatGPTRepair.dylib` in the rootless Debian package is built from source; no precompiled ChatGBeFree binary is included.

## Build

Install Theos with an iOS SDK and run:

```sh
make clean package FINALPACKAGE=1
```

Only install one ChatGBeFree-compatible tweak at a time to avoid duplicate runtime hooks.
