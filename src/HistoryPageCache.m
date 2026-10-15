#import "HistoryPageCache.h"
#import <CommonCrypto/CommonDigest.h>
#include <math.h>

static const NSTimeInterval kMaxAge=6*60*60;
static NSString * const kRetryHeader=@"X-551UK-History-Retry";

static NSString * const kCacheHeader=@"X-551UK-History-Cache";

static NSString *CGHeader(NSURLRequest *request,NSURLSessionConfiguration *config,NSString *name) {
    NSString *value=[request valueForHTTPHeaderField:name];
    if(value.length) return value;
    for(id key in config.HTTPAdditionalHeaders)
        if([key isKindOfClass:NSString.class] && [key caseInsensitiveCompare:name]==NSOrderedSame) {
            id v=config.HTTPAdditionalHeaders[key];
            if([v isKindOfClass:NSString.class]) return v;
        }
    return @"";
}
static NSString *CGPageKey(NSURLRequest *request,NSURLSessionConfiguration *config) {
    NSString *host=request.URL.host.lowercaseString;
    if(![request.HTTPMethod.uppercaseString isEqualToString:@"GET"] ||
       !([host isEqualToString:@"chatgpt.com"] || [host hasSuffix:@".chatgpt.com"] ||
         [host isEqualToString:@"openai.com"] || [host hasSuffix:@".openai.com"]))return nil;
    if(![request.URL.path isEqualToString:@"/backend-api/conversations"] &&
       ![request.URL.path isEqualToString:@"/backend-api/conversations/"])return nil;
    NSString *auth=CGHeader(request,config,@"Authorization");
    // No shared anonymous/cookie-only cache: identity must be explicit.
    if(!auth.length)return nil;
    NSURLComponents *parts=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSMutableArray *query=[NSMutableArray array];
    for(NSURLQueryItem *item in parts.queryItems)
        [query addObject:@[item.name,item.value?:@""]];
    [query sortUsingComparator:^NSComparisonResult(NSArray *a,NSArray *b) {
        NSComparisonResult order=[a[0] compare:b[0]];
        return order==NSOrderedSame?[a[1] compare:b[1]]:order;
    }];
    NSData *keyData=[NSJSONSerialization dataWithJSONObject:@[
        auth,CGHeader(request,config,@"ChatGPT-Account-ID"),CGHeader(request,config,@"OpenAI-Organization"),
        CGHeader(request,config,@"OpenAI-Project"),host,parts.path,query] options:0 error:NULL];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(keyData.bytes,(CC_LONG)keyData.length,digest);
    NSMutableString *key=[NSMutableString string];
    for(unsigned i=0;i<sizeof(digest);i++)[key appendFormat:@"%02x",digest[i]];
    return key;
}
static BOOL CGValidPage(NSData *data) {
    if(!data.length || data.length>4*1024*1024)return NO;
    id json=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [json isKindOfClass:NSDictionary.class] && [json[@"items"] isKindOfClass:NSArray.class];
}
// A rate-limited *older* history page must not be accepted as an empty page:
// the 2024 history controller already requests offset=20,40,... on scroll.
// Hold that existing completion, retry *that exact page* at a bounded pace,
// and return the real response to the controller. No fabricated pagination data.
// Current-page (offset=0) traffic continues to use v52's cache behaviour.
@interface CGOlderPageRetry : NSObject
@property(nonatomic,copy) NSString *key;
@property(nonatomic,strong) NSURLRequest *request;
@property(nonatomic,strong) NSURLSessionConfiguration *configuration;
@property(nonatomic,strong) NSMutableArray *waiters;
@property(nonatomic,strong) NSData *lastData;
@property(nonatomic,strong) NSURLResponse *lastResponse;
@property(nonatomic,strong) NSError *lastError;
@property(nonatomic,assign) NSUInteger attempts;
@end
@implementation CGOlderPageRetry
@end
static NSMutableDictionary<NSString *,CGOlderPageRetry *> *sOlderPageRetries;
static NSTimeInterval sOldPageRetryGate=0;

static NSUInteger CGOlderOffset(NSURLRequest *request) {
    NSURLComponents *parts=[NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *part in parts.queryItems) if([part.name isEqualToString:@"offset"]) {
        NSString *v=part.value?:@"";
        if(!v.length || v.length>7 ||
           [v rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound)
            return 0;
        return (NSUInteger)v.integerValue;
    }
    return 0;
}
static NSString *CGResponseHeader(NSHTTPURLResponse *response,NSString *header) {
    for(id key in response.allHeaderFields) if([key isKindOfClass:NSString.class] &&
            [key caseInsensitiveCompare:header]==NSOrderedSame) {
        id value=response.allHeaderFields[key];
        return [value isKindOfClass:NSString.class]?value:[value description];
    }
    return nil;
}
static NSTimeInterval CGRetryAfter(NSURLResponse *response) {
    if(![response isKindOfClass:NSHTTPURLResponse.class])return 0;
    NSString *value=CGResponseHeader((NSHTTPURLResponse *)response,@"Retry-After");
    if(!value.length)return 0;
    NSScanner *scanner=[NSScanner scannerWithString:value];
    double seconds=0;
    if([scanner scanDouble:&seconds] && scanner.isAtEnd && isfinite(seconds) && seconds>=0)
        return seconds;
    // Honor RFC 7231's IMF-fixdate alternative too.
    NSDateFormatter *formatter=[NSDateFormatter new];
    formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat=@"EEE, dd MMM yyyy HH:mm:ss 'GMT'";
    NSDate *date=[formatter dateFromString:value];
    return date?MAX(0,[date timeIntervalSinceNow]):0;
}
static void CGFinishOlderRetry(CGOlderPageRetry *job) {
    NSArray *waiters=nil;
    @synchronized([NSURLCache class]) {
        if(sOlderPageRetries[job.key]!=job)return;
        [sOlderPageRetries removeObjectForKey:job.key];
        waiters=[job.waiters copy];
        [job.waiters removeAllObjects];
    }
    // The completion is delivered only once to each of the app's original
    // consumers, on a background queue as with NSURLSession completion blocks.
    NSData *data=job.lastData;
    NSURLResponse *response=job.lastResponse;
    NSError *error=job.lastError;
    
    for(id waiter in waiters) {
        void (^completion)(NSData *,NSURLResponse *,NSError *)=waiter;
        completion(data,response,error);
    }
}
static void CGScheduleOlderRetry(CGOlderPageRetry *job) {
    if(!job)return;
    static const NSTimeInterval backoff[]={15,35,70};
    NSTimeInterval delay=backoff[MIN(job.attempts,2)];
    NSTimeInterval after=CGRetryAfter(job.lastResponse);
    if(after>300) {
        
        CGFinishOlderRetry(job);
        return;
    }
    delay=MAX(delay,after);
    @synchronized([NSURLCache class]) {
        NSTimeInterval now=NSDate.date.timeIntervalSince1970;
        // Global gate means different offsets cannot trigger an immediate
        // retry burst after the server has already told us to slow down.
        delay=MAX(delay,sOldPageRetryGate-now);
        sOldPageRetryGate=now+delay+2;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        @synchronized([NSURLCache class]) {
            if(sOlderPageRetries[job.key]!=job)return;
            job.attempts++;
        }
        NSMutableURLRequest *replay=[job.request mutableCopy];
        [replay setValue:@"1" forHTTPHeaderField:kRetryHeader];
        NSURLSessionConfiguration *configuration=[job.configuration copy];
        configuration.timeoutIntervalForRequest=30;
        // The app invalidates short-lived sessions. Never replay on those.
        NSURLSession *session=nil;
        @try {
            session=[NSURLSession sessionWithConfiguration:configuration];
            [[session dataTaskWithRequest:replay completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
                [session finishTasksAndInvalidate];
                
                // Reuse v52 validation/cache semantics. The marker blocks
                // another retry from being spawned for the owned session.
                CGHistoryPageResult(replay,configuration,data,response,error,
                    ^(NSData *usableData,NSURLResponse *usableResponse,NSError *usableError) {
                        job.lastData=usableData;
                        job.lastResponse=usableResponse;
                        job.lastError=usableError;
                        NSInteger usableStatus=[usableResponse isKindOfClass:NSHTTPURLResponse.class]
                            ?((NSHTTPURLResponse *)usableResponse).statusCode:0;
                        if(!usableError && usableStatus==429 && job.attempts<3) {
                            CGScheduleOlderRetry(job);
                        } else {
                            CGFinishOlderRetry(job);
                        }
                    });
            }] resume];
        } @catch(NSException *ex) {
            if(session)[session invalidateAndCancel];
            job.lastError=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost
                userInfo:@{NSLocalizedDescriptionKey:@"History retry session could not start"}];
            
            CGFinishOlderRetry(job);
        }
    });
}
static BOOL CGEnqueueOlderRetry(NSString *key, NSURLRequest *request,
        NSURLSessionConfiguration *configuration,NSData *data,NSURLResponse *response,
        NSError *error,void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    if(!key || !completion || error || CGOlderOffset(request)<20 ||
       [[request valueForHTTPHeaderField:kRetryHeader] isEqualToString:@"1"])
        return NO;
    CGOlderPageRetry *job=nil; BOOL first=NO;
    @synchronized([NSURLCache class]) {
        if(!sOlderPageRetries)sOlderPageRetries=[NSMutableDictionary dictionary];
        job=sOlderPageRetries[key];
        if(!job) {
            if(sOlderPageRetries.count>=4)return NO; // bounded concurrency
            job=[CGOlderPageRetry new]; job.key=key;job.request=[request copy];
            job.configuration=[configuration copy]?:[NSURLSessionConfiguration defaultSessionConfiguration];
            job.waiters=[NSMutableArray array];job.lastData=data;
            job.lastResponse=response;job.lastError=error;
            sOlderPageRetries[key]=job;first=YES;
        }
        [job.waiters addObject:[completion copy]];
    }
    if(first)CGScheduleOlderRetry(job);
    
    return YES;
}

void CGHistoryPageResult(NSURLRequest *request,NSURLSessionConfiguration *configuration,
    NSData *data,NSURLResponse *response,NSError *error,
    void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
    NSString *key=CGPageKey(request,configuration);
    NSData *fallback=nil;
    if(key && !error && (status==200 || status==429)) {
        @synchronized([NSURLCache class]) {
            NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/ChatGPT551HistoryPages"];
            NSString *path=[directory stringByAppendingPathComponent:[key stringByAppendingString:@".plist"]];
            NSFileManager *fm=NSFileManager.defaultManager;
            NSDictionary *record=[NSDictionary dictionaryWithContentsOfFile:path];
            NSTimeInterval age=NSDate.date.timeIntervalSince1970-[record[@"saved"] doubleValue];
            NSData *cached=record[@"data"];
            if(status==200 && CGValidPage(data) && !CGResponseHeader((NSHTTPURLResponse *)response,kCacheHeader)) {
                [fm createDirectoryAtPath:directory withIntermediateDirectories:YES
                     attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:NULL];
                // Bound cache to 32 pages. Retain exact bytes; do not rewrite JSON.
                NSArray *files=[fm contentsOfDirectoryAtPath:directory error:NULL];
                if(files.count>=32 && ![fm fileExistsAtPath:path]) {
                    NSString *oldest=nil;NSDate *oldestDate=nil;
                    for(NSString *file in files) {
                        NSString *candidate=[directory stringByAppendingPathComponent:file];
                        NSDate *date=[[fm attributesOfItemAtPath:candidate error:NULL] fileModificationDate];
                        if(date && (!oldestDate || [date compare:oldestDate]==NSOrderedAscending)) {oldest=candidate;oldestDate=date;}
                    }
                    if(oldest)[fm removeItemAtPath:oldest error:NULL];
                }
                BOOL saved=[@{@"saved":@(NSDate.date.timeIntervalSince1970),@"data":data} writeToFile:path atomically:YES];
                if(saved)[fm setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:path error:NULL];
                
            } else if(status==429 && age>=0 && age<=kMaxAge &&
                      [cached isKindOfClass:NSData.class] && CGValidPage(cached)) {
                fallback=cached;
            }
        }
    }
    if(fallback) {
        
        NSHTTPURLResponse *cachedResponse=[[NSHTTPURLResponse alloc] initWithURL:request.URL
            statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{
                @"Content-Type":@"application/json",@"Content-Length":[NSString stringWithFormat:@"%lu",(unsigned long)fallback.length],
                @"Cache-Control":@"no-store",kCacheHeader:@"rate-limit-fallback"}];
        completion(fallback,cachedResponse,nil);
    } else {
        if(status==429 && CGEnqueueOlderRetry(key,request,configuration,data,response,error,completion))
            return;
        
        completion(data,response,error);
    }
}
