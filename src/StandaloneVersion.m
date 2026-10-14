/*
 * Optional standalone source reimplementation of publicly documented
 * ChatGBeFree version spoofing (Liam, GPL-3.0).
 * Intentionally NOT compiled into the companion package yet.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@implementation NSBundle (CGRStandaloneVersion)
- (NSDictionary *)cgr_standalone_infoDictionary {
    NSDictionary *info = [self cgr_standalone_infoDictionary];
    if (![info[@"CFBundleIdentifier"] isEqualToString:@"com.openai.chat"]) return info;
    NSMutableDictionary *copy = [info mutableCopy];
    copy[@"CFBundleShortVersionString"] = @"1.2026.202";
    copy[@"CFBundleVersion"] = @"30140022279";
    return copy;
}
@end

void CGRInstallStandaloneVersionSpoof(void) {
    Class cls = [NSBundle class];
    Method a = class_getInstanceMethod(cls, @selector(infoDictionary));
    Method b = class_getInstanceMethod(cls, @selector(cgr_standalone_infoDictionary));
    if (a && b) method_exchangeImplementations(a, b);
}
