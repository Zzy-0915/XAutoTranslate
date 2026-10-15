#import "XTranslationRouter.h"
#include "XDiagnostics.h"
#include <math.h>
@implementation XOfficialObservation
@end
@interface XRouteJob : NSObject
@property(nonatomic,copy) NSString *key,*text,*language;
@property(nonatomic,strong) id context;
@property(nonatomic) BOOL started;
@property(nonatomic) NSTimeInterval began;
@end
@implementation XRouteJob
@end
@interface XTranslationRouter ()
@property(nonatomic,strong) XGTXEngine *engine;
@property(nonatomic,strong) NSMutableDictionary<NSString *,XRouteJob *> *jobs;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *order;
@property(nonatomic,strong) NSMutableSet<NSString *> *googleKeys;
@property(nonatomic,copy) NSTimeInterval (^clock)(void);
@property(nonatomic,copy) BOOL (^start)(id);
@property(nonatomic,copy) XOfficialObservation *(^inspect)(id);
@property(nonatomic) NSTimeInterval officialUntil,nextStart;
@property(nonatomic) NSUInteger failures,officialStarts,officialSuccesses,fallbacks;
@end
@implementation XTranslationRouter
- (instancetype)initWithEngine:(XGTXEngine *)engine clock:(NSTimeInterval (^)(void))clock start:(BOOL (^)(id))start inspect:(XOfficialObservation *(^)(id))inspect {
    if((self=[super init])) {
        _engine=engine;_clock=[clock copy];_start=[start copy];_inspect=[inspect copy];
        _jobs=NSMutableDictionary.new;_order=NSMutableOrderedSet.new;_googleKeys=NSMutableSet.new;
        __weak XTranslationRouter *weak=self;
        engine.didFinish=^(NSString *key){
            XTranslationRouter *s=weak;if(!s) return;
            [s.jobs removeObjectForKey:key];[s.order removeObject:key];[s.googleKeys removeObject:key];
            if(s.didFinish) s.didFinish(key);
        };
    }
    return self;
}
- (void)google:(XRouteJob *)job reason:(const char *)reason {
    (void)reason;
    [self.jobs removeObjectForKey:job.key];[self.order removeObject:job.key];
    if(![self.googleKeys containsObject:job.key]) {
        self.fallbacks++;[self.googleKeys addObject:job.key];
        XADLog("ROUTER","fallback key=%.12s from=official to=GoogleGTX reason=%s",job.key.UTF8String,reason);
    }
    [self.engine enqueue:job.key text:job.text language:job.language];
}
- (void)officialFailed:(XRouteJob *)job code:(NSInteger)code reason:(const char *)reason {
    (void)code;
    self.failures++;
    NSTimeInterval delay=MIN(900,300*pow(2,MIN(self.failures-1,2)));
    self.officialUntil=MAX(self.officialUntil,self.clock()+delay);
    XADLog("ROUTER","official failure code=%ld circuit=OPEN wait=%.0f reason=%s",(long)code,delay,reason);
    [self google:job reason:reason];
}
- (BOOL)accept:(XOfficialObservation *)observation job:(XRouteJob *)job {
    if(!observation.result.text.length) return NO;
    self.officialSuccesses++;
    if(self.clock()>=self.officialUntil) {self.failures=0;self.officialUntil=0;}
    XADLog("ROUTER","official success key=%.12s circuit=CLOSED",job.key.UTF8String);
    [self.engine storeSuccess:job.key text:observation.result.text language:job.language];
    return YES;
}
- (void)submit:(NSString *)key text:(NSString *)text language:(NSString *)language context:(id)context {
    NSAssert(NSThread.isMainThread,@"main-thread router");
    if(!text.length || XGTXChinese(language) || [self.engine cached:key]) return;
    if([self.googleKeys containsObject:key]) {[self.engine enqueue:key text:text language:language];return;}
    if(self.jobs[key]) {if(!self.jobs[key].started) self.jobs[key].context=context;return;}
    XRouteJob *job=XRouteJob.new;job.key=key;job.text=text;job.language=language;job.context=context;
    if(self.clock()<self.officialUntil) {[self google:job reason:"official cooldown"];return;}
    if(self.jobs.count>=64) {[self google:job reason:"official queue full"];return;}
    self.jobs[key]=job;[self.order addObject:key];
}
- (void)tickWithVisibleKeys:(NSSet<NSString *> *)visible {
    NSAssert(NSThread.isMainThread,@"main-thread router");
    NSTimeInterval now=self.clock();
    for(NSString *key in self.order.array) {
        XRouteJob *job=self.jobs[key];
        if(!job) continue;
        if([self.engine cached:key]) {[self.jobs removeObjectForKey:key];[self.order removeObject:key];continue;}
        if(!job.started && ![visible containsObject:key]) {[self.jobs removeObjectForKey:key];[self.order removeObject:key];continue;}
        if(!job.started) continue;
        XOfficialObservation *observation=self.inspect(job.context);
        if([self accept:observation job:job]) continue;
        if(observation.failed) {[self officialFailed:job code:observation.code reason:"native failure"];continue;}
        if(now-job.began>=8) [self officialFailed:job code:0 reason:"8s timeout"];
    }
    NSUInteger active=0;for(XRouteJob *job in self.jobs.allValues) if(job.started) active++;
    for(NSString *key in self.order.array) {
        XRouteJob *job=self.jobs[key];if(!job || job.started) continue;
        if(now<self.officialUntil) {[self google:job reason:"official cooldown"];continue;}
        if(active>=(self.failures ? 1U : 2U) || now<self.nextStart) break;
        XOfficialObservation *observation=self.inspect(job.context);
        if([self accept:observation job:job]) continue;
        if(observation.failed) {[self officialFailed:job code:observation.code reason:"existing native failure"];continue;}
        job.started=YES;job.began=now;self.nextStart=now+1;
        if(!observation.inFlight) {
            if(!self.start(job.context)) {[self officialFailed:job code:0 reason:"native route unavailable"];continue;}
            self.officialStarts++;
        }
        active++;
        XADLog("ROUTER","official pending key=%.12s active=%lu probe=%d",key.UTF8String,(unsigned long)active,self.failures>0);
    }
    [self.engine keepQueuedKeys:visible];[self.engine pump];
}
- (NSDictionary<NSString *,NSNumber *> *)statistics {
    return @{@"officialStarts":@(self.officialStarts),@"officialSuccesses":@(self.officialSuccesses),@"fallbacks":@(self.fallbacks),
        @"officialCooldown":@(MAX(0,self.officialUntil-self.clock())),@"officialPending":@(self.jobs.count)};
}
@end
