// XAutoTranslate v3 diagnostic build: X 12.33 (31), iOS 17.2+. Native translation + language preferences.
#include <stdbool.h>
#include "XDiagnostics.h"
extern unsigned long strlen(const char *);
extern int strcmp(const char *, const char *);
extern int strcasecmp(const char *, const char *);
extern int strncasecmp(const char *, const char *, unsigned long);

typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void *Method;
typedef void (*IMP)(void);
extern Class object_getClass(id);
extern const char *class_getName(Class);
extern Class class_getSuperclass(Class);
extern int snprintf(char *, unsigned long, const char *, ...);
extern Class objc_getClass(const char *);
extern SEL sel_registerName(const char *);
extern Method class_getInstanceMethod(Class, SEL);
extern bool class_addMethod(Class, SEL, IMP, const char *);
extern IMP method_getImplementation(Method);
extern IMP method_setImplementation(Method, IMP);
extern const char *method_getTypeEncoding(Method);
extern id objc_getAssociatedObject(id, const void *);
extern void objc_setAssociatedObject(id, const void *, id, unsigned long);
extern void objc_msgSend(void);
extern id objc_retain(id);
extern void objc_release(id);
extern void *dlsym(void *, const char *);
extern struct dispatch_queue_s _dispatch_main_q;
extern void dispatch_async_f(struct dispatch_queue_s *, void *, void (*)(void *));

#define S(s) sel_registerName(s)
#define M0(o,s) ((id (*)(id,SEL))objc_msgSend)((o),S(s))
#define M1(o,s,a) ((id (*)(id,SEL,id))objc_msgSend)((o),S(s),(a))
#define B0(o,s) ((bool (*)(id,SEL))objc_msgSend)((o),S(s))
#define N0(o,s) ((long (*)(id,SEL))objc_msgSend)((o),S(s))
#define HAS(o,s) ((bool (*)(id,SEL,SEL))objc_msgSend)((o),S("respondsToSelector:"),S(s))

extern void *malloc(unsigned long);
extern void free(void *);
extern unsigned long long dispatch_time(unsigned long long, long long);
extern void dispatch_after_f(unsigned long long, struct dispatch_queue_s *, void *, void (*)(void *));

typedef struct { Class cls; IMP layout, moved, handler; } HookSlot;
static HookSlot hooks[3];
static id eventType, translationHelper;
static char pendingKey, ignoredKey, languageCheckedKey, observationPendingKey, observationCountKey, retryUsedKey;

#if XAD_DIAGNOSTICS
static unsigned long callbackCounts[3][3], routedEvents;
static const char *installStatus = "INSTALL_PENDING";
static char diagnosticStampKey, diagnosticDisplayKey, diagnosticLanguageKey;
static const char *className(id o) { const char *n = o ? class_getName(object_getClass(o)) : 0; return n ? n : "nil"; }
static void diagCallback(unsigned slot, unsigned kind) {
    unsigned long n = ++callbackCounts[slot][kind];
    if (n <= 3 || !(n & (n-1))) XADLog("CALLBACK", "slot=%u kind=%u count=%lu", slot, kind, n);
}
static const char *readiness(id v) {
    if (!M0(v,"window")) return "NO_WINDOW";
    if (B0(v,"isHidden")) return "VIEW_HIDDEN";
    if (!M0(v,"viewModel")) return "NO_MODEL";
    if (!M0(v,"account")) return "NO_ACCOUNT";
    id h = M0(v,"eventHandler");
    if (!h) return "NO_HANDLER";
    return HAS(h,"handleStatusViewEvent:") ? "READY" : "HANDLER_SELECTOR_MISSING";
}
static void diagDecision(id v, id model, const char *why, long state) {
    char stamp[256];
    snprintf(stamp,sizeof(stamp),"%p:%s:%ld",model,why,state);
    id old = objc_getAssociatedObject(v,&diagnosticStampKey);
    const char *previous = old ? M0(old,"UTF8String") : 0;
    if (previous && !strcmp(previous,stamp)) return;
    id value = M1(objc_getClass("NSString"),"stringWithUTF8String:",stamp);
    objc_setAssociatedObject(v,&diagnosticStampKey,value,1);
    XADLog("DECISION","view=%p class=%s model=%p modelClass=%s reason=%s state=%ld",v,className(v),model,className(model),why,state);
}
static void diagDisplay(id view, id model, id info) {
    Class c = objc_getClass("T1GrokPostTranslationDisplayHelper");
    bool focal = hooks[1].cls && ((bool (*)(id,SEL,Class))objc_msgSend)(view,S("isKindOfClass:"),hooks[1].cls);
    id helper = c && class_getInstanceMethod(c,S("initWithStatusViewModel:account:forFocalView:")) ?
        ((id (*)(id,SEL,id,id,bool))objc_msgSend)(M0(c,"alloc"),S("initWithStatusViewModel:account:forFocalView:"),model,M0(view,"account"),focal) : 0;
    const char *names[] = {"shouldDisplayManualTranslateText","shouldDisplayAutoTranslateText","shouldDisplayManualTranslateButton","shouldDisplayAutoTranslateButton"};
    int flags[4];
    for (unsigned i=0;i<4;i++) flags[i] = helper && HAS(helper,names[i]) ? (int)B0(helper,names[i]) : -1;
    id error = info && HAS(info,"translationError") ? M0(info,"translationError") : 0;
    id message = error && HAS(error,"message") ? M0(error,"message") : 0;
    id automatic = HAS(model,"grokTranslatedPost") ? M0(model,"grokTranslatedPost") : 0;
    id text = automatic && HAS(automatic,"translation") ? M0(automatic,"translation") : 0;
    id preview = automatic && HAS(automatic,"previewTranslation") ? M0(automatic,"previewTranslation") : 0;
    long state = info && HAS(info,"state") ? N0(info,"state") : -1;
    char stamp[320];
    snprintf(stamp,sizeof(stamp),"%p:%ld:%d:%d:%d:%d:%p:%p:%p:%p",model,state,flags[0],flags[1],flags[2],flags[3],error,text,preview,info ? M0(info,"translatedStatus") : 0);
    id old = objc_getAssociatedObject(view,&diagnosticDisplayKey);
    const char *previous = old ? M0(old,"UTF8String") : 0;
    if (previous && !strcmp(previous,stamp)) { objc_release(helper); return; }
    id stampObject=M1(objc_getClass("NSString"),"stringWithUTF8String:",stamp);
    objc_setAssociatedObject(view,&diagnosticDisplayKey,stampObject,1);
    XADLog("DISPLAY","model=%p focal=%d state=%ld cached=%d manualText=%d autoText=%d manualButton=%d autoButton=%d autoLength=%ld previewLength=%ld errorClass=%s errorCode=%ld messageLength=%ld result=%s",
        model,focal,state,info && M0(info,"translatedStatus") != 0,flags[0],flags[1],flags[2],flags[3],
        text && HAS(text,"length") ? N0(text,"length") : 0,preview && HAS(preview,"length") ? N0(preview,"length") : 0,
        className(error),error && HAS(error,"code") ? N0(error,"code") : 0,message && HAS(message,"length") ? N0(message,"length") : 0,
        state == 3 && flags[0] == 0 && flags[1] == 0 ? "HIDDEN_BY_NATIVE_DISPLAY_GATE" : "DISPLAY_FLAGS_ONLY_NOT_VISUAL_CONFIRMATION");
    objc_release(helper);
}
static id diagItem(id a, unsigned long i) { return ((id (*)(id,SEL,unsigned long))objc_msgSend)(a,S("objectAtIndex:"),i); }
static void diagTree(id v, unsigned depth, unsigned *budget) {
    if (!v || !*budget || depth > 10 || B0(v,"isHidden")) return;
    --*budget;
    bool candidate = HAS(v,"viewModel") || HAS(v,"eventHandler");
    const char *parent=class_getName(class_getSuperclass(object_getClass(v)));
    XADLog("VIEW_TREE","depth=%u view=%p class=%s super=%s modelGetter=%d handlerGetter=%d accountGetter=%d",
        depth,v,className(v),parent ? parent : "nil",HAS(v,"viewModel"),HAS(v,"eventHandler"),HAS(v,"account"));
    if (candidate) {
        id model = HAS(v,"viewModel") ? M0(v,"viewModel") : 0;
        bool matched=false;
        for (unsigned i=0;i<3;i++) if (hooks[i].cls && ((bool (*)(id,SEL,Class))objc_msgSend)(v,S("isKindOfClass:"),hooks[i].cls)) matched=true;
        id info = model && matched && translationHelper ? M1(translationHelper,"getInfoFor:",model) : 0;
        XADLog("VIEW_CENSUS","depth=%u view=%p class=%s super=%s model=%p modelClass=%s accountGetter=%d handlerGetter=%d languageGetter=%d textGetter=%d state=%ld",
            depth,v,className(v),parent ? parent : "nil",model,className(model),HAS(v,"account"),HAS(v,"eventHandler"),HAS(model,"language"),HAS(model,"text"),info ? N0(info,"state") : -1);
        if (model && matched && HAS(v,"account")) diagDisplay(v,model,info);
    }
    id children = HAS(v,"subviews") ? M0(v,"subviews") : 0;
    unsigned long n = (unsigned long)N0(children,"count");
    for (unsigned long i=0;i<n && *budget;i++) diagTree(diagItem(children,i),depth+1,budget);
}
static void diagSnapshot(void) {
    XADLog("SNAPSHOT","status=%s routed=%lu",installStatus,routedEvents);
    for (unsigned i=0;i<3;i++) XADLog("HEALTH","slot=%u class=%p layout=%lu moved=%lu handler=%lu",i,hooks[i].cls,callbackCounts[i][0],callbackCounts[i][1],callbackCounts[i][2]);
    id app=M0(objc_getClass("UIApplication"),"sharedApplication");
    id scenes=M0(M0(app,"connectedScenes"),"allObjects");
    unsigned budget=400;
    for (unsigned long i=0;i<(unsigned long)N0(scenes,"count") && budget;i++) {
        id scene=diagItem(scenes,i);
        id windows=HAS(scene,"windows") ? M0(scene,"windows") : 0;
        for (unsigned long j=0;j<(unsigned long)N0(windows,"count") && budget;j++) diagTree(diagItem(windows,j),0,&budget);
    }
    XADLog("SNAPSHOT","view_census_remaining=%u limit=400 depth=10",budget);
}
static void diagHealth(void *unused) { (void)unused; diagSnapshot(); }
#else
#define diagCallback(...) ((void)0)
#define diagDecision(...) ((void)0)
#define diagDisplay(...) ((void)0)
#endif

// Uses the same exported Swift action and submission path as X's language switch.
#define SWIFT __attribute__((swiftcall))
#define CONTEXT __attribute__((swift_context))
typedef struct { void *value; unsigned long state; } MetadataResponse;
typedef struct { unsigned long low, high; } SwiftString;
typedef MetadataResponse (*MetadataFunction)(unsigned long) SWIFT;
typedef SwiftString (*BridgeStringFunction)(id) SWIFT;
typedef id (*LanguageActionFunction)(bool, unsigned long, unsigned long, void * CONTEXT) SWIFT;
typedef id (*SubmitActionFunction)(id *, id, void *, void *, const char *,
    unsigned long, unsigned long, unsigned long, void *, void *, void *, void * CONTEXT) SWIFT;
typedef void (*StartActionFunction)(void * CONTEXT) SWIFT;
typedef void (*SetDisabledFunction)(bool, unsigned long, unsigned long, bool, void * CONTEXT) SWIFT;
typedef void *(*SharedPreferenceFunction)(void) SWIFT;

static MetadataFunction languageMetadata;
static BridgeStringFunction bridgeString;
static LanguageActionFunction newLanguageAction;
static SubmitActionFunction submitAction;
static StartActionFunction startAction;
static SetDisabledFunction setLanguageDisabled;
static SharedPreferenceFunction sharedPreference;
static void *requestWitness, *errorWitness;
static void (*releaseSwift)(void *);
static void (*releaseBridge)(void *);
static id enabledLanguages;

#if XAD_DIAGNOSTICS
// Include after the core runtime declarations/macros and XADLog definition.
// Observes standard NSOperation flags only. Never interprets Swift Result.
typedef id (*XADExecutionOperationGetter)(void * __attribute__((swift_context)))
    __attribute__((swiftcall));
typedef struct { id execution, language; unsigned sample; } XADExecutionWatch;
static XADExecutionOperationGetter xadOperationGetter;

static const char *xadDiagnosticLanguage(id language) {
    if (!language || !HAS(language, "UTF8String")) return "unknown";
    const char *code = M0(language, "UTF8String");
    if (!code || !*code) return "unknown";
    unsigned i;
    for (i = 0; i < 24 && code[i]; ++i) {
        char c = code[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '_')) return "invalid";
    }
    return i == 24 ? "invalid" : code;
}

static bool xadTraceOperation(id execution, id language, unsigned sample) {
    id operation = xadOperationGetter(execution); // Verified native +1 getter.
    if (!operation) {
        XADLog("LANG_EXEC", "lang=%s sample=%u operation=nil status=SUBMITTED_NOT_CONFIRMED",
            xadDiagnosticLanguage(language), sample);
        return false;
    }
    bool ready = HAS(operation, "isReady") && B0(operation, "isReady");
    bool executing = HAS(operation, "isExecuting") && B0(operation, "isExecuting");
    bool finished = HAS(operation, "isFinished") && B0(operation, "isFinished");
    bool cancelled = HAS(operation, "isCancelled") && B0(operation, "isCancelled");
    const char *name = class_getName(object_getClass(operation));
    XADLog("LANG_EXEC", "lang=%s sample=%u operation=%s ready=%d executing=%d finished=%d cancelled=%d status=SUBMITTED_NOT_CONFIRMED save=NOT_SERVER_SAVE_CONFIRMED",
        xadDiagnosticLanguage(language), sample, name ? name : "unknown",
        ready, executing, finished, cancelled);
    objc_release(operation);
    return finished || cancelled;
}

static void xadExecutionWatchTick(void *context) {
    XADExecutionWatch *watch = context;
    ++watch->sample;
    bool terminal = xadTraceOperation(watch->execution, watch->language, watch->sample);
    if (!terminal && watch->sample < 4) {
        // Sample at approximately 1, 3, 7 and 15 seconds after submission.
        long long delay = (1LL << watch->sample) * 1000000000LL;
        dispatch_after_f(dispatch_time(0, delay), &_dispatch_main_q, watch, xadExecutionWatchTick);
        return;
    }
    if (!terminal) XADLog("LANG_EXEC", "lang=%s watch=ENDED_BOUNDED status=SUBMITTED_NOT_CONFIRMED save=NOT_SERVER_SAVE_CONFIRMED",
        xadDiagnosticLanguage(watch->language));
    objc_release(watch->language);
    objc_release(watch->execution);
    free(watch);
}

static void diagWatchExecution(id execution, id language) {
    if (!execution) {
        XADLog("LANG_EXEC", "lang=%s execution=nil status=NOT_SUBMITTED", xadDiagnosticLanguage(language));
        return;
    }
    if (!xadOperationGetter) xadOperationGetter = dlsym((void *)-2,
        "$s20TwitterActionService03AnyB9ExecutionC19typeErasedOperationSo11NSOperationCvg");
    if (!xadOperationGetter) {
        XADLog("LANG_EXEC", "lang=%s operation_getter=UNAVAILABLE status=SUBMITTED_NOT_CONFIRMED",
            xadDiagnosticLanguage(language));
        return;
    }
    if (xadTraceOperation(execution, language, 0)) return;
    XADExecutionWatch *watch = malloc(sizeof(*watch));
    if (!watch) {
        XADLog("LANG_EXEC", "lang=%s watch=ALLOC_FAILED status=SUBMITTED_NOT_CONFIRMED",
            xadDiagnosticLanguage(language));
        return;
    }
    watch->execution = objc_retain(execution);
    watch->language = objc_retain(language);
    watch->sample = 0;
    dispatch_after_f(dispatch_time(0, 1000000000LL), &_dispatch_main_q, watch, xadExecutionWatchTick);
}

#else
#define diagWatchExecution(...) ((void)0)
#endif

static bool resolveLanguageDefaults(void) {
    languageMetadata = dlsym((void *)-2, "$s14GraphQLActions36AutoTranslateLanguageControlMutationCMa");
    bridgeString = dlsym((void *)-2, "$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ");
    newLanguageAction = dlsym((void *)-2, "$s14GraphQLActions36AutoTranslateLanguageControlMutationC6enable8languageACSb_SStcfC");
    submitAction = dlsym((void *)-2, "$s20TwitterActionService0bC0C14GraphQLActionsE21submitWithoutThrowing_18transactionMetrics10completion4file4lineAA0B9ExecutionCyxGSgx_So014TNUTransactionJ0CSgys6ResultOy11SuccessTypeQz05ErrorR0QzGcSgs12StaticStringVSutAD011HTTPRequestB0RzAD0bc8InternalS0AVRQlF");
    startAction = dlsym((void *)-2, "$s20TwitterActionService03AnyB9ExecutionC5startyyF");
    setLanguageDisabled = dlsym((void *)-2, "$s12TweetDetails41GrokAutoTranslateLanguagePreferenceHelperC03setdE8Disabled_3for6notifyySb_SSSbtF");
    sharedPreference = dlsym((void *)-2, "$s12TweetDetails41GrokAutoTranslateLanguagePreferenceHelperC6sharedACvau");
    requestWitness = dlsym((void *)-2, "$s14GraphQLActions36AutoTranslateLanguageControlMutationCAA17HTTPRequestActionAAWP");
    errorWitness = dlsym((void *)-2, "$s14GraphQLActions30HTTPRequestActionResponseErrorOAA0d15ServiceInternalF0AAWP");
    releaseSwift = dlsym((void *)-2, "swift_release");
    releaseBridge = dlsym((void *)-2, "swift_bridgeObjectRelease");
    if (!languageMetadata || !bridgeString || !newLanguageAction || !submitAction ||
        !startAction || !setLanguageDisabled || !sharedPreference || !requestWitness ||
        !errorWitness || !releaseSwift || !releaseBridge) {
        XADLog("NATIVE", "language bridge unavailable metadata=%p string=%p ctor=%p submit=%p start=%p localSetter=%p shared=%p requestWitness=%p errorWitness=%p release=%p bridgeRelease=%p", (void *)languageMetadata,(void *)bridgeString,(void *)newLanguageAction,(void *)submitAction,(void *)startAction,(void *)setLanguageDisabled,(void *)sharedPreference,requestWitness,errorWitness,(void *)releaseSwift,(void *)releaseBridge);
        return false;
    }
    enabledLanguages = M0(objc_getClass("NSMutableDictionary"), "new");
    XADLog("NATIVE","language bridge symbols resolved dictionary=%p",enabledLanguages);
    return enabledLanguages != 0;
}

static bool enableLanguage(id account, id language) {
    if (!enabledLanguages || !account || !language) return false;
    id accountID = M0(account, "accountID");
    id code = M0(language, "lowercaseString");
    if (!accountID || !code) { XADLog("LANG","accountID or language unavailable (values not recorded)"); return false; }
    id seen = M1(enabledLanguages, "objectForKey:", accountID);
    if (seen && ((bool (*)(id,SEL,id))objc_msgSend)(seen, S("containsObject:"), code)) return true;
    id manager = M0(objc_getClass("TFSTwitterServiceRunner"), "actionServiceManager");
    id service = M1(manager, "actionServiceForAccountID:", accountID);
    if (!service) { XADLog("LANG","action service unavailable"); return false; }
    MetadataResponse metadata = languageMetadata(0);
    if (!metadata.value) { XADLog("LANG","metadata unavailable"); return false; }
    SwiftString string = bridgeString(code);
    // String ownership passes into the native action constructor.
    id action = newLanguageAction(true, string.low, string.high, metadata.value);
    if (!action) { XADLog("LANG","native action construction failed"); return false; }
    static const char file[] = "XAutoTranslate.c";
    id execution = submitAction(&action, 0, 0, 0, file, sizeof(file)-1, 2, 1,
        metadata.value, requestWitness, errorWitness, service);
    releaseSwift(action);
    if (!execution) { XADLog("LANG","submission returned nil execution; not submitted"); return false; }
    if (!seen) {
        seen = M0(objc_getClass("NSMutableSet"), "new");
        ((void (*)(id,SEL,id,id))objc_msgSend)(enabledLanguages, S("setObject:forKey:"), seen, accountID);
        objc_release(seen);
    }
    M1(seen, "addObject:", code);
    XADLog("LANG","lang=%s native enable action starting; SUBMITTED_NOT_CONFIRMED",xadDiagnosticLanguage(code));
    startAction(execution);
    diagWatchExecution(execution,code);
    objc_release(execution);
    void **preference = sharedPreference();
    if (preference && *preference) {
        // Clear X's local language exclusion and notify visible views immediately.
        SwiftString borrowed = bridgeString(code);
        setLanguageDisabled(false, borrowed.low, borrowed.high, true, *preference);
        // The setter borrows its String argument; its bridge reference is released.
        releaseBridge((void *)borrowed.high);
        XADLog("LANG","local language exclusion cleared; notify=true; server save unconfirmed");
    }
    else XADLog("LANG","local preference singleton unavailable");
    return true;
}


static bool chinese(const char *s) {
    static const char *const codes[] = {"zh", "zho", "chi", "cmn", "yue", "wuu", "nan", "hak", "gan", "hsn"};
    if (!s) return false;
    for (unsigned i = 0; i < sizeof(codes) / sizeof(*codes); ++i) {
        unsigned long n = strlen(codes[i]);
        if (!strncasecmp(s, codes[i], n) && (!s[n] || s[n] == '-' || s[n] == '_')) return true;
    }
    return false;
}


static void translate(id view, bool observing);
static bool ready(id view);

static unsigned observations(id model) {
    id n = objc_getAssociatedObject(model, &observationCountKey);
    return n ? (unsigned)N0(n, "unsignedLongValue") : 0;
}

typedef struct { id view, model; } Observation;
static void observeVisible(void *context) {
    Observation *r = context;
    bool owns = objc_getAssociatedObject(r->model, &observationPendingKey) == r->view;
    if (owns) objc_setAssociatedObject(r->model, &observationPendingKey, 0, 1);
    XADLog("OBSERVE","fired model=%p view=%p owns=%d sameModel=%d",r->model,r->view,owns,M0(r->view,"viewModel")==r->model);
    if (owns && M0(r->view, "viewModel") == r->model) translate(r->view, true);
    objc_release(r->model);
    objc_release(r->view);
    free(r);
}

static void queueObservation(id view, id model) {
    unsigned count = observations(model);
    id owner = objc_getAssociatedObject(model, &observationPendingKey);
    if (count >= 10) { diagDecision(view,model,"OBSERVATION_LIMIT_10",-1); return; }
    if (owner && ready(owner) && M0(owner,"viewModel") == model) return;
    XADLog("OBSERVE","model=%p view=%p attempt=%u oldOwner=%p delay=2s",model,view,count+1,owner);
    Observation *r = malloc(sizeof(*r));
    if (!r) return;
    id number = ((id (*)(id,SEL,unsigned long))objc_msgSend)(
        objc_getClass("NSNumber"), S("numberWithUnsignedLong:"), count + 1);
    if (!number) { free(r); return; }
    r->view = objc_retain(view);
    r->model = objc_retain(model);
    objc_setAssociatedObject(model, &observationCountKey, number, 1);
    objc_setAssociatedObject(model, &observationPendingKey, view, 1);
    dispatch_after_f(dispatch_time(0, 2000000000LL), &_dispatch_main_q, r, observeVisible);
}

static bool ready(id view) {
    id handler = M0(view, "eventHandler");
    return M0(view, "window") && !B0(view, "isHidden") &&
        M0(view, "viewModel") && M0(view, "account") && handler &&
        HAS(handler, "handleStatusViewEvent:");
}

static bool autoOriginal(id model) {
    Class cls = objc_getClass("_TtC12TweetDetails27GrokPostAutoTranslateHelper");
    if (!cls || !HAS(cls, "shared")) return false;
    id helper = M0(cls, "shared");
    if (!helper || !HAS(helper, "isShowingOriginalFor:")) return false;
    id status = HAS(model, "representedStatus") ? M0(model, "representedStatus") : model;
    if (!status || !HAS(status, "statusID")) return false;
    long long statusID = ((long long (*)(id,SEL))objc_msgSend)(status, S("statusID"));
    return ((bool (*)(id,SEL,long long))objc_msgSend)(helper, S("isShowingOriginalFor:"), statusID);
}

static bool nonempty(id string) { return string && HAS(string, "length") && N0(string, "length") > 0; }

static bool autoDisplayed(id view, id model) {
    id automatic = HAS(model, "grokTranslatedPost") ? M0(model, "grokTranslatedPost") : 0;
    if (!automatic) return false;
    id text = HAS(automatic, "translation") ? M0(automatic, "translation") : 0;
    id preview = HAS(automatic, "previewTranslation") ? M0(automatic, "previewTranslation") : 0;
    if (!nonempty(text) && !nonempty(preview)) return false;
    Class cls = objc_getClass("T1GrokPostTranslationDisplayHelper");
    if (!cls || !class_getInstanceMethod(cls, S("initWithStatusViewModel:account:forFocalView:")) ||
        !class_getInstanceMethod(cls, S("shouldDisplayAutoTranslateText"))) return false;
    bool focal = hooks[1].cls && ((bool (*)(id,SEL,Class))objc_msgSend)(view, S("isKindOfClass:"), hooks[1].cls);
    id helper = ((id (*)(id,SEL,id,id,bool))objc_msgSend)(M0(cls, "alloc"),
        S("initWithStatusViewModel:account:forFocalView:"), model, M0(view, "account"), focal);
    bool shown = helper && B0(helper, "shouldDisplayAutoTranslateText");
    objc_release(helper);
    return shown;
}

static void translate(id view, bool observing) {
    id model = 0;
    if (!ready(view)) { diagDecision(view,0,readiness(view),-1); return; }
    model = objc_retain(M0(view, "viewModel"));
    if (!HAS(model,"language")) { diagDecision(view,model,"LANGUAGE_GETTER_MISSING",-1); goto done; }
    if (objc_getAssociatedObject(model,&ignoredKey)) goto done;
    id language = M0(model, "language");
    const char *code = M0(language, "UTF8String");
    bool detected = false;
    if (!code || !*code || !strcasecmp(code, "und")) {
        id text = HAS(model, "text") ? M0(model, "text") : 0;
        if (!text) { diagDecision(view,model,"NO_LANGUAGE_AND_NO_TEXT",-1); goto done; }
        language = M1(objc_getClass("NSLinguisticTagger"), "dominantLanguageForString:", text);
        code = M0(language, "UTF8String");
        detected = true;
    }
    if (!code || !*code) { diagDecision(view,model,"LANGUAGE_DETECTION_EMPTY",-1); goto done; }
#if XAD_DIAGNOSTICS
    if (!objc_getAssociatedObject(model,&diagnosticLanguageKey)) {
        XADLog("LANGUAGE","model=%p code=%s source=%s",model,xadDiagnosticLanguage(language),detected ? "LOCAL_DETECTOR" : "NATIVE_MODEL");
        objc_setAssociatedObject(model,&diagnosticLanguageKey,eventType,1);
    }
#endif
    (void)detected;
    if (chinese(code) || !strcasecmp(code, "und") || !strcasecmp(code, "zxx")) {
        diagDecision(view,model,chinese(code) ? "CHINESE_EXCLUDED" : "UNDETERMINED_LANGUAGE",-1);
        objc_setAssociatedObject(model, &ignoredKey, eventType, 1);
        goto done;
    }
    id account = objc_retain(M0(view, "account"));
    bool enabled = enableLanguage(account, language);
    diagDecision(view,model,enabled ? "LANGUAGE_ACTION_SUBMITTED_OR_ALREADY_SEEN" : "LANGUAGE_ENABLE_UNAVAILABLE",-1);
    objc_release(account);
    if (M0(view,"viewModel") != model || !ready(view)) { diagDecision(view,model,"MODEL_CHANGED_OR_VIEW_NOT_READY_AFTER_LANGUAGE_UPDATE",-1); goto done; }
    if (enabled) objc_setAssociatedObject(model, &languageCheckedKey, eventType, 1);
    else queueObservation(view, model);
    id info = M1(translationHelper, "getInfoFor:", model);
    long state = info ? N0(info, "state") : 0;
    diagDisplay(view,model,info);
    if (state == 3) { diagDecision(view,model,"NATIVE_STATE_3_CHECK_DISPLAY_FLAGS",state); goto done; }
    if (state == 0 && info && M0(info,"translatedStatus")) { diagDecision(view,model,"CACHED_ORIGINAL_PRESERVED",state); goto done; }
    if (autoOriginal(model)) { diagDecision(view,model,"NATIVE_SHOW_ORIGINAL_SET",state); goto done; }
    if (autoDisplayed(view,model)) { diagDecision(view,model,"AUTO_DISPLAY_GATE_TRUE",state); goto done; }
    if (state == 1 || state == 4) { diagDecision(view,model,state == 1 ? "NATIVE_IN_FLIGHT" : "NATIVE_STATE_4_NOOP",state); queueObservation(view, model); goto done; }
    if (state == 2) {
        if (objc_getAssociatedObject(model,&retryUsedKey)) { diagDecision(view,model,"ERROR_RETRY_ALREADY_USED",state); goto done; }
        if (!observing) { queueObservation(view, model); goto done; }
    } else if (state != 0) goto done;

    id event = ((id (*)(id,SEL,id,id,id))objc_msgSend)(
        M0(objc_getClass("TTACoreStatusViewEvent"), "alloc"),
        S("initWithEventType:statusView:sourceView:"), eventType, view, view);
    if (!event) { diagDecision(view,model,"NATIVE_EVENT_ALLOCATION_FAILED",state); queueObservation(view,model); goto done; }
    bool errorRetry = observing && state == 2;
    XADLog("ROUTE","before model=%p view=%p handlerClass=%s state=%ld errorRetry=%d",model,view,className(M0(view,"eventHandler")),state,errorRetry);
#if XAD_DIAGNOSTICS
    ++routedEvents;
#endif
    M1(M0(view, "eventHandler"), "handleStatusViewEvent:", event);
    objc_release(event);
    XADLog("ROUTE","event dispatched; delivery does not confirm translation");
    // Routing may ignore an event until its controller is ready.
    info = M1(translationHelper, "getInfoFor:", model);
    state = info ? N0(info, "state") : 0;
    XADLog("ROUTE","after model=%p state=%ld info=%p",model,state,info);
    diagDisplay(view,model,info);
    if (errorRetry && (state == 1 || state == 3 || state == 4 || (info && M0(info, "translatedStatus"))))
        objc_setAssociatedObject(model, &retryUsedKey, eventType, 1);
    if (M0(view, "viewModel") == model && ready(view) &&
        state != 3 && !(state == 0 && info && M0(info, "translatedStatus")) &&
        !(state == 2 && objc_getAssociatedObject(model, &retryUsedKey))) queueObservation(view, model);
 done:
    objc_release(model);
}

static void translateVisible(void *context) {
    id view = context;
    objc_setAssociatedObject(view, &pendingKey, 0, 1);
    translate(view, false);
    objc_release(view);
}

static void queueVisible(id view) {
    if (!ready(view)) { diagDecision(view,0,readiness(view),-1); return; }
    if (objc_getAssociatedObject(view,&pendingKey)) return;
    id model = M0(view, "viewModel");
    if (objc_getAssociatedObject(model, &ignoredKey) ||
        objc_getAssociatedObject(model, &observationPendingKey) == view || observations(model) >= 10) return;
    if (objc_getAssociatedObject(model, &languageCheckedKey)) {
        id info = M1(translationHelper, "getInfoFor:", model);
        long state = info ? N0(info, "state") : 0;
        if (state == 3 || (state == 0 && info && M0(info, "translatedStatus")) ||
            (state == 2 && objc_getAssociatedObject(model, &retryUsedKey)) ||
            autoOriginal(model) || autoDisplayed(view, model)) {
            diagDecision(view,model,"QUEUE_SKIPPED_NATIVE_TERMINAL_OR_ORIGINAL",state);
            diagDisplay(view,model,info);
            return;
        }
    }
    objc_setAssociatedObject(view, &pendingKey, eventType, 1);
    dispatch_async_f(&_dispatch_main_q, objc_retain(view), translateVisible);
}

#define WRAPPERS(n) \
static void layout_##n(id v, SEL s) { \
    ((void (*)(id,SEL))hooks[n].layout)(v,s); diagCallback(n,0); queueVisible(v); \
} \
static void moved_##n(id v, SEL s) { \
    ((void (*)(id,SEL))hooks[n].moved)(v,s); diagCallback(n,1); queueVisible(v); \
} \
static void handler_##n(id v, SEL s, id h) { \
    ((void (*)(id,SEL,id))hooks[n].handler)(v,s,h); diagCallback(n,2); queueVisible(v); \
}
WRAPPERS(0)
WRAPPERS(1)
WRAPPERS(2)

static bool hookMethod(Class cls, const char *name, IMP replacement, IMP *original) {
    SEL selector = S(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) { XADLog("HOOK","missing method=%s",name); return false; }
    *original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        *original = method_setImplementation(method, replacement);
    XADLog("HOOK","class=%s selector=%s original=%p replacement=%p encoding=%s",class_getName(cls),name,(void *)*original,(void *)replacement,method_getTypeEncoding(method));
    return true;
}

static void install(void *unused) {
    (void)unused;
    XADBootstrap("MAIN_QUEUE_INSTALL_ENTER");
    XADStart();
#if XAD_DIAGNOSTICS
    XADSetSnapshotHandler(diagSnapshot);
    dispatch_after_f(dispatch_time(0,10000000000LL),&_dispatch_main_q,0,diagHealth);
#endif
#if XAD_DIAGNOSTICS
    id device=M0(objc_getClass("UIDevice"),"currentDevice");
    XADLog("BOOT","iOS=%s device=%s",(const char *)M0(M0(device,"systemVersion"),"UTF8String"),(const char *)M0(M0(device,"model"),"UTF8String"));
#endif
    id bundle = M0(objc_getClass("NSBundle"), "mainBundle");
    id stringClass = objc_getClass("NSString");
    id versionKey = M1(stringClass, "stringWithUTF8String:", "CFBundleShortVersionString");
    id buildKey = M1(stringClass, "stringWithUTF8String:", "CFBundleVersion");
    const char *identifier = M0(M0(bundle, "bundleIdentifier"), "UTF8String");
    const char *version = M0(M1(bundle, "objectForInfoDictionaryKey:", versionKey), "UTF8String");
    const char *build = M0(M1(bundle, "objectForInfoDictionaryKey:", buildKey), "UTF8String");
    XADLog("BOOT","bundle=%s version=%s build=%s expected=com.atebits.Tweetie2/12.33/31",identifier ? identifier : "nil",version ? version : "nil",build ? build : "nil");
    if (!identifier || strcmp(identifier, "com.atebits.Tweetie2") ||
        !version || strcmp(version,"12.33") || !build || strcmp(build,"31")) {
        XADCoreStatus("翻译核心停用：应用或版本不匹配，查看 BOOT 日志");
#if XAD_DIAGNOSTICS
        installStatus="DISABLED_BUNDLE_VERSION_BUILD";
#endif
        return;
    }

    Class event = objc_getClass("TTACoreStatusViewEvent");
    Class helper = objc_getClass("T1PostTranslationHelper");
    if (!event || !helper ||
        !class_getInstanceMethod(event, S("initWithEventType:statusView:sourceView:")) ||
        !class_getInstanceMethod(helper,S("getInfoFor:")) || !HAS(helper,"shared")) {
        XADLog("INSTALL","native event/helper class or selector missing event=%p helper=%p",event,helper);
        XADCoreStatus("翻译核心停用：原生类或方法不存在");
#if XAD_DIAGNOSTICS
        installStatus="DISABLED_NATIVE_CLASS_OR_SELECTOR";
#endif
        return;
    }
    id *nativeEvent = dlsym((void *)-2, "T1StatusViewGrokTranslateEvent");
    if (!nativeEvent || !*nativeEvent) {
        XADCoreStatus("翻译核心停用：原生翻译事件不存在");
#if XAD_DIAGNOSTICS
        installStatus="DISABLED_EVENT_SYMBOL";
#endif
        XADLog("INSTALL","event symbol=%p value=%p",nativeEvent,nativeEvent ? *nativeEvent : 0);
        return;
    }
    eventType = objc_retain(*nativeEvent);
    translationHelper = objc_retain(M0(helper, "shared"));
    if (!translationHelper) { XADCoreStatus("翻译核心停用：翻译缓存实例不存在");
#if XAD_DIAGNOSTICS
        installStatus="DISABLED_CACHE_SINGLETON";
#endif
        return; }
    (void)resolveLanguageDefaults();
    const char *classes[] = {"T1StandardStatusView", "T1ConversationFocalStatusView", "T1QuotedStandardStatusView"};
    IMP layouts[] = {(IMP)layout_0, (IMP)layout_1, (IMP)layout_2};
    IMP moves[] = {(IMP)moved_0, (IMP)moved_1, (IMP)moved_2};
    IMP handlers[] = {(IMP)handler_0, (IMP)handler_1, (IMP)handler_2};
    unsigned installed=0;
    for (unsigned i = 0; i < 3; ++i) {
        Class cls = objc_getClass(classes[i]);
        XADLog("INSTALL","slot=%u class=%s present=%d viewModel=%d eventHandler=%d account=%d setter=%d",
            i,classes[i],cls != 0,cls && class_getInstanceMethod(cls,S("viewModel")) != 0,
            cls && class_getInstanceMethod(cls,S("eventHandler")) != 0,cls && class_getInstanceMethod(cls,S("account")) != 0,
            cls && class_getInstanceMethod(cls,S("setEventHandler:")) != 0);
        if (!cls || !class_getInstanceMethod(cls, S("viewModel")) ||
            !class_getInstanceMethod(cls, S("eventHandler")) ||
            !class_getInstanceMethod(cls, S("account")) ||
            !class_getInstanceMethod(cls,S("setEventHandler:"))) { XADLog("INSTALL","slot=%u class=%s skipped: class/getter/setter missing",i,classes[i]); continue; }
        hooks[i].cls = cls;
        hookMethod(cls, "layoutSubviews", layouts[i], &hooks[i].layout);
        hookMethod(cls, "didMoveToWindow", moves[i], &hooks[i].moved);
        hookMethod(cls,"setEventHandler:",handlers[i],&hooks[i].handler);
        if (hooks[i].layout && hooks[i].moved && hooks[i].handler) ++installed;
    }
    XADLog("INSTALL","installed=%u/3 languageBridge=%d",installed,enabledLanguages != 0);
    (void)installed;
    XADCoreStatus(installed ? "已挂接，等待翻译事件；是否显示请查看 DISPLAY 日志" : "翻译核心停用：没有匹配的帖子视图");
#if XAD_DIAGNOSTICS
    installStatus=installed ? "HOOKS_INSTALLED" : "NO_MATCHING_VIEW_CLASSES";
#endif
}

// Both native Objective-C +load and the C initializer enter this once gate.
static int initializationScheduled;
void XATScheduleInitialization(void) {
    if (__sync_lock_test_and_set(&initializationScheduled,1)) {
        XADBootstrap("INITIALIZATION_ALREADY_SCHEDULED");
        return;
    }
    XADBootstrap("MAIN_QUEUE_ENQUEUE_BEGIN");
    dispatch_async_f(&_dispatch_main_q,0,install);
    XADBootstrap("MAIN_QUEUE_ENQUEUE_RETURNED");
}

__attribute__((constructor)) static void start(void) {
    XADBootstrap("CONSTRUCTOR_ENTER");
    XADLog("BOOT","constructor reached build=XAutoTranslate-v4-apple-sdk-20261016; source=v2-with-temporary-observability");
#if XAD_DIAGNOSTICS
    struct ImageInfo { const char *path; void *base; const char *symbol; void *address; } image={0};
    extern int dladdr(const void *, struct ImageInfo *);
    if (dladdr((const void *)start,&image)) XADLog("BOOT","loaded image=%s base=%p",image.path ? image.path : "unknown",image.base);
#endif
    XATScheduleInitialization();
}
