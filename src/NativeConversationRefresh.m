// Native coordinator refresh: no navigation and no replacement message view.
#import "NativeConversationRefresh.h"
#import "RuntimeResolver.h"
#import "ConversationLiveSync.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <substrate.h>
#include <string.h>

void *CGNativeOriginalConstructor;
void *CGNativeRemoteIDAddress;
void *CGNativeRefreshAddress;
extern void CGNativeCaptureConstructor(void);
extern BOOL CGNativeCoordinatorMatches(id, NSString *);
extern void CGNativeStartRefresh(id, void (^)(BOOL));
static NSHashTable *coordinators;
static BOOL installed;
static BOOL refreshing;

void CGNativeRememberCoordinator(id coordinator) {
    if (!coordinator) return;
    @synchronized(coordinators) { [coordinators addObject:coordinator]; }
    CGChatSyncLogEvent(@"NATIVE_COORDINATOR_CAPTURED");
}

BOOL CGNativeRefreshConversation(NSString *identifier, void (^completion)(BOOL)) {
    if (!NSThread.isMainThread || !installed || refreshing || !identifier.length)
        return NO;
    NSArray *objects;
    @synchronized(coordinators) { objects=coordinators.allObjects; }
    for (id object in objects) {
        if (!CGNativeCoordinatorMatches(object,identifier)) continue;
        // Avoid racing a reply generated locally by this coordinator.
        Ivar stream=class_getInstanceVariable(object_getClass(object),"streamTask");
        if (!stream) return NO;
        void *task=NULL;
        memcpy(&task,(const uint8_t *)(__bridge void *)object+ivar_getOffset(stream),sizeof(task));
        if (task) { CGChatSyncLogEvent(@"NATIVE_LOCAL_STREAM_ACTIVE"); return NO; }
        refreshing=YES;
        CGNativeStartRefresh(object,^(BOOL success) {
            refreshing=NO;
            if (completion) completion(success);
        });
        return YES;
    }
    return NO;
}

static BOOL CGNativeKnownImage(void) {
    static const unsigned char uuid[16]={0xf1,0xcf,0x3b,0x21,0xaa,0xaf,0x3e,0x57,0xbb,0x62,0xce,0x61,0x49,0xaa,0x90,0x40};
    for (uint32_t i=0;i<_dyld_image_count();i++) {
        const char *name=_dyld_get_image_name(i);
        if (!name || !strstr(name,"/ChatGPT.framework/ChatGPT")) continue;
        const struct mach_header_64 *h=(const void *)_dyld_get_image_header(i);
        if (h->magic!=MH_MAGIC_64) return NO;
        const uint8_t *p=(const void *)(h+1),*end=p+h->sizeofcmds;
        for (uint32_t j=0;j<h->ncmds && p+sizeof(struct load_command)<=end;j++) {
            const struct load_command *c=(const void *)p;
            if (c->cmdsize<sizeof(*c) || c->cmdsize>(size_t)(end-p)) return NO;
            if (c->cmd==LC_UUID && c->cmdsize>=sizeof(struct uuid_command))
                return !memcmp(((const struct uuid_command *)c)->uuid,uuid,16);
            p+=c->cmdsize;
        }
    }
    return NO;
}

__attribute__((constructor)) static void CGNativeInstall(void) {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
    if (!CGNativeKnownImage()) { CGChatSyncLogEvent(@"NATIVE_UNSUPPORTED_BINARY"); return; }
    // Shared initializer, including the provider's inlined allocator at 0xd8aff8.
    const uint32_t constructor[]={0xa9ba6ffc,0xa90167fa,0xa9025ff8,0xa90357f6};
    const uint32_t getter[]={0xd10183ff,0xa90357f6,0xa9044ff4,0xa9057bfd};
    const uint32_t refresh[]={0xf90016d4,0x90000000,0x9128f000};
    void *create=CGBResolveChatGPTTextAddress(0xd82348,constructor,4);
    CGNativeRemoteIDAddress=CGBResolveChatGPTTextAddress(0xd5a628,getter,4);
    CGNativeRefreshAddress=CGBResolveChatGPTTextAddress(0xd5da24,refresh,3);
    if (!create || !CGNativeRemoteIDAddress || !CGNativeRefreshAddress) {
        CGChatSyncLogEvent(@"NATIVE_SIGNATURE_MISMATCH"); return;
    }
    coordinators=[NSHashTable weakObjectsHashTable];
    MSHookFunction(create,(void *)CGNativeCaptureConstructor,&CGNativeOriginalConstructor);
    installed=CGNativeOriginalConstructor!=NULL;
    CGChatSyncLogEvent(installed?@"NATIVE_BRIDGE_READY":@"NATIVE_HOOK_FAILED");
}
