# ChatGPTRepair

One unified, source-built iOS 16 ChatGPT tweak: models, voice, generated images, chat history, sidebar, pins, links and downloads.

## Features

- Restores chat history, older conversations and long-chat loading.
- Provides a pinned sidebar section with pin/unpin controls.
- Prevents active chats blanking during sidebar refreshes and transient network errors.
- Restores downloads, clickable links, citations and newer response formatting.
- Provides supported models and thinking options, with persistent selections.
- Restores voice, generated images, image history and the sunset-screen bypass.

## Build

Install Theos and an iOS SDK. Run `make clean package FINALPACKAGE=1`.

The source in `upstream/chatgbefree/` (ChatGBeFree 2.4.0) and `src/` (551UK repairs) compiles into a single `ChatGPTRepair.dylib` within one rootless `.deb`. No precompiled third-party binaries, patched IPAs or binary repacking are used.

## Credits

ChatGBeFree source originally by [liamschwie](https://github.com/liamschwie/ChatGBeFree). Original authorship retained. Distributed under GNU GPLv3; see `LICENSE`.

Do not simultaneously install another ChatGBeFree-compatible tweak.
