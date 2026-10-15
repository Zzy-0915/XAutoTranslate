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
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *retryAfter;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *order;
@property(nonatomic,strong) NSMutableSet<NSString *> *googleKeys;
@property(nonatomic,copy) NSTimeInterval (^clock)(void);
@property(nonatomic,copy) BOOL (^start)(id);
@property(nonatomic,copy) XOfficialObservation *(^inspect)(id);
@property(nonatomic) NSTimeInterval officialUntil,nextStart;
@property(nonatomic) NSUInteger failures,officialStarts,officialSuccesses,fallbacks,deferrals;
@end
@implementation XTranslationRouter
- (instancetype)initWithEngine:(XGTXEngine *)engine clock:(NSTimeInterval (^)(void))clock start:(BOOL (^)(id))start inspect:(XOfficialObservation *(^)(id))inspect {
    if((self=[super init])) {
        _engine=engine;_clock=[clock copy];_start=[start copy];_inspect=[inspect copy];
        _jobs=NSMutableDictionary.new;_retryAfter=NSMutableDictionary.new;_order=NSMutableOrderedSet.new;_googleKeys=NSMutableSet.new;
        __weak XTranslationRouter *weak=self;
        engine.didFinish=^(NSString *key){
            XTranslationRouter *s=weak;if(!s) return;
            [s.jobs removeObjectForKey:key];[s.order removeObject:key];[s.googleKeys removeObject:key];[s.retryAfter removeObjectForKey:key];
            if(s.didFinish) s.didFinish(key);
        };
    }return self;
}
- (void)remove:(XRouteJob *)job {[self.jobs removeObjectForKey:job.key];[self.order removeObject:job.key];}
- (void)defer:(XRouteJob *)job reason:(const char *)reason {
    (void)reason;self.deferrals++;self.retryAfter[job.key]=@(self.clock()+60);[self remove:job];
    XADLog("ROUTER","official deferred key=%.12s reason=%s googleEnabled=0",job.key.UTF8String,reason);
}
- (void)google:(XRouteJob *)job eligible:(NSSet<NSString *> *)eligible reason:(const char *)reason {
    (void)reason;[self remove:job];
    if(![self.googleKeys containsObject:job.key]) {
        self.fallbacks++;[self.googleKeys addObject:job.key];
        XADLog("ROUTER","fallback key=%.12s from=official to=GoogleGTX reason=%s",job.key.UTF8String,reason);
    }
    if([eligible containsObject:job.key]) [self.engine enqueue:job.key text:job.text language:job.language];
}
- (void)officialFailed:(XRouteJob *)job code:(NSInteger)code eligible:(NSSet<NSString *> *)eligible {
    (void)code;self.failures++;
    NSTimeInterval delay=MIN(900,300*pow(2,MIN(self.failures-1,2)));
    self.officialUntil=MAX(self.officialUntil,self.clock()+delay);
    XADLog("ROUTER","official failure state=2 code=%ld wait=%.0f googleEnabled=1",(long)code,delay);
    [self google:job eligible:eligible reason:"confirmed native failure state=2"];
}
- (BOOL)accept:(XOfficialObservation *)observation job:(XRouteJob *)job {
    if(!observation.result.text.length) return NO;
    if(!XGTXTranslationChanged(observation.result.text,job.text)) {observation.result=nil;observation.unavailable=YES;return NO;}
    self.officialSuccesses++;
    if(self.clock()>=self.officialUntil) {self.failures=0;self.officialUntil=0;}
    XADLog("ROUTER","official success key=%.12s officialCooldown=%.1f",job.key.UTF8String,MAX(0,self.officialUntil-self.clock()));
    if([observation.result.language isEqual:@"und"]) observation.result.language=job.language;
    [self.engine storeResult:job.key result:observation.result];return YES;
}
- (void)submit:(NSString *)key text:(NSString *)text language:(NSString *)language context:(id)context {
    NSAssert(NSThread.isMainThread,@"main-thread router");
    if(!text.length || XGTXChinese(language) || [self.engine cached:key]) return;
    if(self.jobs[key]) {if(!self.jobs[key].started) self.jobs[key].context=context;return;}
    if(self.retryAfter[key].doubleValue>self.clock() && !self.inspect(context).failed) return;
    if(self.jobs.count>=8) return;
    XRouteJob *job=XRouteJob.new;job.key=key;job.text=text;job.language=language;job.context=context;
    self.jobs[key]=job;[self.order addObject:key];
}
- (void)tickWithVisibleKeys:(NSSet<NSString *> *)eligible {
    NSAssert(NSThread.isMainThread,@"main-thread router");
    [self.engine setEligibleKeys:eligible];NSTimeInterval now=self.clock();
    for(NSString *key in self.retryAfter.allKeys) if(self.retryAfter[key].doubleValue<=now) [self.retryAfter removeObjectForKey:key];
    for(NSString *key in self.order.array) {
        XRouteJob *job=self.jobs[key];if(!job) continue;
        if([self.engine cached:key]) {[self remove:job];continue;}
        if(!job.started && ![eligible containsObject:key]) {[self remove:job];continue;}
        if(!job.started) continue;
        XOfficialObservation *observation=self.inspect(job.context);
        if([self accept:observation job:job]) continue;
        if(observation.failed) {[self officialFailed:job code:observation.code eligible:eligible];continue;}
        if(observation.unavailable) {[self defer:job reason:"native unavailable or result invalid"];continue;}
        if(now-job.began>=30) [self defer:job reason:"30s without official failure; Google not started"];
    }
    NSUInteger active=0;for(XRouteJob *job in self.jobs.allValues) if(job.started) active++;
    for(NSString *key in self.order.array) {
        XRouteJob *job=self.jobs[key];if(!job || job.started || ![eligible containsObject:key]) continue;
        if([self.googleKeys containsObject:key] || now<self.officialUntil) {[self google:job eligible:eligible reason:"confirmed official failure cooldown"];continue;}
        XOfficialObservation *observation=self.inspect(job.context);
        if([self accept:observation job:job]) continue;
        if(observation.failed) {[self officialFailed:job code:observation.code eligible:eligible];continue;}
        if(observation.unavailable) {[self defer:job reason:"native unavailable or result invalid"];continue;}
        if(active>=1 || now<self.nextStart) continue;
        job.started=YES;job.began=now;self.nextStart=now+1.5;
        if(!observation.inFlight) {
            if(!self.start(job.context)) {[self defer:job reason:"view changed or native route unavailable"];continue;}
            self.officialStarts++;
        }
        active++;
        XADLog("ROUTER","official pending key=%.12s active=1 probe=%d",key.UTF8String,self.failures>0);
    }
    [self.engine pump];
}
- (NSDictionary<NSString *,NSNumber *> *)statistics {
    return @{@"officialStarts":@(self.officialStarts),@"officialSuccesses":@(self.officialSuccesses),@"fallbacks":@(self.fallbacks),
        @"officialCooldown":@(MAX(0,self.officialUntil-self.clock())),@"officialPending":@(self.jobs.count),@"deferrals":@(self.deferrals)};
}
@end
