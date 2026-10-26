// Verified ARM64 Swift ABI: self=x20, async context=x22, error=x20.
.text
.p2align 2
.globl _CGNativeCaptureConstructor
_CGNativeCaptureConstructor:
 stp x19, x30, [sp, #-16]!
 adrp x16, _CGNativeOriginalConstructor@PAGE
 ldr x16, [x16, _CGNativeOriginalConstructor@PAGEOFF]
 blr x16
 mov x19, x0
 bl _CGNativeRememberCoordinator
 mov x0, x19
 ldp x19, x30, [sp], #16
 ret

.globl _CGNativeRemoteIDThunk
_CGNativeRemoteIDThunk:
 stp x20, x30, [sp, #-16]!
 mov x20, x0
 adrp x16, _CGNativeRemoteIDAddress@PAGE
 ldr x16, [x16, _CGNativeRemoteIDAddress@PAGEOFF]
 blr x16
 ldp x20, x30, [sp], #16
 ret

// A Swift free function takes its object in x0; the native method uses x20.
// Tail call preserves the caller's async continuation and native error handling.
.globl _CGNativeRefreshThunk
_CGNativeRefreshThunk:
 mov x20, x0
 adrp x16, _CGNativeRefreshAddress@PAGE
 ldr x16, [x16, _CGNativeRefreshAddress@PAGEOFF]
 br x16

.section __TEXT,__const
.p2align 2
.globl _CGNativeRefreshThunkTu
_CGNativeRefreshThunkTu:
 .long _CGNativeRefreshThunk - .
 .long 160 // Native async context size at 0x207d1c4 (UUID guarded).
