#import "XGTXEngine.h"
#include "XDiagnostics.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>
#include <stdio.h>

@implementation XGTXResult
@end

NSString *XGTXDigest(NSString *text) {
    NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,hash);
    char out[CC_SHA256_DIGEST_LENGTH*2+1];
    for(NSUInteger i=0;i<sizeof(hash);i++) snprintf(out+2*i,3,"%02x",hash[i]);
    return [NSString stringWithUTF8String:out];
}
BOOL XGTXChinese(NSString *language) {
    NSString *code=language.lowercaseString;
    for(NSString *base in @[@"zh",@"zho",@"chi",@"cmn",@"yue",@"wuu",@"nan",@"hak",@"gan",@"hsn"])
        if([code isEqual:base] || [code hasPrefix:[base stringByAppendingString:@"-"]] || [code hasPrefix:[base stringByAppendingString:@"_"]]) return YES;
    return NO;
}
XGTXResult *XGTXParse(NSData *data) {
    id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if(![root isKindOfClass:NSArray.class] || [root count]<1 || ![root[0] isKindOfClass:NSArray.class]) return nil;
    NSMutableString *text=NSMutableString.new;
    for(id part in root[0]) {
        if(![part isKindOfClass:NSArray.class] || [part count]<1 || ![part[0] isKindOfClass:NSString.class]) return nil;
        [text appendString:part[0]];
    }
    if(!text.length) return nil;
    XGTXResult *result=XGTXResult.new;result.text=text;
    result.language=[root count]>2 && [root[2] isKindOfClass:NSString.class] ? root[2] : @"und";
    if(result.language.length>24 || [result.language rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"] invertedSet]].location!=NSNotFound) result.language=@"und";
    return result;
}
NSArray<NSString *> *XGTXChunks(NSString *text) {
    NSMutableArray *parts=NSMutableArray.new;
    NSMutableString *current=NSMutableString.new;
    __block NSUInteger bytes=0;
    [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s,NSRange range,NSRange enclosing,BOOL *stop) {
        (void)range;(void)enclosing;(void)stop;
        NSUInteger n=[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if(bytes+n>1000 && current.length) { [parts addObject:current.copy];[current setString:@""];bytes=0; }
        [current appendString:s];bytes+=n;
    }];
    if(current.length) [parts addObject:current.copy];
    return parts;
}

@interface XGTXJob : NSObject
@property(nonatomic,copy) NSString *key,*language,*token;
@property(nonatomic,copy) NSArray<NSString *> *chunks;
@property(nonatomic,strong) NSMutableArray<NSString *> *parts;
@property(nonatomic,strong,nullable) NSURLSessionDataTask *task;
@property(nonatomic) NSUInteger index,failures;
@property(nonatomic) NSTimeInterval readyAt;
@end
@implementation XGTXJob
@end

@interface XGTXEngine ()
@property(nonatomic,strong) NSLock *lock;
@property(nonatomic,strong) NSMutableDictionary<NSString *,XGTXResult *> *success,*segments;
@property(nonatomic,strong) NSMutableDictionary<NSString *,XGTXJob *> *jobs;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *failedUntil;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *queue;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,copy) NSTimeInterval (^clock)(void);
@property(nonatomic) NSTimeInterval interval,nextStart,cooldown,wakeAt;
@property(nonatomic) NSUInteger active,requests,hits,joined,throttles,consecutiveThrottles,wakeGeneration;
@property(nonatomic) BOOL invalidated,wakeScheduled;
@end
@implementation XGTXEngine
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration clock:(NSTimeInterval (^)(void))clock interval:(NSTimeInterval)interval {
    if((self=[super init])) {
        _lock=NSLock.new;_success=NSMutableDictionary.new;_segments=NSMutableDictionary.new;
        _jobs=NSMutableDictionary.new;_failedUntil=NSMutableDictionary.new;_queue=NSMutableOrderedSet.new;
        _clock=[clock copy];_interval=MAX(0,interval);
        configuration.URLCache=nil;configuration.HTTPCookieStorage=nil;configuration.HTTPShouldSetCookies=NO;
        configuration.URLCredentialStorage=nil;configuration.connectionProxyDictionary=@{};
        configuration.timeoutIntervalForRequest=20;configuration.timeoutIntervalForResource=30;
        _session=[NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    }
    return self;
}
- (XGTXResult *)cached:(NSString *)key {
    [self.lock lock];XGTXResult *result=self.success[key];if(result) self.hits++;[self.lock unlock];return result;
}
- (void)storeSuccess:(NSString *)key text:(NSString *)text language:(NSString *)language {
    NSAssert(NSThread.isMainThread,@"main-thread scheduler");
    if(!text.length) return;
    XGTXResult *result=XGTXResult.new;result.text=text;result.language=language;
    [self.lock lock];BOOL fresh=self.success[key]==nil;
    if(fresh) self.success[key]=result;
    [self.lock unlock];
    if(fresh && self.didFinish) self.didFinish(key);
}
- (void)enqueue:(NSString *)key text:(NSString *)text language:(NSString *)language {
    NSAssert(NSThread.isMainThread,@"main-thread scheduler");
    if(self.invalidated || !text.length || XGTXChinese(language) || [self cached:key]) return;
    if(self.jobs[key]) {self.joined++;return;}
    if(self.failedUntil[key].doubleValue>self.clock()) return;
    if(self.jobs.count>=64) {XADLog("GTX","queue full; visible item deferred");return;}
    XGTXJob *job=XGTXJob.new;job.key=key;job.language=language;job.token=@"";
    job.chunks=XGTXChunks(text);job.parts=NSMutableArray.new;
    self.jobs[key]=job;[self.queue addObject:key];[self pump];
}
- (void)wakeAfter:(NSTimeInterval)delay {
    if(self.invalidated) return;
    NSTimeInterval fire=self.clock()+MAX(0.01,delay);
    if(self.wakeScheduled && self.wakeAt<=fire) return;
    self.wakeScheduled=YES;
    self.wakeAt=fire;NSUInteger generation=++self.wakeGeneration;
    __weak XGTXEngine *weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(MAX(0.01,delay)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        XGTXEngine *s=weak;if(!s || s.wakeGeneration!=generation) return;s.wakeScheduled=NO;[s pump];
    });
}
- (void)keepQueuedKeys:(NSSet<NSString *> *)visibleKeys {
    NSAssert(NSThread.isMainThread,@"main-thread scheduler");
    for(NSString *key in self.queue.array) if(![visibleKeys containsObject:key]) {
        XGTXJob *job=self.jobs[key];if(job.task) continue;
        [self.queue removeObject:key];[self.jobs removeObjectForKey:key];
    }
}
- (void)complete:(XGTXJob *)job {
    [self storeSuccess:job.key text:[job.parts componentsJoinedByString:@""] language:job.language];
    [self.jobs removeObjectForKey:job.key];[self.failedUntil removeObjectForKey:job.key];
    XADLog("GTX","success key=%.12s chunks=%lu cacheEntries=%lu",job.key.UTF8String,(unsigned long)job.chunks.count,(unsigned long)self.success.count);
}
- (void)pump {
    NSAssert(NSThread.isMainThread,@"main-thread scheduler");
    if(self.invalidated) return;
    while(self.active<2 && self.queue.count) {
        NSTimeInterval now=self.clock();
        NSTimeInterval wait=MAX(self.nextStart,self.cooldown)-now;
        if(wait>0) {[self wakeAfter:wait];return;}
        XGTXJob *job=nil;NSTimeInterval earliest=HUGE_VAL;
        for(NSString *key in self.queue.array) {
            XGTXJob *candidate=self.jobs[key];
            if(candidate.readyAt<=now) {job=candidate;break;}
            earliest=MIN(earliest,candidate.readyAt);
        }
        if(!job) {[self wakeAfter:earliest-now];return;}
        [self.queue removeObject:job.key];
        while(job.index<job.chunks.count) {
            XGTXResult *saved=self.segments[XGTXDigest(job.chunks[job.index])];
            if(!saved) break;
            [job.parts addObject:saved.text];if([job.language isEqual:@"und"] && ![saved.language isEqual:@"und"]) job.language=saved.language;job.index++;
        }
        if(job.index==job.chunks.count) {[self complete:job];continue;}
        NSURLComponents *url=[NSURLComponents componentsWithString:@"https://translate.googleapis.com/translate_a/single"];
        url.queryItems=@[[NSURLQueryItem queryItemWithName:@"client" value:@"gtx"],
            [NSURLQueryItem queryItemWithName:@"sl" value:@"auto"],[NSURLQueryItem queryItemWithName:@"tl" value:@"zh-CN"],
            [NSURLQueryItem queryItemWithName:@"dt" value:@"t"],[NSURLQueryItem queryItemWithName:@"q" value:job.chunks[job.index]]];
        url.percentEncodedQuery=[url.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        NSString *token=NSUUID.UUID.UUIDString;job.token=token;self.active++;self.requests++;self.nextStart=now+self.interval;
        __weak XGTXEngine *weak=self;
        job.task=[self.session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
            dispatch_async(dispatch_get_main_queue(),^{
                XGTXEngine *s=weak;if(!s) return;
                [s received:job token:token data:data response:response error:error];
            });
        }];
        XADLog("GTX","request key=%.12s chunk=%lu/%lu active=%lu host=translate.googleapis.com",job.key.UTF8String,(unsigned long)job.index+1,(unsigned long)job.chunks.count,(unsigned long)self.active);
        [job.task resume];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,35*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            XGTXEngine *s=weak;
            if(s && job.task && [job.token isEqual:token]) {
                [job.task cancel];
                [s received:job token:token data:nil response:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
            }
        });
    }
}
- (NSTimeInterval)retryAfter:(NSHTTPURLResponse *)response {
    NSString *header=[response valueForHTTPHeaderField:@"Retry-After"];
    if(!header.length) return 0;
    NSScanner *scanner=[NSScanner scannerWithString:header];double seconds=0;
    if([scanner scanDouble:&seconds] && scanner.isAtEnd && isfinite(seconds)) return MAX(0,seconds);
    NSDateFormatter *formatter=NSDateFormatter.new;formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];formatter.dateFormat=@"EEE, dd MMM yyyy HH:mm:ss zzz";
    return MAX(0,[[formatter dateFromString:header] timeIntervalSinceNow]);
}
- (void)received:(XGTXJob *)job token:(NSString *)token data:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    if(self.invalidated || !job.task || ![job.token isEqual:token]) return;
    job.task=nil;job.token=@"";self.active--;
    NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class] ? (id)response : nil;
    XGTXResult *result=!error && http.statusCode==200 && data ? XGTXParse(data) : nil;
    if(result) {
        self.consecutiveThrottles=0;job.failures=0;
        self.segments[XGTXDigest(job.chunks[job.index])]=result;
        [job.parts addObject:result.text];job.index++;
        if([job.language isEqual:@"und"] && ![result.language isEqual:@"und"]) job.language=result.language;
        if(job.index==job.chunks.count) [self complete:job];
        else [self.queue addObject:job.key];
    } else {
        job.failures++;
        NSTimeInterval delay=MIN(60,5*pow(2,job.failures-1));
        if(http.statusCode==429 || http.statusCode==503) {
            self.throttles++;self.consecutiveThrottles++;
            delay=MAX([self retryAfter:http],MIN(300,15*pow(2,MIN(self.consecutiveThrottles-1,5))));
            self.cooldown=MAX(self.cooldown,self.clock()+delay);
        }
        XADLog("GTX","failure key=%.12s http=%ld errorDomain=%s errorCode=%ld retry=%lu wait=%.1f",job.key.UTF8String,(long)http.statusCode,error.domain.UTF8String ?: "none",(long)error.code,(unsigned long)job.failures,delay);
        if(job.failures<=2) {job.readyAt=self.clock()+delay;[self.queue addObject:job.key];}
        else {self.failedUntil[job.key]=@(self.clock()+60);[self.jobs removeObjectForKey:job.key];}
    }
    [self pump];
}
- (NSDictionary<NSString *,NSNumber *> *)statistics {
    [self.lock lock];NSUInteger count=self.success.count,hits=self.hits;[self.lock unlock];
    return @{@"cache":@(count),@"hits":@(hits),@"requests":@(self.requests),@"joined":@(self.joined),
        @"active":@(self.active),@"queued":@(self.queue.count),@"throttles":@(self.throttles),@"cooldown":@(MAX(0,self.cooldown-self.clock()))};
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session;(void)task;(void)response;
    completionHandler([request.URL.host.lowercaseString isEqual:@"translate.googleapis.com"] && [request.URL.scheme isEqual:@"https"] ? request : nil);
}
- (void)invalidate {
    self.invalidated=YES;[self.session invalidateAndCancel];[self.jobs removeAllObjects];[self.queue removeAllObjects];self.didFinish=nil;
}
@end
