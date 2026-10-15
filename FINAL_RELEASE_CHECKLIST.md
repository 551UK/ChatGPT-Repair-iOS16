# ChatGPTRepair final-release blocker list

**Temporary diagnostic build: v0.54.1. Not the final production version.**

Before describing any combined version as final or deleting old releases:

1. On device, prove version-sunset screen is gone after force-close/reopen and respring.
2. Examine `Library/Caches/ChatGPTRepair-CompatProbe.log`: require `preload handle=1`, `protocol_class=1`, and the spoofed version. A successful dlopen alone does NOT prove all features work.
3. Confirm v53 history pagination, older chat loading, pinned chats opening, Pin and Unpin menus.
4. Confirm model selection, thinking settings, real-time voice, message copying, image loading and generation, and new-chat behaviour.
5. **REMOVE** temporary diagnostic function `CGRCompatTemporaryLog`, its log-file creation, `ChatGPTRepair-CompatProbe.log` constant and test-only messages from `src/CompatibilityBootstrap.m` (or replace that file with a production-only loader if required). Delete existing temporary diagnostic log from the testing device when safe; do not delete chats/cache.
6. Ensure release-source and built DEB contain **no compatibility diagnostic logging**. Use `grep -R 'ChatGPTRepair-CompatProbe.log\|CGRCompatTemporaryLog' src` (must return no matches) and scan the compiled payload as well.
7. Keep upstream licence/credit where it is legally required and do not describe the precompiled 2.3.5 component as source-editable.
8. Only after the combined DEB passes on-device testing: consider removing historical GitHub branches and releases. Keep v53 recovery backup outside the repository.

The v53 source files are the protected working base. Do not refactor them while solving compatibility startup.
