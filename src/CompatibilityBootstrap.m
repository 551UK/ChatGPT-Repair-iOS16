/*
 * ChatGPTRepair compatibility startup probe - TEMPORARY v0.54.1 TEST.
 * Verify the bundled compatibility dylib loads before the v53 history
 * constructor runs. This file and its logging MUST be removed for FINAL.
 * The compatibility dylib itself is preserved byte-for-byte.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>

static void CGRCompatTemporaryLog(NSString *line) {
    // Temporary diagnostics ONLY. Remove this entire function in final.
    NSString *base = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Caches/ChatGPTRepair-CompatProbe.log"];
    @try {
        @synchronized ([NSFileHandle class]) {
            NSFileManager *fm = NSFileManager.defaultManager;
            if (![fm fileExistsAtPath:base]) {
                [fm createFileAtPath:base contents:nil attributes:nil];
            }
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:base];
            if (!handle) return;
            @try {
                [handle seekToEndOfFile];
                NSString *entry = [NSString stringWithFormat:@"%@ %@\n",
                                   [NSDate date], line ?: @""];
                [handle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
            } @finally {
                [handle closeFile];
            }
        }
    } @catch (__unused NSException *e) {}
}

// Lower constructor priority runs before HistoryIsolation's default ctor.
// dlopen is idempotent when ElleKit has already injected the same image.
__attribute__((constructor(200))) static void CGRCompatibilityPreload(void) {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
        const char *path = "/var/jb/Library/MobileSubstrate/DynamicLibraries/ChatGBeFree.dylib";
        void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        const char *error = handle ? NULL : dlerror();
        Class protocol = objc_getClass("LVBVoiceURLProtocol");
        NSString *version = [[NSBundle mainBundle]
            objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        CGRCompatTemporaryLog([NSString stringWithFormat:
            @"preload handle=%d protocol_class=%d reported_version=%@ error=%s",
            handle != NULL, protocol != Nil, version ?: @"(null)",
            error ?: "(none)"]);
    }
}
