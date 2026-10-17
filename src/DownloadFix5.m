#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL Trusted(NSURL *u) {
 return [u.scheme.lowercaseString isEqual:@"https"] && (!u.port || u.port.integerValue==443) &&
 [@[@"chatgpt.com",@"chat.openai.com",@"api.openai.com"] containsObject:u.host.lowercaseString];
}
static void Log(NSString *s) {
 NSString *p=[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"ChatGPTRepairDownloadFixTest.log"];
 @synchronized([NSURLSession class]) {
  NSData *d=[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
  if (![[NSFileManager defaultManager] fileExistsAtPath:p]) [d writeToFile:p atomically:YES];
  else { NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:p]; [h seekToEndOfFile]; [h writeData:d]; [h closeFile]; }
 }
}
static NSError *Failure(NSInteger code) {
 return [NSError errorWithDomain:@"ChatGPTRepairDownload" code:code userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Download failed (HTTP %ld). No error file was saved.",(long)code]}];
}
@interface CGRDownloadRedirectGuard : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic,copy) NSString *host;
@end
@implementation CGRDownloadRedirectGuard
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
 // Fail closed: do not forward account headers or cookies to another origin.
 completionHandler(Trusted(request.URL) && [request.URL.host.lowercaseString isEqual:self.host] ? request : nil);
}
@end
@interface NSURLSession (CGRDownload5)
- (NSURLSessionDataTask *)cgr_download5:(NSURLRequest *)request completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))done;
@end
@implementation NSURLSession (CGRDownload5)
- (NSURLSessionDataTask *)cgr_download5:(NSURLRequest *)request completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))done {
 if (!done || !Trusted(request.URL) || ![request.URL.path hasSuffix:@"/interpreter/download"])
  return [self cgr_download5:request completionHandler:done];
 NSURLRequest *original=[request copy];
 NSURLSessionConfiguration *configuration=[self.configuration copy];
 return [self cgr_download5:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
  NSInteger status=[response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
  if(error || status<200 || status>=300) { done(nil,response,error?:Failure(status)); return; }
  id json=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  NSString *link=[json isKindOfClass:[NSDictionary class]] ? json[@"download_url"] : nil;
  if (![link isKindOfClass:[NSString class]]) { done(data,response,nil); return; }
  NSURL *url=[NSURL URLWithString:link relativeToURL:original.URL].absoluteURL;
  if(!Trusted(url) || ![url.path isEqual:@"/backend-api/estuary/content"]) {
   Log(@"fix5 unsupported file destination; stopped"); done(nil,response,Failure(-2)); return;
  }
  NSMutableURLRequest *next=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:120];
  // Copy only credentials already supplied by this app, never browser-exported values.
  for(NSString *key in @[@"Authorization",@"ChatGPT-Account-Id",@"originator",@"User-Agent"]) {
   NSString *value=[original valueForHTTPHeaderField:key];
   if(!value.length) for(id k in configuration.HTTPAdditionalHeaders) if([[k description] caseInsensitiveCompare:key]==NSOrderedSame) value=[configuration.HTTPAdditionalHeaders[k] description];
   if(value.length) [next setValue:value forHTTPHeaderField:key];
  }
  // Explicit Cookie is scoped to the original host. Cookie storage applies domain rules.
  if([url.host.lowercaseString isEqual:original.URL.host.lowercaseString]) {
   NSString *cookie=[original valueForHTTPHeaderField:@"Cookie"];
   if(cookie.length) [next setValue:cookie forHTTPHeaderField:@"Cookie"];
  }
  [next setValue:@"*/*" forHTTPHeaderField:@"Accept"];
  [next setValue:@"https://chatgpt.com/" forHTTPHeaderField:@"Referer"];
  configuration.HTTPAdditionalHeaders=@{};
  configuration.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
  CGRDownloadRedirectGuard *guard=[CGRDownloadRedirectGuard new]; guard.host=url.host.lowercaseString;
  NSURLSession *transfer=[NSURLSession sessionWithConfiguration:configuration delegate:guard delegateQueue:nil];
  Log([NSString stringWithFormat:@"fix5 resolver=%ld auth=%d account=%d",(long)status,[next valueForHTTPHeaderField:@"Authorization"].length>0,[next valueForHTTPHeaderField:@"ChatGPT-Account-Id"].length>0]);
  [[transfer dataTaskWithRequest:next completionHandler:^(NSData *bytes,NSURLResponse *reply,NSError *err) {
   NSInteger code=[reply isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)reply statusCode] : 0;
   Log([NSString stringWithFormat:@"fix5 file status=%ld bytes=%lu mime=%@ error=%ld",(long)code,(unsigned long)bytes.length,reply.MIMEType?:@"",(long)err.code]);
   if(err || code<200 || code>=300) done(nil,reply,err?:Failure(code));
   else done(bytes,reply,nil);
   [transfer finishTasksAndInvalidate];
  }] resume];
 }];
}
@end
__attribute__((constructor)) static void StartDownload5(void) {
 @autoreleasepool {
  if(![[NSBundle mainBundle].bundleIdentifier isEqual:@"com.openai.chat"]) return;
  Method a=class_getInstanceMethod([NSURLSession class],@selector(dataTaskWithRequest:completionHandler:));
  Method b=class_getInstanceMethod([NSURLSession class],@selector(cgr_download5:completionHandler:));
  if(a&&b) { method_exchangeImplementations(a,b); Log(@"=== ChatGPTRepair download fix5 auth test launch ==="); }
 }
}
