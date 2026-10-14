#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

// ==================== 全局状态与日志系统 ====================
static NSMutableArray<NSString *> *gLogList = nil;
static NSLock *gLogLock = nil;
static NSMutableSet<NSString *> *gHookedKeys = nil;
static NSHashTable<UIView *> *gTrackedViews = nil;
static NSCache<NSString *, NSDate *> *gRecentRequests = nil;
static NSUInteger gSubmissionCount = 0;
static char kBindingKey, kRequestKey, kAccountKey;

#import "XATModelSupport.h"

@interface XATViewBinding : NSObject
@property (nonatomic, weak) id adapter;
@property (nonatomic, weak) id viewModel;
@property (nonatomic, copy) NSString *identity;
@property (nonatomic) BOOL scheduled;
@property (nonatomic) BOOL waitingLogged;
@property (nonatomic) NSTimeInterval nextAttempt;
@end
@implementation XATViewBinding
@end

@interface XATRequestRecord : NSObject
@property (nonatomic, copy) NSString *identity;
@property (nonatomic) BOOL submitted;
@end
@implementation XATRequestRecord
@end

@interface XATAccountContext : NSObject
@property (nonatomic, weak) id account;
@end
@implementation XATAccountContext
@end

static NSString *const kPrefAutoTranslateEnabled = @"XAutoTranslate_Enabled";

static void XLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"HH:mm:ss.SSS"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@", timestamp, msg];

    NSLog(@"[XAutoTranslate] %@", logEntry);

    [gLogLock lock];
    if (!gLogList) gLogList = [NSMutableArray array];
    [gLogList addObject:logEntry];
    if (gLogList.count > 800) [gLogList removeObjectAtIndex:0];
    [gLogLock unlock];
}

static BOOL IsAutoTranslateEnabled(void) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefAutoTranslateEnabled];
    return val ? [val boolValue] : YES;
}

// ==================== 语种与推文辅助判定 ====================
static BOOL IsAlreadyChineseText(NSString *text) {
    if (!text || text.length == 0) return YES;
    NSUInteger hanziCount = 0;
    NSUInteger alphaCount = 0;

    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        // 日文假名、韩文、泰文、阿拉伯文、俄文 -> 均需要翻译
        if ((c >= 0x3040 && c <= 0x30FF) || (c >= 0xFF66 && c <= 0xFF9F) ||
            (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x0E00 && c <= 0x0E7F) ||
            (c >= 0x0600 && c <= 0x06FF) || (c >= 0x0400 && c <= 0x04FF)) {
            return NO;
        }
        if (c >= 0x4E00 && c <= 0x9FFF) {
            hanziCount++;
        } else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
            alphaCount++;
        }
    }
    if (hanziCount == 0) return NO;
    if (hanziCount >= 2 && hanziCount * 3 >= alphaCount) return YES;
    return NO;
}

static BOOL ShouldTranslateViewModel(id vmOrStatus) {
    if (!IsAutoTranslateEnabled() || !vmOrStatus) return NO;

    NSString *lang = XATSourceLanguage(vmOrStatus).lowercaseString;
    if ([lang hasPrefix:@"zh"] || [lang isEqualToString:@"qam"] || [lang isEqualToString:@"qct"]) return NO;
    NSString *text = XATSourceText(vmOrStatus);
    if (text && (text.length < 2 || IsAlreadyChineseText(text))) return NO;
    return YES;
}

// Keep the closest controller for native routing; parents may only supply its account.
static UIViewController *FindControllerForView(UIView *view, id *outAccount) {
    UIViewController *firstVC = nil;
    id account = nil;
    for (UIResponder *resp = view.nextResponder; resp; resp = resp.nextResponder) {
        if (![resp isKindOfClass:[UIViewController class]]) continue;
        if (!firstVC) firstVC = (UIViewController *)resp;
        if (!account) account = SafeCallZeroArgObject(resp, NSSelectorFromString(@"account"));
    }
    for (UIViewController *parent = firstVC.parentViewController; parent && !account; parent = parent.parentViewController) {
        account = SafeCallZeroArgObject(parent, NSSelectorFromString(@"account"));
    }
    if (outAccount) *outAccount = account;
    return firstVC;
}

static BOOL XATVisibleInWindow(UIView *view) {
    UIWindow *window = view.window;
    if (!window || CGRectIsEmpty(view.bounds)) return NO;
    CGRect visible = [view convertRect:view.bounds toView:window];
    visible = CGRectIntersection(visible, window.bounds);
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
        if (ancestor.clipsToBounds) {
            visible = CGRectIntersection(visible, [ancestor convertRect:ancestor.bounds toView:window]);
        }
    }
    return !CGRectIsNull(visible) && !CGRectIsEmpty(visible);
}

static BOOL XATObjectArguments(NSMethodSignature *sig, NSUInteger count, char returnType) {
    if (!sig || sig.numberOfArguments != count + 2 || sig.methodReturnType[0] != returnType) return NO;
    for (NSUInteger i = 2; i < count + 2; i++) {
        if ([sig getArgumentTypeAtIndex:i][0] != '@') return NO;
    }
    return YES;
}

static UIView *XATTranslateButton(UIView *view) {
    id button = SafeCallZeroArgObject(view, NSSelectorFromString(@"translateButton"));
    if ([button isKindOfClass:[UIView class]]) return button;
    Class buttonClass = objc_getClass("T1TranslateButton");
    return buttonClass && [view isKindOfClass:buttonClass] ? view : nil;
}

static void XATScheduleTranslation(UIView *view) {
    XATViewBinding *binding = objc_getAssociatedObject(view, &kBindingKey);
    id vm = binding.viewModel;
    if (!binding || !vm || binding.scheduled || !IsAutoTranslateEnabled()) return;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if (!XATVisibleInWindow(view) || binding.nextAttempt > [NSDate timeIntervalSinceReferenceDate]) return;
    XATRequestRecord *record = objc_getAssociatedObject(XATRequestOwner(vm), &kRequestKey);
    if (record.submitted && [record.identity isEqualToString:binding.identity]) return;
    if (!ShouldTranslateViewModel(vm) || XATModelIsShowingTranslation(vm)) return;
    binding.scheduled = YES;
    __weak UIView *weakView = view;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        binding.scheduled = NO;
        UIView *currentView = weakView;
        id currentVM = binding.viewModel;
        // The binding object is a generation token. A recycled view cancels this callback.
        if (!currentView || objc_getAssociatedObject(currentView, &kBindingKey) != binding || !currentVM) return;
        if (![binding.identity isEqualToString:(XATModelIdentity(currentVM) ?: @"opaque-model")]) return;
        if (!IsAutoTranslateEnabled() || !XATVisibleInWindow(currentView) ||
            [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
        if (!ShouldTranslateViewModel(currentVM) || XATModelIsShowingTranslation(currentVM)) return;
        UIView *button = XATTranslateButton(currentView);
        if (SafeCallZeroArgBool(button, NSSelectorFromString(@"showingTranslation"))) return;
        id requestOwner = XATRequestOwner(currentVM);
        XATRequestRecord *existing = objc_getAssociatedObject(requestOwner, &kRequestKey);
        if (existing.submitted && [existing.identity isEqualToString:binding.identity]) return;

        NSString *tid = ExtractTweetID(currentVM);
        NSDate *lastRequest = tid ? [gRecentRequests objectForKey:tid] : nil;
        if (lastRequest && -lastRequest.timeIntervalSinceNow < 2.0) return;
        id account = nil;
        UIViewController *controller = FindControllerForView(currentView, &account);
        if (!account) account = SafeCallZeroArgObject(currentVM, NSSelectorFromString(@"account"));
        XATAccountContext *context = objc_getAssociatedObject(requestOwner, &kAccountKey);
        if (!account) account = context.account;
        Class toggleClass = objc_getClass("T1TranslationToggleEventHandler");
        SEL toggleSEL = NSSelectorFromString(@"_t1_toggleTranslationForViewModel:account:controller:");
        NSMethodSignature *toggleSignature = [toggleClass instanceMethodSignatureForSelector:toggleSEL];
        // Pick exactly ONE route. Missing synchronous callbacks do not imply a tap failed.
        id tap = nil;
        if (controller && button) {
            SEL tapSEL = NSSelectorFromString(@"tapActionBlock");
            NSMethodSignature *sig = [button methodSignatureForSelector:tapSEL];
            if (sig && sig.numberOfArguments == 2 && strcmp(sig.methodReturnType, "@?") == 0) {
                tap = SafeCallZeroArgObject(button, tapSEL);
            }
        }
        id handler = !tap && controller && account && XATObjectArguments(toggleSignature, 3, 'v') ? [[toggleClass alloc] init] : nil;
        if (!handler && !tap) {
            binding.nextAttempt = [NSDate timeIntervalSinceReferenceDate] + 2.0;
            if (!binding.waitingLogged) {
                XLog(@"[等待原生入口] adapter=%@ VM=%@ ID=%@ controller=%@ account=%@ engine=%@",
                     NSStringFromClass([binding.adapter class]), NSStringFromClass([currentVM class]), tid ?: @"未暴露",
                     NSStringFromClass([controller class]), NSStringFromClass([account class]),
                     XATObjectArguments(toggleSignature, 3, 'v') ? @"可用" : @"不可用");
                binding.waitingLogged = YES;
            }
            return; // No permanent dedupe before the native call is ready.
        }

        XATRequestRecord *submitted = [XATRequestRecord new];
        submitted.identity = binding.identity;
        submitted.submitted = YES; // Prevent a synchronous model rebind from issuing a second toggle.
        objc_setAssociatedObject(requestOwner, &kRequestKey, submitted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (tid) [gRecentRequests setObject:[NSDate date] forKey:tid];
        gSubmissionCount++;
        XLog(@"[自动提交] route=%@ adapter=%@ VM=%@ ID=%@ VC=%@",
             handler ? @"native-engine" : @"translate-button", NSStringFromClass([binding.adapter class]),
             NSStringFromClass([currentVM class]), tid ?: @"未暴露(按模型去重)", NSStringFromClass([controller class]));
        if (handler) {
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(handler, toggleSEL, currentVM, account, controller);
        } else {
            ((void(^)(void))tap)();
        }
        // Submission is not proof of success. Do not retry a toggle on an unknown async result.
    });
}

static void TriggerNativeTranslateOnAdapter(id adapter, UIView *view, id viewModel) {
    if (![view isKindOfClass:[UIView class]] || ![NSThread isMainThread]) return;
    // Subclasses can inherit a hooked body method even if discovery excluded them.
    NSString *adapterName = NSStringFromClass([adapter class]);
    if ([adapterName containsString:@"Translated"] || [adapterName containsString:@"Error"] ||
        [adapterName containsString:@"Quote"]) {
        objc_setAssociatedObject(view, &kBindingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gTrackedViews removeObject:view];
        return;
    }
    NSString *identity = XATModelIdentity(viewModel) ?: @"opaque-model";
    XATViewBinding *old = objc_getAssociatedObject(view, &kBindingKey);
    if (!viewModel) {
        objc_setAssociatedObject(view, &kBindingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gTrackedViews removeObject:view];
        return;
    }
    if (old.viewModel != viewModel || ![old.identity isEqualToString:identity]) {
        XATViewBinding *binding = [XATViewBinding new];
        binding.adapter = adapter;
        binding.viewModel = viewModel;
        binding.identity = identity;
        objc_setAssociatedObject(view, &kBindingKey, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        XLog(@"[正文绑定] adapter=%@ VM=%@ ID=%@", NSStringFromClass([adapter class]),
             NSStringFromClass([viewModel class]), ExtractTweetID(viewModel) ?: @"未暴露");
    }
    [gTrackedViews addObject:view];
    XATScheduleTranslation(view);
}

static void XATScanVisibleBindings(void) {
    if (!IsAutoTranslateEnabled()) return;
    for (UIView *view in gTrackedViews.allObjects) XATScheduleTranslation(view);
}

// ==================== Hook 辅助工具 ====================
static BOOL CanHook(Class cls, SEL sel) {
    if (!cls || !sel) return NO;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return NO;
    NSDictionary *contracts = @{
        @"initWithStatusViewModel:account:forFocalView:": @[@"@", @"@", @"@", @"Bc"],
        @"initWithViewModel:forFocalView:": @[@"@", @"@", @"Bc"],
        @"shouldBeVisibleForViewModel:": @[@"Bc", @"@"],
        @"setViewModel:forView:": @[@"v", @"@", @"@"],
        @"_t1_updateManualTranslateButtonForViewModel:forView:": @[@"v", @"@", @"@"],
        @"handleStatusViewEvent:controller:": @[@"v", @"@", @"@"],
        @"setState:": @[@"v", @"qQ"],
        @"setTranslationError:": @[@"v", @"@"],
        @"isTranslatable": @[@"Bc"],
        @"layoutSubviews": @[@"v"]
    };
    NSArray<NSString *> *contract = contracts[NSStringFromSelector(sel)];
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    BOOL compatible = contract && sig.numberOfArguments == contract.count + 1;
    for (NSUInteger i = 0; compatible && i < contract.count; i++) {
        const char *actual = XATUnqualifiedType(i == 0 ? sig.methodReturnType : [sig getArgumentTypeAtIndex:i + 1]);
        compatible = actual[0] && strchr(contract[i].UTF8String, actual[0]) != NULL;
    }
    if (!compatible) {
        XLog(@"[跳过不兼容签名] %@ -> %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return NO;
    }
    class_addMethod(cls, sel, method_getImplementation(method), method_getTypeEncoding(method));
    NSString *key = [NSString stringWithFormat:@"%@::%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
    @synchronized (gHookedKeys) {
        if ([gHookedKeys containsObject:key]) return NO;
        [gHookedKeys addObject:key];
        return YES;
    }
}

static void XATHookBodyBinding(Class cls, BOOL translatedBody) {
    SEL selector = NSSelectorFromString(@"setViewModel:forView:");
    NSMethodSignature *sig = [cls instanceMethodSignatureForSelector:selector];
    if (!XATObjectArguments(sig, 2, 'v') || !CanHook(cls, selector)) return;
    Method method = class_getInstanceMethod(cls, selector);
    IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^void(id self, id vm, UIView *view) {
        ((void(*)(id, SEL, id, id))original)(self, selector, vm, view);
        if (!translatedBody) {
            TriggerNativeTranslateOnAdapter(self, view, vm);
        } else if ([view isKindOfClass:[UIView class]]) {
            // Binding and on-screen visibility are separate observations; diagnostics only.
            static char translationTokenKey;
            NSObject *token = [NSObject new];
            objc_setAssociatedObject(view, &translationTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSString *tid = ExtractTweetID(vm);
            __weak UIView *weakView = view;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIView *current = weakView;
                if (current && objc_getAssociatedObject(current, &translationTokenKey) == token) {
                    XLog(@"[译文视图绑定] adapter=%@ ID=%@ visible=%@", NSStringFromClass(cls),
                         tid ?: @"未暴露", XATVisibleInWindow(current) ? @"YES" : @"NO");
                }
            });
        }
    }));
    XLog(@"[Hook成功] %@ -> setViewModel:forView: (%@)", NSStringFromClass(cls), translatedBody ? @"译文诊断" : @"正文入口");
}

static void XATInstallTimelineBindings(void) {
    // Discover only status body adapters with the exact, type-checked binding contract.
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSUInteger matches = 0;
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *name = NSStringFromClass(cls);
        if (![name hasPrefix:@"T1"] || ![name hasSuffix:@"BodyAdapter"] ||
            (![name containsString:@"Status"] && ![name containsString:@"Conversation"]) ||
            [name containsString:@"Translated"] || [name containsString:@"Error"] ||
            [name containsString:@"Quote"]) continue;
        if (!XATObjectArguments([cls instanceMethodSignatureForSelector:NSSelectorFromString(@"setViewModel:forView:")], 2, 'v')) continue;
        matches++;
        XATHookBodyBinding(cls, NO);
    }
    free(classes);
    XLog(@"[时间线入口扫描] 匹配正文适配器 %lu 个", (unsigned long)matches);

    Class statusView = objc_getClass("T1StatusView");
    SEL layout = @selector(layoutSubviews);
    NSMethodSignature *sig = [statusView instanceMethodSignatureForSelector:layout];
    if ([statusView isSubclassOfClass:[UIView class]] && XATObjectArguments(sig, 0, 'v') && CanHook(statusView, layout)) {
        Method method = class_getInstanceMethod(statusView, layout);
        IMP original = method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^void(UIView *self) {
            ((void(*)(id, SEL))original)(self, layout);
            id vm = SafeCallZeroArgObject(self, NSSelectorFromString(@"viewModel"));
            TriggerNativeTranslateOnAdapter(nil, self, vm);
        }));
        XLog(@"[Hook成功] T1StatusView -> layoutSubviews (可见正文入口)");
    }
    XATHookBodyBinding(objc_getClass("T1ConversationTranslatedBodyAdapter"), YES);
}

static void InstallTargetedNativeHooks(void) {
    XATInstallTimelineBindings();
    // 1. 挂钩 T1GrokPostTranslationDisplayHelper：强制将主页时间线视为 FocalView（解锁时间线翻译按钮与译文显示）
    Class grokHelperCls = objc_getClass("T1GrokPostTranslationDisplayHelper");
    if (grokHelperCls) {
        SEL init1 = NSSelectorFromString(@"initWithStatusViewModel:account:forFocalView:");
        if (CanHook(grokHelperCls, init1)) {
            Method m = class_getInstanceMethod(grokHelperCls, init1);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^id(id self, id vm, id acc, BOOL focal) {
                    if (vm && acc) {
                        XATAccountContext *context = [XATAccountContext new];
                        context.account = acc;
                        objc_setAssociatedObject(XATRequestOwner(vm), &kAccountKey, context, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                    if (IsAutoTranslateEnabled()) focal = YES;
                    return ((id(*)(id, SEL, id, id, BOOL))orig)(self, init1, vm, acc, focal);
                }));
                XLog(@"[Hook成功] T1GrokPostTranslationDisplayHelper -> initWithStatusViewModel:account:forFocalView:");
            }
        }

        SEL init2 = NSSelectorFromString(@"initWithViewModel:forFocalView:");
        if (CanHook(grokHelperCls, init2)) {
            Method m = class_getInstanceMethod(grokHelperCls, init2);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^id(id self, id vm, BOOL focal) {
                    if (IsAutoTranslateEnabled()) focal = YES;
                    return ((id(*)(id, SEL, id, BOOL))orig)(self, init2, vm, focal);
                }));
                XLog(@"[Hook成功] T1GrokPostTranslationDisplayHelper -> initWithViewModel:forFocalView:");
            }
        }
    }

    // 2. 挂钩 T1StandardStatusTranslateAdapter（仅针对真正的“显示翻译”按钮适配器，绝不碰 ErrorAdapter）
    Class translateAdapterCls = objc_getClass("T1StandardStatusTranslateAdapter");
    if (translateAdapterCls) {
        SEL visSel = NSSelectorFromString(@"shouldBeVisibleForViewModel:");
        if (CanHook(translateAdapterCls, visSel)) {
            Method m = class_getInstanceMethod(translateAdapterCls, visSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^BOOL(id self, id viewModel) {
                    if (IsAutoTranslateEnabled() && ShouldTranslateViewModel(viewModel)) {
                        return YES;
                    }
                    return ((BOOL(*)(id, SEL, id))orig)(self, visSel, viewModel);
                }));
                XLog(@"[Hook成功] T1StandardStatusTranslateAdapter -> shouldBeVisibleForViewModel:");
            }
        }

        SEL setVMSel = NSSelectorFromString(@"setViewModel:forView:");
        if (CanHook(translateAdapterCls, setVMSel)) {
            Method m = class_getInstanceMethod(translateAdapterCls, setVMSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^void(id self, id viewModel, UIView *view) {
                    ((void(*)(id, SEL, id, UIView *))orig)(self, setVMSel, viewModel, view);
                    TriggerNativeTranslateOnAdapter(self, view, viewModel);
                }));
                XLog(@"[Hook成功] T1StandardStatusTranslateAdapter -> setViewModel:forView:");
            }
        }

        SEL updateBtnSel = NSSelectorFromString(@"_t1_updateManualTranslateButtonForViewModel:forView:");
        if (CanHook(translateAdapterCls, updateBtnSel)) {
            Method m = class_getInstanceMethod(translateAdapterCls, updateBtnSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^void(id self, id viewModel, UIView *view) {
                    ((void(*)(id, SEL, id, UIView *))orig)(self, updateBtnSel, viewModel, view);
                    TriggerNativeTranslateOnAdapter(self, view, viewModel);
                }));
                XLog(@"[Hook成功] T1StandardStatusTranslateAdapter -> _t1_updateManualTranslateButtonForViewModel:forView:");
            }
        }
    }

    // 3. 挂钩 T1ConversationTranslatedBodyAdapter（仅在真正存在译文时显示译文区域）
    Class bodyAdapterCls = objc_getClass("T1ConversationTranslatedBodyAdapter");
    if (bodyAdapterCls) {
        SEL visSel = NSSelectorFromString(@"shouldBeVisibleForViewModel:");
        SEL transVMSel = NSSelectorFromString(@"translatedViewModelForViewModel:");
        if (CanHook(bodyAdapterCls, visSel)) {
            Method m = class_getInstanceMethod(bodyAdapterCls, visSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^BOOL(id self, id viewModel) {
                    BOOL origVal = ((BOOL(*)(id, SEL, id))orig)(self, visSel, viewModel);
                    id transVM = nil;
                    if (IsAutoTranslateEnabled() && XATObjectArguments([self methodSignatureForSelector:transVMSel], 1, '@')) {
                        transVM = ((id(*)(id, SEL, id))objc_msgSend)(self, transVMSel, viewModel);
                        static char availabilityKey;
                        NSNumber *availability = @((origVal ? 2 : 0) | (transVM ? 1 : 0));
                        if (viewModel && ![availability isEqual:objc_getAssociatedObject(viewModel, &availabilityKey)]) {
                            objc_setAssociatedObject(viewModel, &availabilityKey, availability, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            XLog(@"[译文模型检查] ID=%@ nativeVisible=%@ translatedModel=%@", ExtractTweetID(viewModel) ?: @"未暴露",
                                 origVal ? @"YES" : @"NO", transVM ? @"YES" : @"NO");
                        }
                    }
                    return origVal || transVM != nil;
                }));
                XLog(@"[Hook成功] T1ConversationTranslatedBodyAdapter -> shouldBeVisibleForViewModel:");
            }
        }
    }

    // 4. 挂钩 T1TranslationToggleEventHandler 与 T1GrokTranslateEventHandler（监控原生事件处理）
    NSArray *handlerNames = @[@"T1TranslationToggleEventHandler", @"T1GrokTranslateEventHandler", @"T1GrokAutoTranslateEventHandler"];
    for (NSString *hName in handlerNames) {
        Class hCls = objc_getClass([hName UTF8String]);
        if (!hCls) continue;
        SEL hSel = NSSelectorFromString(@"handleStatusViewEvent:controller:");
        if (CanHook(hCls, hSel)) {
            Method m = class_getInstanceMethod(hCls, hSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^void(id self, id event, id controller) {
                    XLog(@"[原生事件命中] %@ -> handleStatusViewEvent:controller: (%@)", hName, NSStringFromClass([controller class]));
                    ((void(*)(id, SEL, id, id))orig)(self, hSel, event, controller);
                }));
            }
        }
    }

    // 5. 挂钩 T1PostTranslationInfo（监控翻译结果与真实报错原因）
    Class infoCls = objc_getClass("T1PostTranslationInfo");
    if (infoCls) {
        SEL stateSel = NSSelectorFromString(@"setState:");
        if (CanHook(infoCls, stateSel)) {
            Method m = class_getInstanceMethod(infoCls, stateSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^void(id self, long long state) {
                    XLog(@"[原生翻译状态改变] T1PostTranslationInfo -> state = %lld", state);
                    ((void(*)(id, SEL, long long))orig)(self, stateSel, state);
                }));
            }
        }

        SEL errSel = NSSelectorFromString(@"setTranslationError:");
        if (CanHook(infoCls, errSel)) {
            Method m = class_getInstanceMethod(infoCls, errSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^void(id self, NSError *err) {
                    if (err) {
                        XLog(@"[原生翻译报错详情] %@", err);
                    }
                    ((void(*)(id, SEL, id))orig)(self, errSel, err);
                }));
            }
        }
    }

    // 6. 开启 Status / ViewModel 的 isTranslatable 权限
    NSArray *statusClasses = @[@"TFNTwitterStatus", @"T1TwitterCoreStatusViewModelAdapter", @"T1CompositionStatusViewModel"];
    for (NSString *sName in statusClasses) {
        Class sCls = objc_getClass([sName UTF8String]);
        if (!sCls) continue;
        SEL transSel = NSSelectorFromString(@"isTranslatable");
        if (CanHook(sCls, transSel)) {
            Method m = class_getInstanceMethod(sCls, transSel);
            if (m) {
                IMP orig = method_getImplementation(m);
                method_setImplementation(m, imp_implementationWithBlock(^BOOL(id self) {
                    if (IsAutoTranslateEnabled() && ShouldTranslateViewModel(self)) {
                        return YES;
                    }
                    return ((BOOL(*)(id, SEL))orig)(self, transSel);
                }));
                XLog(@"[Hook成功] %@ -> isTranslatable", sName);
            }
        }
    }
}

// ==================== 悬浮球 & 菜单 ====================
static void ShowSettingsMenu(void);

@interface XFloatBtn : UIButton
@property (nonatomic, assign) CGPoint startPoint;
@end

@implementation XFloatBtn
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UITouch *t = [touches anyObject];
    self.startPoint = [t locationInView:self];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    UITouch *t = [touches anyObject];
    CGPoint cur = [t locationInView:self.superview];
    self.center = CGPointMake(cur.x, cur.y);
}
- (void)onButtonClicked {
    ShowSettingsMenu();
}
@end

static void ShowLogViewer(UIViewController *rootVC) {
    [gLogLock lock];
    NSString *fullLog = [gLogList componentsJoinedByString:@"\n"];
    [gLogLock unlock];

    UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"运行日志"
                                                                      message:fullLog.length > 0 ? fullLog : @"(暂无日志)"
                                                               preferredStyle:UIAlertControllerStyleAlert];

    [logAlert addAction:[UIAlertAction actionWithTitle:@"一键复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = fullLog;
    }]];

    [logAlert addAction:[UIAlertAction actionWithTitle:@"导出为 TXT 文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"XAutoTranslate_Native.log"];
        [fullLog writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSURL *fileURL = [NSURL fileURLWithPath:tmpPath];
        UIActivityViewController *actVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        [rootVC presentViewController:actVC animated:YES completion:nil];
    }]];

    [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [rootVC presentViewController:logAlert animated:YES completion:nil];
}

static void ShowSettingsMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        UIViewController *topVC = window.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;
        if (!topVC) return;

        BOOL isEnabled = IsAutoTranslateEnabled();

        NSString *title = [NSString stringWithFormat:@"X 原生自动翻译 (当前: %@)", isEnabled ? @"✅ 开启" : @"❌ 关闭"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:[NSString stringWithFormat:@"已提交原生翻译: %lu 次", (unsigned long)gSubmissionCount]
                                                                preferredStyle:UIAlertControllerStyleActionSheet];

        [alert addAction:[UIAlertAction actionWithTitle:(isEnabled ? @"暂停自动翻译" : @"开启自动翻译")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] setBool:!isEnabled forKey:kPrefAutoTranslateEnabled];
            [[NSUserDefaults standardUserDefaults] synchronize];
            if (!isEnabled) XATScanVisibleBindings();
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"清除已触发记录 (重新触发当前页)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            for (UIView *view in gTrackedViews.allObjects) {
                XATViewBinding *binding = objc_getAssociatedObject(view, &kBindingKey);
                id vm = binding.viewModel;
                if (vm) objc_setAssociatedObject(XATRequestOwner(vm), &kRequestKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                binding.nextAttempt = 0;
                binding.waitingLogged = NO;
            }
            [gRecentRequests removeAllObjects];
            gSubmissionCount = 0;
            XATScanVisibleBindings();
            XLog(@"[提示] 已重置触发记录");
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"查看与导出运行日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            ShowLogViewer(topVC);
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

static void SetupFloatingButton(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        if (!window) return;

        XFloatBtn *btn = [XFloatBtn buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(window.bounds.size.width - 55, window.bounds.size.height - 220, 44, 44);
        [btn setTitle:@"🌐" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:22];
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
        btn.layer.cornerRadius = 22;
        btn.layer.masksToBounds = YES;
        btn.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
        btn.layer.borderWidth = 1.5;

        [btn addTarget:btn action:@selector(onButtonClicked) forControlEvents:UIControlEventTouchUpInside];
        [window addSubview:btn];
        XLog(@"[UI] 悬浮控制球挂载完毕");
    });
}

// ==================== 构造入口 ====================
__attribute__((constructor)) static void initTweak(void) {
    @autoreleasepool {
        gLogList = [[NSMutableArray alloc] init];
        gLogLock = [[NSLock alloc] init];
        gHookedKeys = [[NSMutableSet alloc] init];
        gTrackedViews = [NSHashTable weakObjectsHashTable];
        gRecentRequests = [NSCache new];
        gRecentRequests.countLimit = 200;

        XLog(@"=== XAutoTranslate (时间线触发修复版 1.1) 启动 ===");

        dispatch_async(dispatch_get_main_queue(), ^{
            InstallTargetedNativeHooks();
            SetupFloatingButton();
            NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
                XATScanVisibleBindings();
            }];
            [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            InstallTargetedNativeHooks();
        });
    }
}
