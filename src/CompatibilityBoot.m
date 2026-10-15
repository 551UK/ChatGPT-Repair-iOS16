/* ChatGPTRepair production compatibility startup.
 * Preserve all bundled 2.3.5 features; no diagnostic logging.
 */
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
static void *sCompatibilityImage;
void CGRCompatibilityEnsureLoaded(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @autoreleasepool {
            if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.openai.chat"]) return;
            sCompatibilityImage = dlopen(
                "/var/jb/Library/MobileSubstrate/DynamicLibraries/ChatGBeFree.dylib",
                RTLD_NOW | RTLD_GLOBAL);
            if (!sCompatibilityImage) {
                sCompatibilityImage = dlopen(
                    "/Library/MobileSubstrate/DynamicLibraries/ChatGBeFree.dylib",
                    RTLD_NOW | RTLD_GLOBAL);
            }
        }
    });
}
__attribute__((constructor)) static void CGRCompatibilityEarlyBoot(void) {
    CGRCompatibilityEnsureLoaded();
}
