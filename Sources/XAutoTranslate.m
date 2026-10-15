#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <NaturalLanguage/NaturalLanguage.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <dlfcn.h>
#include "XDiagnostics.h"
#import "XGTXEngine.h"
#import "XGTXNativeDisplay.h"
#import "XTranslationRouter.h"

// Verified selectors in the supplied X 12.33 (31) binary; native factory keeps
// glyph layout, max-lines, width measurements and the cell's normal height path.
@interface NSObject (XATNativeTextFactory)
- (instancetype)initWithStatusID:(long long)statusID cardData:(id)card originalText:(NSString *)text fromUserID:(long long)userID date:(NSDate *)date;
- (instancetype)initWithCanonicalStatus:(id)canonical fromUser:(id)user;
- (instancetype)initWithEventType:(id)type statusView:(id)view sourceView:(id)source;
@end

@interface XATSource : NSObject
@property(nonatomic,copy) NSString *key,*text,*language,*version;
@property(nonatomic,weak) id status;
@property(nonatomic,strong) id canonical,note;
@end
@implementation XATSource
@end
@interface XATNativeContext : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic,strong) id model;
@end
@implementation XATNativeContext
@end

static XGTXEngine *engine;
static XTranslationRouter *router;
static id translationHelper,eventType;
static id (*currentLanguage)(void);
static _Thread_local unsigned routingOfficial;
static void (*originalOfficial)(id,SEL,id,id);
static NSCache<NSString *,id> *nativeModels;
static NSHashTable<UIView *> *views;
static NSTimer *scanTimer;
static NSMutableSet<NSString *> *changedKeys;
static BOOL refreshPending,refreshing,installed;
static unsigned attempts;
static _Thread_local unsigned readingOriginal;
static char sourceKey,viewKey,renderedKey;
static Class statusClass;
static id (*originalDisplay)(id,SEL,NSUInteger);
static NSUInteger bindings;

static id Object(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if(!object || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature *sig=[object methodSignatureForSelector:selector];
    if(sig.numberOfArguments!=2 || sig.methodReturnType[0]!='@') return nil;
    return ((id (*)(id,SEL))objc_msgSend)(object,selector);
}
static long long Number(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    NSMethodSignature *sig=[object methodSignatureForSelector:selector];
    if(sig.numberOfArguments==2 && (sig.methodReturnType[0]=='i' || sig.methodReturnType[0]=='I')) return ((int (*)(id,SEL))objc_msgSend)(object,selector);
    if(sig.numberOfArguments!=2 || (sig.methodReturnType[0]!='q' && sig.methodReturnType[0]!='Q')) return 0;
    return ((long long (*)(id,SEL))objc_msgSend)(object,selector);
}
static NSString *String(id value) {return [value isKindOfClass:NSString.class] ? value : nil;}
static id Status(id model) {
    NSHashTable *seen=[NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPointerPersonality];
    for(unsigned i=0;model && i<8;i++) {
        if([seen containsObject:model]) return nil;[seen addObject:model];
        if([model isKindOfClass:statusClass]) {
            id represented=Object(model,@"representeeStatus");
            return [represented isKindOfClass:statusClass] ? represented : model;
        }
        id next=Object(model,@"representedStatus") ?: Object(model,@"statusViewModel") ?: Object(model,@"status");
        if(next==model) return nil;model=next;
    }
    return nil;
}
static XATSource *Source(id status) {
    if(!status) return nil;
    id canonical=Object(status,@"canonicalStatus") ?: status;
    id note=Object(status,@"noteTweet");
    NSString *version=String(Object(canonical,@"originalText")) ?: @"";
    XATSource *old=objc_getAssociatedObject(status,&sourceKey);
    if(old && old.canonical==canonical && old.note==note && [old.version isEqual:version]) return old;
    readingOriginal++;
    NSString *text=String(Object(status,@"fullText")) ?: String(Object(status,@"text"));
    readingOriginal--;
    if(!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location==NSNotFound) return nil;
    NSString *language=String(Object(status,@"language")) ?: String(Object(canonical,@"language")) ?: @"und";
    if([language isEqual:@"und"]) language=[NLLanguageRecognizer dominantLanguageForString:text] ?: @"und";
    XATSource *source=XATSource.new;
    source.status=status;source.canonical=canonical;source.note=note;source.version=version;source.text=text;source.language=language;
    NSString *identity=String(Object(status,@"statusIDString")) ?: [NSString stringWithFormat:@"%lld",Number(status,@"statusID")];
    source.key=XGTXDigest([NSString stringWithFormat:@"zh-CN\n%@\n%@",identity,text]);
    objc_setAssociatedObject(status,&sourceKey,source,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return source;
}
static id DisplayFor(XATSource *source,XGTXResult *result,NSUInteger options) {
    NSString *modelKey=[source.key stringByAppendingFormat:@":%lu",(unsigned long)options];
    id cached=[nativeModels objectForKey:modelKey];if(cached) return cached;
    NSString *code=[result.language isEqual:@"und"] ? source.language : result.language;
    readingOriginal++;
    id model=XGTXNativeDisplay(source.status,result.text,code,options,originalDisplay);
    readingOriginal--;
    if(model) [nativeModels setObject:model forKey:modelKey];
    return model;
}
static id GoogleDisplay(id status,SEL selector,NSUInteger options) {
    if(!readingOriginal && engine) {
        XATSource *source=Source(Status(status) ?: status);
        XGTXResult *saved=source && !XGTXChinese(source.language) ? [engine cached:source.key] : nil;
        if(saved && !XGTXChinese(saved.language)) {
            id native=DisplayFor(source,saved,options);
            if(native) {
                if(!objc_getAssociatedObject(status,&renderedKey)) {
                    objc_setAssociatedObject(status,&renderedKey,source.key,OBJC_ASSOCIATION_COPY_NONATOMIC);
                    XADLog("RENDER","cache hit key=%.12s nativeTextModel=1 networkRequest=0",source.key.UTF8String);
                }
                return native;
            }
            XADLog("RENDER","native factory unavailable; original body preserved");
        }
    }
    return originalDisplay(status,selector,options);
}
static BOOL Visible(UIView *view) {
    if(!view.window || view.hidden || view.alpha<0.01 || view.bounds.size.width<10 || view.bounds.size.height<10) return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:view.window],view.window.bounds);
}
static XATSource *ViewSource(UIView *view) {
    return Source(Status(Object(view,@"viewModel")));
}
static BOOL StartOfficial(XATNativeContext *context) {
    UIView *view=context.view;
    id handler=Object(view,@"eventHandler");SEL handle=NSSelectorFromString(@"handleStatusViewEvent:");
    Class eventClass=NSClassFromString(@"TTACoreStatusViewEvent");
    if(!originalOfficial || !view.window || Object(view,@"viewModel")!=context.model || !Object(view,@"account") || ![handler respondsToSelector:handle] || !eventType || !class_getInstanceMethod(eventClass,@selector(initWithEventType:statusView:sourceView:))) return NO;
    @try {
        id event=[[eventClass alloc] initWithEventType:eventType statusView:view sourceView:view];
        if(!event) return NO;
        routingOfficial++;
        @try {((void (*)(id,SEL,id))objc_msgSend)(handler,handle,event);}
        @finally {routingOfficial--;}
        return YES;
    } @catch(NSException *e) {(void)e;XADLog("OFFICIAL","dispatch exception=%s",e.name.UTF8String);return NO;}
}
static XOfficialObservation *InspectOfficial(XATNativeContext *context) {
    XOfficialObservation *observation=XOfficialObservation.new;
    if(currentLanguage && !XGTXChinese(String(currentLanguage()) ?: @"und")) {observation.failed=YES;return observation;}
    SEL getInfo=NSSelectorFromString(@"getInfoFor:");
    if(![translationHelper respondsToSelector:getInfo]) {observation.failed=YES;return observation;}
    @try {
        id info=((id (*)(id,SEL,id))objc_msgSend)(translationHelper,getInfo,context.model);
        NSInteger state=Number(info,@"state");
        id automatic=Object(context.model,@"grokTranslatedPost");
        NSString *text=String(Object(automatic,@"translation"));
        if(!text.length && state==3) {
            id translated=Object(info,@"translatedStatus");
            readingOriginal++;
            @try {text=String(Object(translated,@"fullText")) ?: String(Object(translated,@"text"));}
            @finally {readingOriginal--;}
        }
        if(text.length) {XGTXResult *result=XGTXResult.new;result.text=text;result.language=@"und";observation.result=result;}
        observation.failed=!text.length && (state==2 || state==3);
        observation.inFlight=state==1 || state==4;
        observation.code=Number(Object(info,@"translationError"),@"code");
    } @catch(NSException *e) {(void)e;observation.failed=YES;XADLog("OFFICIAL","observe exception=%s",e.name.UTF8String);}
    return observation;
}
static void Track(UIView *view) {
    if(!NSThread.isMainThread) return;
    [views addObject:view];
    if(!Visible(view)) return;
    XATSource *source=ViewSource(view);
    if(!source || XGTXChinese(source.language)) return;
    NSString *previous=objc_getAssociatedObject(view,&viewKey);
    if(![previous isEqual:source.key]) {
        objc_setAssociatedObject(view,&viewKey,source.key,OBJC_ASSOCIATION_COPY_NONATOMIC);
        XADLog("VIEW","visible key=%.12s class=%s lang=%s",source.key.UTF8String,NSStringFromClass(view.class).UTF8String,source.language.UTF8String);
    }
    XATNativeContext *context=XATNativeContext.new;context.view=view;context.model=Object(view,@"viewModel");
    [router submit:source.key text:source.text language:source.language context:context];
}
static UITableView *Table(UIView *view) {
    for(UIView *parent=view.superview;parent;parent=parent.superview) if([parent isKindOfClass:UITableView.class]) return (id)parent;
    return nil;
}
static UICollectionView *Collection(UIView *view) {
    for(UIView *parent=view.superview;parent;parent=parent.superview) if([parent isKindOfClass:UICollectionView.class]) return (id)parent;
    return nil;
}
static void RefreshBody(UIView *view,unsigned depth) {
    if(depth>8) return;
    Class body=NSClassFromString(@"TTAStatusBodyTextView");
    SEL changed=NSSelectorFromString(@"statusDidUpdate:");
    if(body && [view isKindOfClass:body] && [view respondsToSelector:changed]) {
        ((void (*)(id,SEL,BOOL))objc_msgSend)(view,changed,YES);
        [view invalidateIntrinsicContentSize];[view setNeedsLayout];return;
    }
    for(UIView *child in view.subviews.copy) RefreshBody(child,depth+1);
}
static void Refresh(void) {
    refreshPending=NO;
    if(refreshing || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    NSMutableSet *ready=[NSMutableSet setWithSet:changedKeys];
    NSMutableSet *notified=NSMutableSet.new;
    NSHashTable *tables=NSHashTable.weakObjectsHashTable,*collections=NSHashTable.weakObjectsHashTable;
    BOOL postponed=NO;refreshing=YES;
    for(UIView *view in views.allObjects) {
        if(!Visible(view)) continue;
        XATSource *source=ViewSource(view);
        if(![ready containsObject:source.key ?: @""]) continue;
        UIScrollView *scroll=Table(view) ?: (UIScrollView *)Collection(view);
        if(scroll.isDragging || scroll.isDecelerating || scroll.isTracking) {postponed=YES;continue;}
        @try {
            if(![notified containsObject:source.key] && [source.status respondsToSelector:NSSelectorFromString(@"postStatusNotificationUserInfo:")]) {
                ((void (*)(id,SEL,id))objc_msgSend)(source.status,NSSelectorFromString(@"postStatusNotificationUserInfo:"),@{});
                [notified addObject:source.key];
            }
            RefreshBody(view,0);[view invalidateIntrinsicContentSize];[view setNeedsLayout];
            UITableView *table=Table(view);if(table) [tables addObject:table];
            UICollectionView *collection=Collection(view);if(collection) [collections addObject:collection];
        } @catch(NSException *e) {XADLog("REFRESH","native notification failed exception=%s",e.name.UTF8String);}
    }
    [UIView performWithoutAnimation:^{
        for(UITableView *table in tables.allObjects) @try {[table beginUpdates];[table endUpdates];} @catch(NSException *e) {XADLog("REFRESH","table relayout exception=%s",e.name.UTF8String);}
        for(UICollectionView *collection in collections.allObjects) [collection.collectionViewLayout invalidateLayout];
    }];
    [changedKeys minusSet:notified];
    if(!postponed && !notified.count) [changedKeys removeAllObjects];
    refreshing=NO;
}
static void Tick(void) {
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    NSMutableSet *visible=NSMutableSet.new;
    for(UIView *view in views.allObjects) if(Visible(view)) {
        Track(view);XATSource *source=ViewSource(view);if(source) [visible addObject:source.key];
    }
    [router tickWithVisibleKeys:visible];
    if(changedKeys.count) Refresh();
}
static void __attribute__((unused)) Snapshot(void) {
    NSDictionary *stats=engine.statistics;
    (void)stats;
    NSDictionary *routes=router.statistics;(void)routes;
    XADLog("ROUTER","officialStarts=%lu officialSuccesses=%lu fallbacks=%lu officialCooldown=%.1f pending=%lu",
        (unsigned long)[routes[@"officialStarts"] unsignedIntegerValue],(unsigned long)[routes[@"officialSuccesses"] unsignedIntegerValue],
        (unsigned long)[routes[@"fallbacks"] unsignedIntegerValue],[routes[@"officialCooldown"] doubleValue],(unsigned long)[routes[@"officialPending"] unsignedIntegerValue]);
    XADLog("SNAPSHOT","provider=OfficialFirst+GoogleGTX tracked=%lu bindings=%lu cache=%lu hits=%lu googleRequests=%lu joined=%lu active=%lu queued=%lu throttles=%lu cooldown=%.1f",
        (unsigned long)views.allObjects.count,(unsigned long)bindings,(unsigned long)[stats[@"cache"] unsignedIntegerValue],
        (unsigned long)[stats[@"hits"] unsignedIntegerValue],(unsigned long)[stats[@"requests"] unsignedIntegerValue],(unsigned long)[stats[@"joined"] unsignedIntegerValue],
        (unsigned long)[stats[@"active"] unsignedIntegerValue],(unsigned long)[stats[@"queued"] unsignedIntegerValue],(unsigned long)[stats[@"throttles"] unsignedIntegerValue],[stats[@"cooldown"] doubleValue]);
}
static BOOL Replace(Class cls,SEL selector,IMP replacement,IMP *old) {
    Method method=class_getInstanceMethod(cls,selector);if(!method) return NO;
    if(old) *old=method_getImplementation(method);
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
    return YES;
}
static BOOL NeverDisplay(id self,SEL selector) {(void)self;(void)selector;return NO;}
static void BlockOfficialTranslation(id self,SEL selector,id event,id controller) {
    if(routingOfficial && originalOfficial) {originalOfficial(self,selector,event,controller);return;}
    XADLog("OFFICIAL","unmanaged native translation event suppressed; use router");
}
static void Install(void);
static void Retry(void) { if(attempts<20) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{Install();}); }
static void Install(void) {
    if(installed) return;
    XADStart();attempts++;
    NSBundle *bundle=NSBundle.mainBundle;
    if(![bundle.bundleIdentifier isEqual:@"com.atebits.Tweetie2"] || ![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"12.33"] || ![[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"31"]) {
        XADCoreStatus("停用：仅支持 X 12.33（31）");return;
    }
    statusClass=NSClassFromString(@"TFNTwitterStatus");
    Class canonical=NSClassFromString(@"TFNTwitterCanonicalStatus");
    SEL display=NSSelectorFromString(@"_tfn_displayTextModelForOptions:");
    if(!class_getInstanceMethod(statusClass,display) || !class_getInstanceMethod(canonical,@selector(initWithStatusID:cardData:originalText:fromUserID:date:)) || !class_getInstanceMethod(statusClass,@selector(initWithCanonicalStatus:fromUser:))) {
        XADLog("INSTALL","native text factory not ready attempt=%u",attempts);Retry();return;
    }
    nativeModels=NSCache.new;nativeModels.countLimit=256;views=NSHashTable.weakObjectsHashTable;changedKeys=NSMutableSet.new;
    engine=[[XGTXEngine alloc] initWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration clock:^NSTimeInterval{return NSDate.timeIntervalSinceReferenceDate;} interval:1.0];
    Class helperClass=NSClassFromString(@"T1PostTranslationHelper");
    translationHelper=Object(helperClass,@"shared");
    currentLanguage=dlsym(RTLD_DEFAULT,"TFSCurrentLanguageCode");
    void *eventAddress=dlsym(RTLD_DEFAULT,"T1StatusViewGrokTranslateEvent");
    if(eventAddress) eventType=*(__unsafe_unretained id *)eventAddress;
    router=[[XTranslationRouter alloc] initWithEngine:engine clock:^NSTimeInterval{return NSDate.timeIntervalSinceReferenceDate;}
        start:^BOOL(id context){return StartOfficial(context);}
        inspect:^XOfficialObservation *(id context){return InspectOfficial(context);}];
    router.didFinish=^(NSString *key){
        [changedKeys addObject:key];
        if(!refreshPending) {refreshPending=YES;dispatch_async(dispatch_get_main_queue(),^{Refresh();});}
    };
    Replace(statusClass,display,(IMP)GoogleDisplay,(IMP *)&originalDisplay);
    NSUInteger count=0;
    for(NSString *name in @[@"T1StandardStatusView",@"T1ConversationFocalStatusView",@"T1QuotedStandardStatusView"]) {
        Class cls=NSClassFromString(name);if(!cls) continue;
        for(NSString *method in @[@"layoutSubviews",@"didMoveToWindow"]) {
            SEL selector=NSSelectorFromString(method);Method m=class_getInstanceMethod(cls,selector);if(!m) continue;
            IMP original=method_getImplementation(m);
            IMP hook=imp_implementationWithBlock(^(UIView *view){((void (*)(id,SEL))original)(view,selector);Track(view);});
            if(Replace(cls,selector,hook,NULL)) count++;
        }
        SEL selector=NSSelectorFromString(@"setViewModel:options:account:");Method m=class_getInstanceMethod(cls,selector);
        if(m) {
            IMP original=method_getImplementation(m);
            IMP hook=imp_implementationWithBlock(^(UIView *view,id model,NSUInteger options,id account){
                ((void (*)(id,SEL,id,NSUInteger,id))original)(view,selector,model,options,account);bindings++;Track(view);
            });
            if(Replace(cls,selector,hook,NULL)) count++;
        }
    }
    Class helper=NSClassFromString(@"T1GrokPostTranslationDisplayHelper");
    for(NSString *method in @[@"shouldDisplayAutoTranslateText",@"shouldDisplayManualTranslateText",@"shouldDisplayAutoTranslateButton",@"shouldDisplayManualTranslateButton"])
        Replace(helper,NSSelectorFromString(method),(IMP)NeverDisplay,NULL);
    Class access=NSClassFromString(@"_TtC4Grok17GrokFeatureAccess");
    NSUInteger blocked=0;
    for(NSString *method in @[@"isGrokPostAutoTranslationEnabled"])
        blocked+=Replace(access,NSSelectorFromString(method),(IMP)NeverDisplay,NULL);
    blocked+=Replace(NSClassFromString(@"T1GrokTranslateEventHandler"),NSSelectorFromString(@"handleStatusViewEvent:controller:"),(IMP)BlockOfficialTranslation,(IMP *)&originalOfficial);
    (void)blocked;(void)count;
    XADLog("OFFICIAL","managed translation gates installed=%lu/2 helper=%d event=%d",(unsigned long)blocked,translationHelper!=nil,eventType!=nil);
    scanTimer=[NSTimer timerWithTimeInterval:0.75 repeats:YES block:^(NSTimer *timer){(void)timer;Tick();}];
    [NSRunLoop.mainRunLoop addTimer:scanTimer forMode:NSRunLoopCommonModes];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
        (void)note;[nativeModels removeAllObjects];XADLog("MEMORY","native render models cleared; successful translations retained");
    }];
    XADSetSnapshotHandler(Snapshot);installed=YES;
    XADCoreStatus("官方优先，失败自动转 Google；中文跳过；成功结果缓存");
    XADLog("INSTALL","GTX hooks=%lu nativeDisplay=1 footer=language-translated overlay=0 interval=1s concurrent=2",(unsigned long)count);
}
static atomic_bool scheduled;
void XATScheduleInitialization(void) {
    if(atomic_exchange(&scheduled,true)) return;
    dispatch_async(dispatch_get_main_queue(),^{Install();});
}
__attribute__((constructor)) static void start(void) {
    XADBootstrap("CONSTRUCTOR_ENTER");XADLog("BOOT","XAutoTranslate v6 OfficialFirst + GoogleGTX loaded");XATScheduleInitialization();
}
