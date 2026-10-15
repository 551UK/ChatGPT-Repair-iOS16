// ARM64 Swift ABI adapters for the UUID-checked 1.2024.200 framework.
.text
.p2align 2
// C: fn, NSString, output Swift.String[2]; bridge returns owned x0/x1.
.globl _CG46BridgeString
_CG46BridgeString:
 stp x19, x30, [sp, #-16]!
 mov x16, x0
 mov x0, x1
 mov x19, x2
 blr x16
 stp x0, x1, [x19]
 ldp x19, x30, [sp], #16
 ret
// C: constructor, destination, owned ID words, owned configuration.
// Swift init(id:configuration:tree:) has optional Tree in x3/x4/x5.
.globl _CG46MakeConversation
_CG46MakeConversation:
 stp x20, x30, [sp, #-16]!
 mov x16, x0
 mov x8, x1
 ldp x0, x1, [x2]
 mov x2, x3
 mov x3, #0
 mov x4, #0
 mov x5, #0
 blr x16
 ldp x20, x30, [sp], #16
 ret
// C: setter, inout Conversation, owned Swift.String words.
.globl _CG46SetString
_CG46SetString:
 stp x20, x30, [sp, #-16]!
 mov x16, x0
 mov x20, x1
 ldp x0, x1, [x2]
 blr x16
 ldp x20, x30, [sp], #16
 ret
// C: getter, borrowed Conversation, output title-state (17 bytes).
.globl _CG46GetTitle
_CG46GetTitle:
 stp x19, x20, [sp, #-32]!
 stp x29, x30, [sp, #16]
 mov x16, x0
 mov x20, x1
 mov x19, x2
 blr x16
 stp x0, x1, [x19]
 strb w2, [x19, #16]
 ldp x29, x30, [sp, #16]
 ldp x19, x20, [sp], #32
 ret
// C: closure function, retained context, borrowed HistorySelection.
.globl _CG46Select
_CG46Select:
 stp x20, x30, [sp, #-16]!
 mov x16, x0
 mov x20, x1
 mov x0, x2
 blr x16
 ldp x20, x30, [sp], #16
 ret
