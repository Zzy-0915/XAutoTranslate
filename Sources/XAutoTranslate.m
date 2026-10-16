#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <NaturalLanguage/NaturalLanguage.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <dlfcn.h>
#import "XGTXEngine.h"
#import "XNativeTranslation.h"
#import "XTranslationRouter.h"
#import "XIntegratedPlugin.h"

@interface NSObject (XATNativeEvent)
- (instancetype)initWithEventType:(id)type statusView:(id)view sourceView:(id)source;
@end

@interface XATSource : NSObject
@property(nonatomic,copy) NSString *key,*text,*language,*version;
@property(nonatomic,strong) id canonical,note;
@end
@implementation XATSource
@end
@interface XATNativeContext : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic,strong) id model;
@property(nonatomic,copy) NSString *text,*language;
@end
@implementation XATNativeContext
@end

static XGTXEngine *engine;
static XTranslationRouter *router;
static id translationHelper,eventType;
static id (*currentLanguage)(void);
static _Thread_local unsigned routingOfficial;
static void (*originalOfficial)(id,SEL,id,id);
static NSString *dynamicUpdateKey,*animatedUpdateKey;
static NSHashTable<UIView *> *views;
static NSTimer *scanTimer;
static NSMutableSet<NSString *> *changedKeys;
static BOOL refreshPending,refreshing,installed;
static unsigned attempts;
static char sourceKey,notifiedKey;
static Class statusClass;
static Ivar displayModelIvar;

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
    NSString *text=String(Object(status,@"fullText")) ?: String(Object(status,@"text"));
    if(!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location==NSNotFound) return nil;
    NSString *language=String(Object(status,@"language")) ?: String(Object(canonical,@"language")) ?: @"und";
    if([language isEqual:@"zxx"]) return nil;
    if([language isEqual:@"und"]) language=[NLLanguageRecognizer dominantLanguageForString:text] ?: @"und";
    XATSource *source=XATSource.new;
    source.canonical=canonical;source.note=note;source.version=version;source.text=text;source.language=language;
    NSString *identity=String(Object(status,@"statusIDString")) ?: [NSString stringWithFormat:@"%lld",Number(status,@"statusID")];
    source.key=XGTXDigest([NSString stringWithFormat:@"zh-CN\n%@\n%@",identity,text]);
    objc_setAssociatedObject(status,&sourceKey,source,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return source;
}
static BOOL Visible(UIView *view) {
    if(!view.window || view.hidden || view.alpha<0.01 || view.bounds.size.width<10 || view.bounds.size.height<10) return NO;
    CGRect box=[view convertRect:view.bounds toView:view.window];CGRect intersection=CGRectIntersection(box,view.window.bounds);
    return !CGRectIsNull(intersection) && intersection.size.height>=MIN(100,box.size.height*0.4) && intersection.size.width>=MIN(100,box.size.width*0.4);
}
static XATSource *ViewSource(UIView *view) {
    return Source(Status(Object(view,@"viewModel")));
}
static BOOL Eligible(UIView *view,XATSource *source) {
    return view && source && Visible(view) && UIApplication.sharedApplication.applicationState==UIApplicationStateActive && !view.window.rootViewController.presentedViewController;
}
static BOOL StartOfficial(XATNativeContext *context) {
    UIView *view=context.view;
    id handler=Object(view,@"eventHandler");SEL handle=NSSelectorFromString(@"handleStatusViewEvent:");
    Class eventClass=NSClassFromString(@"TTACoreStatusViewEvent");
    if(!Eligible(view,ViewSource(view)) || !originalOfficial || !view.window || Object(view,@"viewModel")!=context.model || !Object(view,@"account") || ![handler respondsToSelector:handle] || !eventType || !class_getInstanceMethod(eventClass,@selector(initWithEventType:statusView:sourceView:))) return NO;
    @try {
        id event=[[eventClass alloc] initWithEventType:eventType statusView:view sourceView:view];
        if(!event) return NO;
        routingOfficial++;
        @try {((void (*)(id,SEL,id))objc_msgSend)(handler,handle,event);}
        @finally {routingOfficial--;}
        return YES;
    } @catch(NSException *e) {(void)e;return NO;}
}
static XOfficialObservation *InspectOfficial(XATNativeContext *context) {
    XOfficialObservation *observation=XOfficialObservation.new;
    if(currentLanguage && !XGTXChinese(String(currentLanguage()) ?: @"und")) {observation.unavailable=YES;return observation;}
    SEL getInfo=NSSelectorFromString(@"getInfoFor:");
    if(![translationHelper respondsToSelector:getInfo]) {observation.unavailable=YES;return observation;}
    @try {
        id info=((id (*)(id,SEL,id))objc_msgSend)(translationHelper,getInfo,context.model);
        NSInteger state=Number(info,@"state");
        observation.result=XATNativeResult(context.model,info,context.text,context.language);
        observation.failed=state==2;
        observation.unavailable=!observation.result && state==3;
        observation.inFlight=state==1 || state==4;
    } @catch(NSException *e) {(void)e;observation.unavailable=YES;}
    return observation;
}
static void Refresh(void);
static void Track(UIView *view) {
    if(NSThread.isMainThread) [views addObject:view];
}
static void Refresh(void) {
    refreshPending=NO;
    if(refreshing || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
    NSSet *ready=changedKeys.copy;NSMutableSet *finished=NSMutableSet.new,*seenModels=NSMutableSet.new;
    BOOL postponed=NO;refreshing=YES;
    for(UIView *view in views.allObjects) {
        if(!Visible(view)) continue;
        XATSource *source=ViewSource(view);if(![ready containsObject:source.key ?: @""]) continue;
        if(!Eligible(view,source)) {postponed=YES;continue;}
        id model=Object(view,@"viewModel");XGTXResult *saved=[engine cached:source.key];
        if(!model || !saved || [seenModels containsObject:model]) continue;
        [seenModels addObject:model];
        @try {
            NSUInteger applied=XATNativePublish(model,translationHelper,saved,source.text);
            if(!applied) {continue;}
            BOOL notified=[objc_getAssociatedObject(model,&notifiedKey) isEqual:source.key];
            if(applied==1 && notified) {[finished addObject:source.key];continue;}
            if(XATNativeNotify(model,dynamicUpdateKey,animatedUpdateKey)) {
                objc_setAssociatedObject(model,&notifiedKey,source.key,OBJC_ASSOCIATION_COPY_NONATOMIC);
                [finished addObject:source.key];
            }
        } @catch(NSException *e) {(void)e;}
    }
    if(!postponed) [changedKeys minusSet:finished];
    refreshing=NO;
}
static void Tick(void) {
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) {[engine setEligibleKeys:NSSet.set];return;}
    NSMutableSet *eligible=NSMutableSet.new;NSMutableArray<UIView *> *ready=NSMutableArray.new;
    for(UIView *view in views.allObjects) {
        if(!Visible(view)) continue;
        XATSource *source=ViewSource(view);
        if(!source || XGTXChinese(source.language)) continue;
        if(Eligible(view,source)) {[eligible addObject:source.key];[ready addObject:view];}
    }
    [engine setEligibleKeys:eligible];
    [changedKeys intersectSet:eligible];
    for(UIView *view in ready) {
        XATSource *source=ViewSource(view);if(!source) continue;
        XATNativeContext *context=XATNativeContext.new;context.view=view;context.model=Object(view,@"viewModel");context.text=source.text;context.language=source.language;
        [router submit:source.key text:source.text language:source.language context:context];
        XGTXResult *saved=[engine cached:source.key];
        id info=[translationHelper respondsToSelector:NSSelectorFromString(@"getInfoFor:")] ? ((id (*)(id,SEL,id))objc_msgSend)(translationHelper,NSSelectorFromString(@"getInfoFor:"),context.model) : nil;
        if(saved && (!XATNativeMatches(info,saved.text) || ![objc_getAssociatedObject(context.model,&notifiedKey) isEqual:source.key])) [changedKeys addObject:source.key];
    }
    [router tickWithVisibleKeys:eligible];
    if(changedKeys.count) Refresh();
}
static BOOL Replace(Class cls,SEL selector,IMP replacement,IMP *old) {
    Method method=class_getInstanceMethod(cls,selector);if(!method) return NO;
    if(old) *old=method_getImplementation(method);
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
    return YES;
}
static BOOL NeverDisplay(id self,SEL selector) {(void)self;(void)selector;return NO;}
static BOOL EnableInline(id self,SEL selector) {(void)self;(void)selector;return YES;}
static void BlockOfficialTranslation(id self,SEL selector,id event,id controller) {
    id view=Object(event,@"statusView"),model=Object(view,@"viewModel");
    XATSource *source=ViewSource(view);XGTXResult *saved=source ? [engine cached:source.key] : nil;
    id info=[translationHelper respondsToSelector:NSSelectorFromString(@"getInfoFor:")] ? ((id (*)(id,SEL,id))objc_msgSend)(translationHelper,NSSelectorFromString(@"getInfoFor:"),model) : nil;
    NSInteger state=Number(info,@"state");
    BOOL cachedToggle=saved && (state==0 || state==3) && XATNativeMatches(info,saved.text);
    if(originalOfficial && (routingOfficial || cachedToggle)) {originalOfficial(self,selector,event,controller);return;}
}
static void Install(void);
static void Retry(void) { if(attempts<20) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{Install();}); }
static void Install(void) {
    if(installed) return;
    attempts++;
    NSBundle *bundle=NSBundle.mainBundle;
    if(![bundle.bundleIdentifier isEqual:@"com.atebits.Tweetie2"] || ![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"12.33"] || ![[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"31"]) {
        return;
    }
    XATPrepareIntegratedPlugin();
    if(!XATTranslationEnabled()) {installed=YES;return;}
    statusClass=NSClassFromString(@"TFNTwitterStatus");
    if(!statusClass || !NSClassFromString(@"T1TranslatedStatusViewModel") || !NSClassFromString(@"TFSTwitterTranslation")) {
        Retry();return;
    }
    views=NSHashTable.weakObjectsHashTable;changedKeys=NSMutableSet.new;
    void *dynamic=dlsym(RTLD_DEFAULT,"TTAStatusViewCombinedViewModelContainsDynamicContentTypeKey");
    void *animated=dlsym(RTLD_DEFAULT,"TTAStatusViewCombinedViewModelUpdateAnimatedKey");
    if(dynamic) dynamicUpdateKey=*(__unsafe_unretained id *)dynamic;
    if(animated) animatedUpdateKey=*(__unsafe_unretained id *)animated;
    engine=[[XGTXEngine alloc] initWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration clock:^NSTimeInterval{return NSProcessInfo.processInfo.systemUptime;} interval:1.0];
    [engine setEligibleKeys:NSSet.set];
    engine.admitRequest=^BOOL(NSString *key){
        if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return NO;
        for(UIView *view in views.allObjects) {
            if(!Visible(view)) continue;
            XATSource *source=ViewSource(view);
            if([source.key isEqual:key] && Eligible(view,source)) return YES;
        }return NO;
    };
    Class helperClass=NSClassFromString(@"T1PostTranslationHelper");
    translationHelper=Object(helperClass,@"shared");
    currentLanguage=dlsym(RTLD_DEFAULT,"TFSCurrentLanguageCode");
    void *eventAddress=dlsym(RTLD_DEFAULT,"T1StatusViewGrokTranslateEvent");
    if(eventAddress) eventType=*(__unsafe_unretained id *)eventAddress;
    router=[[XTranslationRouter alloc] initWithEngine:engine clock:^NSTimeInterval{return NSProcessInfo.processInfo.systemUptime;}
        start:^BOOL(id context){return StartOfficial(context);}
        inspect:^XOfficialObservation *(id context){return InspectOfficial(context);}];
    router.didFinish=^(NSString *key){
        [changedKeys addObject:key];
        if(!refreshPending) {refreshPending=YES;dispatch_async(dispatch_get_main_queue(),^{Refresh();});}
    };
    for(NSString *name in @[@"T1StandardStatusView",@"T1ConversationFocalStatusView",@"T1QuotedStandardStatusView"]) {
        Class cls=NSClassFromString(name);if(!cls) continue;
        for(NSString *method in @[@"layoutSubviews",@"didMoveToWindow"]) {
            SEL selector=NSSelectorFromString(method);Method m=class_getInstanceMethod(cls,selector);if(!m) continue;
            IMP original=method_getImplementation(m);
            IMP hook=imp_implementationWithBlock(^(UIView *view){((void (*)(id,SEL))original)(view,selector);Track(view);});
            Replace(cls,selector,hook,NULL);
        }
        SEL selector=NSSelectorFromString(@"setViewModel:options:account:");Method m=class_getInstanceMethod(cls,selector);
        if(m) {
            IMP original=method_getImplementation(m);
            IMP hook=imp_implementationWithBlock(^(UIView *view,id model,NSUInteger options,id account){
                ((void (*)(id,SEL,id,NSUInteger,id))original)(view,selector,model,options,account);Track(view);
            });
            Replace(cls,selector,hook,NULL);
        }
    }
    Class access=NSClassFromString(@"_TtC4Grok17GrokFeatureAccess");
    for(NSString *method in @[@"isGrokPostAutoTranslationEnabled"])
        Replace(access,NSSelectorFromString(method),(IMP)NeverDisplay,NULL);
    Replace(access,NSSelectorFromString(@"isGrokPostInlineTranslationEnabled"),(IMP)EnableInline,NULL);
    Class displayHelper=NSClassFromString(@"T1GrokPostTranslationDisplayHelper");
    displayModelIvar=class_getInstanceVariable(displayHelper,"statusViewModel");
    NSArray<NSString *> *displayMethods=@[@"shouldDisplayManualTranslateText",@"shouldDisplayManualTranslateButton",@"shouldDisplayAutoTranslateText",@"shouldDisplayAutoTranslateButton"];
    if(displayModelIvar) for(NSUInteger kind=0;kind<displayMethods.count;kind++) {
        SEL selector=NSSelectorFromString(displayMethods[kind]);Method method=class_getInstanceMethod(displayHelper,selector);if(!method) continue;
        IMP original=method_getImplementation(method);
        IMP hook=imp_implementationWithBlock(^BOOL(id helper){
            id model=object_getIvar(helper,displayModelIvar);XATSource *source=Source(Status(model));
            if(source && [translationHelper respondsToSelector:NSSelectorFromString(@"getInfoFor:")]) {
                id info=((id (*)(id,SEL,id))objc_msgSend)(translationHelper,NSSelectorFromString(@"getInfoFor:"),model);
                NSInteger decision=XATNativeDisplayOverride(model,info,[engine cached:source.key],source.text,source.language,kind);
                if(decision>=0) return decision!=0;
            }
            return ((BOOL (*)(id,SEL))original)(helper,selector);
        });
        Replace(displayHelper,selector,hook,NULL);
    }

    Replace(NSClassFromString(@"T1GrokTranslateEventHandler"),NSSelectorFromString(@"handleStatusViewEvent:controller:"),(IMP)BlockOfficialTranslation,(IMP *)&originalOfficial);

    scanTimer=[NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer){(void)timer;Tick();}];
    [NSRunLoop.mainRunLoop addTimer:scanTimer forMode:NSRunLoopCommonModes];
    installed=YES;
    
}
static atomic_bool scheduled;
void XATScheduleInitialization(void) {
    if(atomic_exchange(&scheduled,true)) return;
    dispatch_async(dispatch_get_main_queue(),^{Install();});
}
__attribute__((constructor)) static void start(void) {
    XATScheduleInitialization();
}
