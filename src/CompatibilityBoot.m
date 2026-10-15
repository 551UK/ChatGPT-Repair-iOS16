// ChatGPTRepair v0.55 compatibility startup: loads the full tested legacy component.
// This is a temporary diagnostic build; remove the file log in the final release.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>

static void *gCGRCompatibilityHandle = NULL;
static NSString *const kCGRCompatLogName = @"ChatGPTRepair-Compatibility-v055.log";

static void CGRCompatLog(NSString *message) {
    @try {
        NSString *file = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"]
                          stringByAppendingPathComponent:kCGRCompatLogName];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message ?: @""];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:file]) [fm createFileAtPath:file contents:nil attributes:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:file];
        if (h) {
            [h seekToEndOfFile];
            [h writeData:data];
            [h closeFile];
        }
    } @catch (__unused NSException *e) {}
}

// Exported and called by v53's own two earliest constructors before history hooks.
// An additional constructor guards early boot in case one original constructor moves.
void CGRCompatibilityEnsureLoaded(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @autoreleasepool {
            if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
            const char *paths[] = {
                "/var/jb/Library/MobileSubstrate/DynamicLibraries/ChatGBeFree.dylib",
                "/Library/MobileSubstrate/DynamicLibraries/ChatGBeFree.dylib"
            };
            const char *lastError = NULL;
            for (unsigned i=0; i<sizeof(paths)/sizeof(paths[0]); i++) {
                dlerror();
                gCGRCompatibilityHandle = dlopen(paths[i], RTLD_NOW | RTLD_GLOBAL);
                if (gCGRCompatibilityHandle) {
                    CGRCompatLog([NSString stringWithFormat:@"component_load=OK path=%s", paths[i]]);
                    break;
                }
                lastError = dlerror();
            }
            if (!gCGRCompatibilityHandle) {
                CGRCompatLog([NSString stringWithFormat:@"component_load=FAILED error=%s",
                              lastError ?: "unknown"]);
                return;
            }
            // Check exported entry points without calling them. They remain owned
            // and installed by the original dylib's initializers/hooks.
            const char *functions[] = {
                "LVBRealtimeVoiceStart",
                "LVBInstallLegacyNativeVoiceLifecycleBridge",
                "CGBLegacyModelCatalog",
                "CGBPersistedModelSelection",
                "CGBInstallLegacyCopyBridge",
                "CGBLegacyGeneratedImageMessages",
                "CGBLegacyImageCompatibleObject",
                "CGBLegacyFileServiceURLForSedimentURL"
            };
            unsigned found=0;
            for (unsigned i=0; i<sizeof(functions)/sizeof(functions[0]); i++) {
                if (dlsym(gCGRCompatibilityHandle, functions[i])) found++;
                else CGRCompatLog([NSString stringWithFormat:@"missing_export=%s", functions[i]]);
            }
            BOOL voiceProtocol = objc_getClass("LVBVoiceURLProtocol") != Nil;
            CGRCompatLog([NSString stringWithFormat:
                @"component_exports=%u/%u voice_protocol_class=%d",
                found, (unsigned)(sizeof(functions)/sizeof(functions[0])), voiceProtocol]);
        }
    });
}

__attribute__((constructor)) static void CGRCompatibilityEarlyBoot(void) {
    CGRCompatibilityEnsureLoaded();
}
