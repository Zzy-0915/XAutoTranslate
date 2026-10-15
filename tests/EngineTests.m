#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "XGTXEngine.h"
#import "XNativeTranslation.h"
#import "XTranslationRouter.h"
#import "XDwellGate.h"
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
        else data=[NSJSONSerialization dataWithJSONObject:@[@[@[([q isEqual:@"Unchanged"] ? q : [@"译" stringByAppendingString:q]),q]],NSNull.null,@"en"] options:0 error:NULL];
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

// Doubles reproduce the native wrapper's original-status delegation.
@interface TFSTwitterEntitySet : NSObject
- (instancetype)initWithURLs:(id)a mentions:(id)b hashtags:(id)c symbols:(id)d timestamps:(id)e;
@end
@implementation TFSTwitterEntitySet
- (instancetype)initWithURLs:(id)a mentions:(id)b hashtags:(id)c symbols:(id)d timestamps:(id)e {(void)a;(void)b;(void)c;(void)d;(void)e;return [super init];}
@end
@interface TFSTwitterTranslation : NSObject
@property(nonatomic,copy) NSString *translation,*sourceLanguage,*destinationLanguage,*translationSource;
@property(nonatomic,strong) id entities;
- (instancetype)initWithTranslation:(NSString *)text previewTranslation:(id)preview entities:(id)entities translationSource:(NSString *)provider localizedSourceLanguage:(NSString *)name sourceLanguage:(NSString *)source destinationLanguage:(NSString *)destination polls:(id)polls translationState:(NSString *)state;
@end
@implementation TFSTwitterTranslation
- (instancetype)initWithTranslation:(NSString *)text previewTranslation:(id)preview entities:(id)entities translationSource:(NSString *)provider localizedSourceLanguage:(NSString *)name sourceLanguage:(NSString *)source destinationLanguage:(NSString *)destination polls:(id)polls translationState:(NSString *)state {
    (void)preview;(void)name;(void)polls;(void)state;
    if((self=[super init])) {_translation=text;_entities=entities;_sourceLanguage=source;_destinationLanguage=destination;_translationSource=provider;}return self;
}
@end
@interface FixtureOriginal : NSObject
@property(nonatomic,copy) NSString *text;
@property(nonatomic,strong) id grokTranslatedPost;
- (NSString *)statusItemViewModelDidUpdateNotificationName;
@end
@implementation FixtureOriginal
- (NSString *)statusItemViewModelDidUpdateNotificationName {return @"FixtureStatusUpdated";}
@end
static BOOL brokenWrapper;
@interface T1TranslatedStatusViewModel : NSObject
@property(nonatomic,strong) TFSTwitterTranslation *translation;
@property(nonatomic,strong) FixtureOriginal *underlyingViewModel;
@property(nonatomic,readonly) NSString *text;
@property(nonatomic,readonly) id representedStatus;
- (instancetype)initWithTranslation:(id)translation forUnderlyingViewModel:(id)model;
@end
@implementation T1TranslatedStatusViewModel
- (instancetype)initWithTranslation:(id)translation forUnderlyingViewModel:(id)model {if((self=[super init])) {_translation=translation;_underlyingViewModel=model;}return self;}
- (NSString *)text {return brokenWrapper ? self.underlyingViewModel.text : self.translation.translation;}
- (id)representedStatus {return self.underlyingViewModel;}
@end
@interface T1PostTranslationInfo : NSObject
@property(nonatomic) NSInteger state;
@property(nonatomic,strong) id originalStatus,translatedStatus,translationError;
- (instancetype)initWithFixtureModel:(id)model;
@end
static NSUInteger forbiddenInfoInitializers,factoryCalls;
@implementation T1PostTranslationInfo
- (instancetype)init {forbiddenInfoInitializers++;[NSException raise:@"UnavailableNativeInitializer" format:@"X 12.33 default init is not supported"];return nil;}
- (instancetype)initWithFixtureModel:(id)model {if((self=[super init])) {_originalStatus=model;_state=0;}return self;}
@end
@interface FixtureHelper : NSObject
@property(nonatomic,strong) NSMapTable *infos;
- (id)getInfoFor:(id)model;
- (id)getOrCreateInfoFor:(id)model;
- (void)setInfo:(id)info for:(id)model;
@end
@implementation FixtureHelper
- (instancetype)init {if((self=[super init])) _infos=NSMapTable.strongToStrongObjectsMapTable;return self;}
- (id)getInfoFor:(id)model {return [self.infos objectForKey:model];}
- (id)getOrCreateInfoFor:(id)model {factoryCalls++;id info=[self getInfoFor:model];if(!info) {info=[[T1PostTranslationInfo alloc] initWithFixtureModel:model];[self setInfo:info for:model];}return info;}
- (void)setInfo:(id)info for:(id)model {[self.infos setObject:info forKey:model];}
@end
@interface T1TranslationProvider : NSObject
@property(nonatomic,copy) NSString *translationSource;
+ (id)googleTranslationProvider;
@end
@implementation T1TranslationProvider
+ (id)googleTranslationProvider {T1TranslationProvider *provider=self.new;provider.translationSource=@"Google";return provider;}
@end

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
    Check(peak<=1,@"Google network concurrency bounded at one");[e invalidate];

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
    Check(![dual cached:@"probe-queued"] && Count(@"ProbeQueued")==0,@"a slow official request does not unlock Google");
    now=1335;[router tickWithVisibleKeys:both];
    Check(![dual cached:@"probe-queued"] && Count(@"ProbeQueued")==0 && [router.statistics[@"deferrals"] unsignedIntegerValue]==1,@"30s wait defers instead of manufacturing official failure");
    NSUInteger requestsBefore=[dual.statistics[@"requests"] unsignedIntegerValue];
    for(NSUInteger i=0;i<1000;i++) [router submit:@"fallback" text:@"DualFallback" language:@"en" context:fail];
    Check([dual.statistics[@"requests"] unsignedIntegerValue]==requestsBefore && officialStarts==3,@"shared successful cache prevents requests on both providers");
    [dual invalidate];

    FixtureOriginal *original=FixtureOriginal.new;original.text=@"Hello original";
    FixtureHelper *helper=FixtureHelper.new;
    XGTXResult *google=XGTXResult.new;google.text=@"你好 & <你好>";google.language=@"en";
    Check(XATNativePublish(original,helper,google,original.text)==2,@"Google result is published through native translation wrapper");
    Check(forbiddenInfoInitializers==0 && factoryCalls==1,@"crash regression: use native helper factory, never T1PostTranslationInfo.init");
    T1PostTranslationInfo *info=[helper getInfoFor:original];T1TranslatedStatusViewModel *wrapper=info.translatedStatus;
    Check([wrapper.text isEqual:google.text] && [((FixtureOriginal *)wrapper.representedStatus).text isEqual:original.text],@"native wrapper shows translation while representedStatus preserves original");
    Check(![wrapper.text containsString:@"已翻译"] && [wrapper.translation.translationSource isEqual:@"Google"],@"no custom hint in text; native provider attribution preserved");
    XGTXResult *read=XATNativeResult(original,info,original.text,@"en");
    Check([read.text isEqual:google.text] && read.nativeTranslation==wrapper.translation,@"regression: read translation object instead of unwrapping representedStatus");
    Check(XATNativePublish(original,helper,google,original.text)==1,@"native publication is idempotent");
    Check(XATNativeDisplayOverride(original,info,google,original.text,@"en",0)==1 && XATNativeDisplayOverride(original,info,google,original.text,@"en",1)==1 && XATNativeDisplayOverride(original,info,google,original.text,@"en",2)==0,@"validated native translation enables both list body and official button without duplicate auto body");
    info.state=0;Check(XATNativePublish(original,helper,google,original.text)==1 && info.state==0 && XATNativeDisplayOverride(original,info,google,original.text,@"en",0)==0,@"native show-original choice is retained without a network request");info.state=3;
    __block NSNotification *observed=nil;
    id observer=[NSNotificationCenter.defaultCenter addObserverForName:@"FixtureStatusUpdated" object:original queue:nil usingBlock:^(NSNotification *note){observed=note;}];
    Check(XATNativeNotify(original,@"dynamic",@"animated") && [observed.userInfo[@"dynamic"] boolValue] && ![observed.userInfo[@"animated"] boolValue],@"native refresh carries required dynamic-content flag");
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    Check(!XATNativeNotify(original,nil,@"animated"),@"missing native notification key fails explicitly");
    wrapper.translation.translation=original.text;
    Check(!XATNativeResult(original,info,original.text,@"en"),@"unchanged original is never accepted as translated");
    Check(XATNativeDisplayOverride(original,info,nil,original.text,@"en",0)==0 && XATNativeDisplayOverride(original,info,nil,original.text,@"en",1)==0,@"unchanged original cannot enable translated body or hint");
    wrapper.translation.translation=google.text;wrapper.translation.destinationLanguage=@"en";
    Check(!XATNativeResult(original,info,original.text,@"en"),@"non-Chinese target is rejected");
    wrapper.translation.destinationLanguage=@"zh-CN";
    FixtureOriginal *broken=FixtureOriginal.new;broken.text=@"Broken original";brokenWrapper=YES;
    Check(XATNativePublish(broken,helper,google,broken.text)==0 && ![helper getInfoFor:broken],@"failed native body verification never publishes translated state");brokenWrapper=NO;
    Check(!XGTXTranslationChanged(@"HELLO \n original",@"Hello original"),@"whitespace and case alone do not count as translation");
    XGTXEngine *unchanged=Engine(^NSTimeInterval{return NSDate.timeIntervalSinceReferenceDate;},0);
    [unchanged enqueue:@"unchanged" text:@"Unchanged" language:@"en"];
    Check(Wait(^BOOL{return Count(@"Unchanged")==1 && [unchanged.statistics[@"active"] unsignedIntegerValue]==0;}),@"unchanged response finishes");
    Check(![unchanged cached:@"unchanged"],@"unchanged Google reply is excluded from success cache");[unchanged invalidate];

    now=4000;XGTXEngine *guarded=Engine(^NSTimeInterval{return now;},0);
    XTranslationRouter *guard=[[XTranslationRouter alloc] initWithEngine:guarded clock:^NSTimeInterval{return now;} start:^BOOL(id context){(void)context;return YES;} inspect:^XOfficialObservation *(id context){return context;}];
    XOfficialObservation *wrong=XOfficialObservation.new;XGTXResult *wrongResult=XGTXResult.new;wrongResult.text=@"OriginalIsNotTranslated";wrongResult.language=@"en";wrong.result=wrongResult;
    [guard submit:@"wrong" text:wrongResult.text language:@"en" context:wrong];[guard tickWithVisibleKeys:[NSSet setWithObject:@"wrong"]];
    Check(![guarded cached:@"wrong"] && Count(@"OriginalIsNotTranslated")==0 && [guard.statistics[@"officialSuccesses"] unsignedIntegerValue]==0,@"unchanged response neither poisons cache nor activates Google without native failure");[guarded invalidate];
    // Moving, recycled and offscreen views cannot satisfy the dwell policy.
    now=5000;XDwellGate *gate=[[XDwellGate alloc] initWithClock:^NSTimeInterval{return now;} delay:1.0];NSObject *view=NSObject.new;
    for(NSUInteger i=0;i<100;i++) {
        now+=0.02;
        Check(![gate eligible:view key:[NSString stringWithFormat:@"passed-%lu",(unsigned long)i] visible:YES stationary:NO position:100],@"fast flings never qualify");
    }
    Check(![gate eligible:view key:@"read" visible:YES stationary:YES position:100],@"dwell begins when motion stops");
    now+=0.99;Check(![gate eligible:view key:@"read" visible:YES stationary:YES position:100],@"no premature request");
    now+=0.02;Check([gate eligible:view key:@"read" visible:YES stationary:YES position:100],@"stable one-second view qualifies");
    Check(![gate eligible:view key:@"recycled" visible:YES stationary:YES position:100],@"reused cell resets dwell");
    now+=1.1;Check(![gate eligible:view key:@"recycled" visible:YES stationary:YES position:110],@"programmatic position change resets dwell");
    now+=1.1;Check([gate eligible:view key:@"recycled" visible:YES stationary:YES position:110],@"stationary programmatic scroll end can qualify");
    Check(![gate eligible:view key:@"recycled" visible:NO stationary:YES position:110],@"offscreen resets dwell");
    now+=2;Check(![gate eligible:view key:@"recycled" visible:YES stationary:YES position:110],@"returning view must dwell anew");
    __weak NSObject *weakView;
    @autoreleasepool {NSObject *temporary=NSObject.new;weakView=temporary;[gate eligible:temporary key:@"weak" visible:YES stationary:YES position:0];}
    Check(!weakView,@"dwell metadata does not retain offscreen views");

    XGTXEngine *paused=Engine(^NSTimeInterval{return NSDate.timeIntervalSinceReferenceDate;},0);
    [paused setEligibleKeys:NSSet.set];[paused enqueue:@"denied" text:@"MovingDenied" language:@"en"];
    Check(Count(@"MovingDenied")==0,@"paused engine rejects new network jobs");
    [paused setEligibleKeys:[NSSet setWithArray:@[@"keep",@"drop"]]];
    [paused enqueue:@"keep" text:@"AlreadyReading" language:@"en"];
    [paused enqueue:@"drop" text:@"OffscreenQueued" language:@"en"];
    [paused setEligibleKeys:NSSet.set];
    Check(Wait(^BOOL{return [paused cached:@"keep"]!=nil;}),@"already-started result may complete into cache");
    Check(Count(@"OffscreenQueued")==0,@"completion pump never starts a queued item after scrolling resumes");[paused invalidate];
    XGTXEngine *live=Engine(^NSTimeInterval{return NSDate.timeIntervalSinceReferenceDate;},0);
    [live setEligibleKeys:[NSSet setWithObject:@"stale-eligible"]];live.admitRequest=^BOOL(NSString *key){(void)key;return NO;};
    [live enqueue:@"stale-eligible" text:@"MovedBetweenTicks" language:@"en"];
    Check(Count(@"MovedBetweenTicks")==0 && [live.statistics[@"requests"] unsignedIntegerValue]==0,@"live start guard closes the motion/background race between polling ticks");[live invalidate];

    now=6000;XGTXEngine *strict=Engine(^NSTimeInterval{return now;},0);__block NSUInteger starts=0;
    XTranslationRouter *policy=[[XTranslationRouter alloc] initWithEngine:strict clock:^NSTimeInterval{return now;} start:^BOOL(id context){(void)context;starts++;return YES;} inspect:^XOfficialObservation *(id context){return context;}];
    XOfficialObservation *pending=XOfficialObservation.new;
    [policy submit:@"passed" text:@"FastPassed" language:@"en" context:pending];[policy tickWithVisibleKeys:NSSet.set];
    Check(starts==0 && Count(@"FastPassed")==0,@"ineligible queue is removed before either provider starts");
    [policy submit:@"read" text:@"StrictReading" language:@"en" context:pending];[policy tickWithVisibleKeys:[NSSet setWithObject:@"read"]];
    Check(starts==1 && Count(@"StrictReading")==0,@"stable post starts official only");
    now=6009;[policy tickWithVisibleKeys:[NSSet setWithObject:@"read"]];Check(Count(@"StrictReading")==0,@"eight-second delay is not a native failure");
    pending.failed=YES;pending.code=60;[policy tickWithVisibleKeys:[NSSet setWithObject:@"read"]];
    Check(Wait(^BOOL{return [strict cached:@"read"]!=nil;}),@"confirmed native failure enables Google automatically");
    XOfficialObservation *next=XOfficialObservation.new;
    [policy submit:@"cooldown-read" text:@"StrictCooldownRead" language:@"en" context:next];
    Check(Count(@"StrictCooldownRead")==0,@"submit itself never issues network even after official failure");
    [policy tickWithVisibleKeys:NSSet.set];Check(Count(@"StrictCooldownRead")==0,@"cooldown does not translate posts passed during motion");[strict invalidate];
    XGTXEngine *missing=Engine(^NSTimeInterval{return now;},0);
    XTranslationRouter *unavailable=[[XTranslationRouter alloc] initWithEngine:missing clock:^NSTimeInterval{return now;} start:^BOOL(id context){(void)context;return NO;} inspect:^XOfficialObservation *(id context){return context;}];
    [unavailable submit:@"no-route" text:@"NativeRouteMissing" language:@"en" context:next];[unavailable tickWithVisibleKeys:[NSSet setWithObject:@"no-route"]];
    Check(Count(@"NativeRouteMissing")==0 && [unavailable.statistics[@"fallbacks"] unsignedIntegerValue]==0,@"missing native route never impersonates official failure");[missing invalidate];
    Check(forbiddenInfoInitializers==0,@"all publications avoid the unavailable native initializer");
    puts("PASS: crash factory regression, stable dwell, fast scrolling/offscreen/reuse, serial requests, paused completion pump, Google only after native failure, no timeout fallback, native translation UI, successful cache and retry controls");

    return 0;
}}
