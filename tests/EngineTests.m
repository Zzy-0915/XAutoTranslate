#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "XGTXEngine.h"
#import "XGTXNativeDisplay.h"
#import "XTranslationRouter.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

void XADLog(const char *category,const char *format,...) {(void)category;(void)format;}
static void Check(BOOL good,NSString *label) {if(!good) {fprintf(stderr,"FAIL %s\n",label.UTF8String);exit(1);}}
static BOOL Wait(BOOL (^condition)(void)) {
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:4];
    while(!condition() && limit.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    return condition();
}

static NSLock *fixtureLock;
static NSMutableDictionary<NSString *,NSNumber *> *counts;
static NSUInteger active,peak;
@interface FixtureProtocol : NSURLProtocol
@property(atomic) BOOL stopped;
@end
@implementation FixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {return [request.URL.host isEqual:@"translate.googleapis.com"];}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {return request;}
- (void)stopLoading {self.stopped=YES;}
- (void)startLoading {
    NSURLComponents *url=[NSURLComponents componentsWithURL:self.request.URL resolvingAgainstBaseURL:NO];
    NSString *q=nil;for(NSURLQueryItem *item in url.queryItems) if([item.name isEqual:@"q"]) q=item.value;
    Check(q.length>0,@"request q exists");
    if([q containsString:@"+"]) Check([url.percentEncodedQuery containsString:@"%2B"],@"literal plus is escaped for Google's form parser");
    [fixtureLock lock];NSUInteger n=counts[q].unsignedIntegerValue+1;counts[q]=@(n);active++;peak=MAX(peak,active);[fixtureLock unlock];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
        [fixtureLock lock];active--;[fixtureLock unlock];
        if(self.stopped) return;
        NSInteger code=200;NSDictionary *headers=@{};NSData *data;
        if([q isEqual:@"RateMe"] && n==1) {code=429;headers=@{@"Retry-After":@"120"};data=[@"rate limited" dataUsingEncoding:NSUTF8StringEncoding];}
        else if([q isEqual:@"BadJSON"] && n==1) data=[@"{}" dataUsingEncoding:NSUTF8StringEncoding];
        else data=[NSJSONSerialization dataWithJSONObject:@[@[@[[@"译" stringByAppendingString:q],q]],NSNull.null,@"en"] options:0 error:NULL];
        NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:code HTTPVersion:@"HTTP/1.1" headerFields:headers];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];
    });
}
@end
static NSUInteger Count(NSString *q) {[fixtureLock lock];NSUInteger n=counts[q].unsignedIntegerValue;[fixtureLock unlock];return n;}
static XGTXEngine *Engine(NSTimeInterval (^clock)(void),NSTimeInterval spacing) {
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.protocolClasses=@[FixtureProtocol.class];
    return [[XGTXEngine alloc] initWithConfiguration:config clock:clock interval:spacing];
}

// Native model factory doubles: no X framework or live network is used by tests.
@interface TFNTwitterCanonicalStatus : NSObject
@property(nonatomic,copy) NSString *originalText;
@property(nonatomic) long long statusID;
- (instancetype)initWithStatusID:(long long)sid cardData:(id)card originalText:(NSString *)text fromUserID:(long long)uid date:(NSDate *)date;
@end
@implementation TFNTwitterCanonicalStatus
- (instancetype)initWithStatusID:(long long)sid cardData:(id)card originalText:(NSString *)text fromUserID:(long long)uid date:(NSDate *)date {
    (void)card;(void)uid;(void)date;if((self=[super init])) {_originalText=text;_statusID=sid;}return self;
}
@end
@interface TFNTwitterStatus : NSObject
@property(nonatomic,strong) TFNTwitterCanonicalStatus *canonicalStatus;
@property(nonatomic) long long statusID,fromUserID;
@property(nonatomic,strong) NSDate *date;
@property(nonatomic,strong) id fromUser;
- (instancetype)initWithCanonicalStatus:(id)status fromUser:(id)user;
@end
@implementation TFNTwitterStatus
- (instancetype)initWithCanonicalStatus:(id)status fromUser:(id)user {
    if((self=[super init])) {_canonicalStatus=status;_fromUser=user;}return self;
}
@end
static NSUInteger factoryCalls;
static id Factory(id proxy,SEL selector,NSUInteger options) {
    (void)selector;factoryCalls++;
    return @{@"text":((TFNTwitterStatus *)proxy).canonicalStatus.originalText,@"options":@(options)};
}
int main(void) {@autoreleasepool {
    fixtureLock=NSLock.new;counts=NSMutableDictionary.new;
    Check(XGTXChinese(@"zh-Hant") && XGTXChinese(@"cmn") && !XGTXChinese(@"ja"),@"Chinese aliases");
    Check(!XGTXParse([@"{}" dataUsingEncoding:NSUTF8StringEncoding]),@"malformed response rejected");
    NSData *good=[NSJSONSerialization dataWithJSONObject:@[@[@[@"一",@"a"],@[@"二",@"b"]],NSNull.null,@"ja"] options:0 error:NULL];
    Check([XGTXParse(good).text isEqual:@"一二"],@"all returned segments are joined");
    NSMutableString *longText=NSMutableString.new;
    for(NSUInteger i=0;i<350;i++) [longText appendString:@"日本語😀 é + & ? # العربية\n"];
    NSArray *chunks=XGTXChunks(longText);Check([[chunks componentsJoinedByString:@""] isEqual:longText],@"Unicode splitting loses no characters");
    for(NSString *chunk in chunks) Check([chunk lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=1000,@"GET payload byte bound");
    XGTXEngine *e=Engine(^NSTimeInterval{return NSDate.timeIntervalSinceReferenceDate;},0);
    __block NSUInteger finishes=0;e.didFinish=^(NSString *key){(void)key;finishes++;};
    NSString *text=@"Hello + & ? # العربية";
    for(NSUInteger i=0;i<100;i++) [e enqueue:@"same" text:text language:@"en"];
    Check(Wait(^BOOL{return [e cached:@"same"]!=nil;}),@"first request completes");
    Check(Count(text)==1 && finishes==1,@"100 duplicate requests coalesce");
    for(NSUInteger i=0;i<1000;i++) [e enqueue:@"same" text:text language:@"en"];
    Check(Count(text)==1,@"1000 revisits never re-request successful post");
    [e enqueue:@"another-id-same-text" text:text language:@"en"];
    Check([e cached:@"another-id-same-text"]!=nil && Count(text)==1,@"segment cache also protects repeated identical content");
    [e enqueue:@"Chinese" text:@"中文" language:@"zh-CN"];Check(Count(@"中文")==0,@"Chinese never sent");
    Check(![XGTXDigest(@"id:1:old") isEqual:XGTXDigest(@"id:1:edited")],@"edited content has a new key");
    [e enqueue:@"long" text:longText language:@"ja"];
    Check(Wait(^BOOL{return [e cached:@"long"]!=nil;}),@"long Unicode post completes via bounded requests");
    Check(peak<=2,@"network concurrency bounded at two");[e invalidate];

    __block NSTimeInterval now=100;
    XGTXEngine *rate=Engine(^NSTimeInterval{return now;},0);
    [rate enqueue:@"rate" text:@"RateMe" language:@"en"];
    Check(Wait(^BOOL{return [rate.statistics[@"throttles"] unsignedIntegerValue]==1;}),@"429 observed");
    [rate enqueue:@"after-rate" text:@"AfterRate" language:@"en"];
    now=219;[rate pump];Check(Count(@"RateMe")==1 && Count(@"AfterRate")==0,@"Retry-After respected for all queued requests");
    now=221;[rate pump];Check(Wait(^BOOL{return [rate cached:@"rate"] && [rate cached:@"after-rate"];}),@"requests resume after cooldown");[rate invalidate];
    now=500;XGTXEngine *bad=Engine(^NSTimeInterval{return now;},0);
    [bad enqueue:@"bad" text:@"BadJSON" language:@"en"];
    Check(Wait(^BOOL{return Count(@"BadJSON")==1 && [bad.statistics[@"active"] unsignedIntegerValue]==0;}),@"bad JSON finishes as failure");
    Check(![bad cached:@"bad"],@"failed reply never poisons success cache");now=506;[bad pump];
    Check(Wait(^BOOL{return [bad cached:@"bad"]!=nil;}),@"failed request can retry and cache success");[bad invalidate];

    now=1000;XGTXEngine *dual=Engine(^NSTimeInterval{return now;},0);
    __block NSUInteger officialStarts=0,dualFinishes=0;
    XTranslationRouter *router=[[XTranslationRouter alloc] initWithEngine:dual clock:^NSTimeInterval{return now;}
        start:^BOOL(id context){(void)context;officialStarts++;return YES;}
        inspect:^XOfficialObservation *(id context){return context;}];
    router.didFinish=^(NSString *key){(void)key;dualFinishes++;};
    XOfficialObservation *first=XOfficialObservation.new;
    [router submit:@"official" text:@"OfficialOnly" language:@"en" context:first];
    for(NSUInteger i=0;i<100;i++) [router submit:@"official" text:@"OfficialOnly" language:@"en" context:first];
    [router tickWithVisibleKeys:[NSSet setWithObject:@"official"]];Check(officialStarts==1,@"official duplicate triggers coalesce");
    XGTXResult *officialText=XGTXResult.new;officialText.text=@"官方译文";officialText.language=@"en";first.result=officialText;
    now=1001;[router tickWithVisibleKeys:[NSSet setWithObject:@"official"]];
    Check([[dual cached:@"official"].text isEqual:@"官方译文"] && Count(@"OfficialOnly")==0 && dualFinishes==1,@"official success enters shared cache without Google");
    XOfficialObservation *fail=XOfficialObservation.new;fail.failed=YES;fail.code=60;
    [router submit:@"fallback" text:@"DualFallback" language:@"en" context:fail];
    [router tickWithVisibleKeys:[NSSet setWithObject:@"fallback"]];
    Check(Wait(^BOOL{return [dual cached:@"fallback"]!=nil;}),@"native failure automatically falls back to GTX");
    Check(officialStarts==1 && Count(@"DualFallback")==1,@"failed native state is not retried");
    XOfficialObservation *later=XOfficialObservation.new;
    [router submit:@"during-open" text:@"DuringOpen" language:@"en" context:later];
    [router tickWithVisibleKeys:[NSSet setWithObject:@"during-open"]];
    Check(Wait(^BOOL{return [dual cached:@"during-open"]!=nil;}),@"new content goes directly to Google during official cooldown");
    Check(officialStarts==1,@"official circuit suppresses repeated failing requests");
    now=1302;
    [router submit:@"probe" text:@"OfficialProbe" language:@"en" context:later];
    XOfficialObservation *second=XOfficialObservation.new;
    [router submit:@"probe-queued" text:@"ProbeQueued" language:@"en" context:second];
    NSSet *both=[NSSet setWithArray:@[@"probe",@"probe-queued"]];
    [router tickWithVisibleKeys:both];Check(officialStarts==2,@"cooldown recovery starts one probe");
    now=1304;[router tickWithVisibleKeys:both];Check(officialStarts==2,@"half-open circuit allows only one pending probe");
    later.result=officialText;[router tickWithVisibleKeys:both];Check(officialStarts==3,@"successful probe restores official priority");
    now=1313;[router tickWithVisibleKeys:both];
    Check(Wait(^BOOL{return [dual cached:@"probe-queued"]!=nil;}),@"8s official timeout falls back automatically");
    NSUInteger requestsBefore=[dual.statistics[@"requests"] unsignedIntegerValue];
    for(NSUInteger i=0;i<1000;i++) [router submit:@"fallback" text:@"DualFallback" language:@"en" context:fail];
    Check([dual.statistics[@"requests"] unsignedIntegerValue]==requestsBefore && officialStarts==3,@"shared successful cache prevents requests on both providers");
    [dual invalidate];

    TFNTwitterStatus *status=TFNTwitterStatus.new;status.statusID=123;status.fromUserID=456;status.date=NSDate.date;
    NSDictionary *display=XGTXNativeDisplay(status,@"A&B <C>",@"en",42,Factory);
    Check([display[@"text"] hasPrefix:@"英语 已翻译\n\n"],@"language status is in native text flow");
    Check([display[@"text"] hasSuffix:@"A&amp;B &lt;C&gt;"] && [display[@"options"] unsignedIntegerValue]==42 && factoryCalls==1,@"native constructor, escaping and original sizing options preserved");
    Check(XGTXNativeDisplay(nil,@"x",@"en",0,Factory)==nil,@"missing source does not create an overlay");
    puts("PASS: parser, Unicode, Chinese exclusion, coalescing, 1000 cache revisits, concurrency, HTTP429 Retry-After, official success, automatic Google fallback, circuit cooldown/probe/recovery, timeout, shared cache, native text model/status/escaping");
    return 0;
}}
