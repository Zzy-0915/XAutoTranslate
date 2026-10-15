/* Temporary XAutoTranslate diagnostics. UIKit/Foundation calls use the public ObjC ABI. */
#include "XDiagnostics.h"
#if XAD_DIAGNOSTICS
#include <stdbool.h>
#include <stdarg.h>

typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void (*IMP)(void);
typedef unsigned long NSUInteger;
typedef struct { double x, y; } Point;
typedef struct { double width, height; } Size;
typedef struct { Point origin; Size size; } Rect;
typedef struct { double top, left, bottom, right; } Insets;
struct ObjCSuper { id receiver; Class superclass; };
extern void objc_msgSend(void);
extern void objc_msgSendSuper(void);
extern Class objc_getClass(const char *);
extern Class objc_allocateClassPair(Class, const char *, NSUInteger);
extern void objc_registerClassPair(Class);
extern bool class_addMethod(Class, SEL, IMP, const char *);
extern SEL sel_registerName(const char *);
extern Class object_getClass(id);
extern Class class_getSuperclass(Class);
extern id objc_getAssociatedObject(id, const void *);
extern void objc_setAssociatedObject(id, const void *, id, NSUInteger);
extern void objc_release(id);
extern void *malloc(unsigned long);
extern void free(void *);
extern void *memcpy(void *, const void *, unsigned long);
extern void *memmove(void *, const void *, unsigned long);
extern unsigned long strlen(const char *);
extern int strcmp(const char *, const char *);
extern int snprintf(char *, unsigned long, const char *, ...);
extern int vsnprintf(char *, unsigned long, const char *, va_list);
extern int mkdir(const char *, unsigned short);
extern int rename(const char *, const char *);
extern int unlink(const char *);
extern int sched_yield(void);
extern char *getenv(const char *);
extern int getpid(void);
typedef struct __sFILE XADFile;
#ifdef __APPLE__
#define XAD_LIBC(n) __asm__("_" n)
#else
#define XAD_LIBC(n) __asm__(n)
#endif
/* Alternate C identifiers allow a genuinely opaque FILE without SDK headers. */
extern XADFile *xad_fopen(const char *, const char *) XAD_LIBC("fopen");
extern unsigned long xad_fwrite(const void *, unsigned long, unsigned long, XADFile *) XAD_LIBC("fwrite");
extern unsigned long xad_fread(void *, unsigned long, unsigned long, XADFile *) XAD_LIBC("fread");
#define fopen xad_fopen
#define fwrite xad_fwrite
#define fread xad_fread
extern int fclose(XADFile *);
extern int fflush(XADFile *);
extern int fseek(XADFile *, long, int);
extern long ftell(XADFile *);
struct XADTimeval { long seconds; int microseconds; };
extern int gettimeofday(struct XADTimeval *, void *);
struct XADTM { int sec, min, hour, day, month, year, weekday, yearday, dst; long offset; const char *zone; };
extern struct XADTM *gmtime_r(const long *, struct XADTM *);

#define S(n) sel_registerName(n)
#define M0(o,n) ((id (*)(id,SEL))objc_msgSend)((o),S(n))
#define M1(o,n,a) ((id (*)(id,SEL,id))objc_msgSend)((o),S(n),(a))
#define V0(o,n) ((void (*)(id,SEL))objc_msgSend)((o),S(n))
#define V1(o,n,a) ((void (*)(id,SEL,id))objc_msgSend)((o),S(n),(a))
#define N0(o,n) ((long (*)(id,SEL))objc_msgSend)((o),S(n))
#define B0(o,n) ((bool (*)(id,SEL))objc_msgSend)((o),S(n))
#define HAS(o,n) ((bool (*)(id,SEL,SEL))objc_msgSend)((o),S("respondsToSelector:"),S(n))
#define SETBOOL(o,n,v) ((void (*)(id,SEL,bool))objc_msgSend)((o),S(n),(v))
#define SETLONG(o,n,v) ((void (*)(id,SEL,long))objc_msgSend)((o),S(n),(v))

enum { RingCapacity = 512 * 1024, FileCapacity = 2 * 1024 * 1024 };
static char ring[RingCapacity], logPath[4096], previousPath[4096], exportPath[4096];
static char startup[64 * 1024];
static unsigned long startupLength;
static bool startupComplete;
static char coreStatus[256] = "核心尚未报告状态";
static unsigned long ringLength, fileLength, lineCount;
static unsigned long fileErrors;
static int logLock;
static XADFile *logFile;
static id coordinator, panel, navigation, segment, textView, exportView, statusLabel, shareButton, timer;
static char buttonKey;
static bool started, visible;
static void scanWindows(void);
static bool filesInitialized;
static unsigned startupAttempts, windowRescans, attachedWindows;
extern struct dispatch_queue_s _dispatch_main_q;
extern unsigned long long dispatch_time(unsigned long long, long long);
extern void dispatch_after_f(unsigned long long, struct dispatch_queue_s *, void *, void (*)(void *));
static void (*snapshotHandler)(void);
void XADSetSnapshotHandler(void (*handler)(void)) { snapshotHandler = handler; }

/* First-stage evidence: libc only, no Foundation/UIKit, logger lock or dispatch. */
void XADBootstrap(const char *stage) {
    const char *homes[] = {getenv("CFFIXED_USER_HOME"),getenv("HOME")};
    const char *suffixes[] = {"/XAutoTranslate-bootstrap.log","/Documents/XAutoTranslate-bootstrap.log"};
    char path[4096],line[1024];
    struct XADTimeval tv={0};
    gettimeofday(&tv,0);
    int count=snprintf(line,sizeof(line),"epoch=%ld.%03d pid=%d build=v4 stage=%s\n",tv.seconds,tv.microseconds/1000,getpid(),stage ? stage : "unknown");
    unsigned long length=count>0 ? (unsigned long)count : 0;
    if(length>=sizeof(line)) length=sizeof(line)-1;
    for(unsigned i=0;i<2;i++) {
        if(!homes[i] || homes[i][0]!='/') continue;
        if(i && homes[0] && !strcmp(homes[0],homes[i])) continue;
        for(unsigned j=0;j<2;j++) {
            int n=snprintf(path,sizeof(path),"%s%s",homes[i],suffixes[j]);
            if(n<0 || (unsigned long)n>=sizeof(path)) continue;
            XADFile *file=fopen(path,"ab");
            if(!file) continue;
            if(!fseek(file,0,2) && ftell(file)>128*1024) { fclose(file); file=fopen(path,"wb"); }
            if(file) { fwrite(line,1,length,file); fflush(file); fclose(file); }
        }
    }
    const char *temporary=getenv("TMPDIR");
    if(temporary && temporary[0]=='/') {
        int n=snprintf(path,sizeof(path),"%s/XAutoTranslate-bootstrap.log",temporary);
        if(n>0 && (unsigned long)n<sizeof(path)) {
            XADFile *file=fopen(path,"ab");
            if(file) {
                if(!fseek(file,0,2) && ftell(file)>128*1024) { fclose(file); file=fopen(path,"wb"); }
                if(file) { fwrite(line,1,length,file); fflush(file); fclose(file); }
            }
        }
    }
}

static void lockLog(void) { while (__sync_lock_test_and_set(&logLock, 1)) sched_yield(); }
static void unlockLog(void) { __sync_lock_release(&logLock); }
static id string(const char *s) { return ((id (*)(id,SEL,const char *))objc_msgSend)(objc_getClass("NSString"), S("stringWithUTF8String:"), s ? s : ""); }
static const char *utf8(id s) { return s ? ((const char *(*)(id,SEL))objc_msgSend)(s,S("UTF8String")) : 0; }
static void rotateFile(void) {
    if (logFile) fclose(logFile);
    logFile = 0;
    unlink(previousPath);
    if (rename(logPath, previousPath)) fileErrors++;
    logFile = fopen(logPath, "wb");
    if (!logFile) fileErrors++;
    fileLength = 0;
}
void XADLog(const char *category, const char *format, ...) {
    if (!format) return;
    char message[2048], line[2304];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);
    /* Keep one event on one physical line, including strings supplied by the core. */
    for (char *p = message; *p; p++) if (*p == '\n' || *p == '\r') *p = ' ';
    struct XADTimeval tv = {0};
    struct XADTM tm = {0};
    gettimeofday(&tv, 0);
    gmtime_r(&tv.seconds, &tm);
    lockLog();
    int count = snprintf(line, sizeof(line), "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ #%lu [%s] %s\n",
        tm.year + 1900, tm.month + 1, tm.day, tm.hour, tm.min, tm.sec,
        tv.microseconds / 1000, ++lineCount, category ? category : "core", message);
    unsigned long length = count > 0 ? (unsigned long)count : 0;
    if (length >= sizeof(line)) length = sizeof(line) - 1;
    if (ringLength + length >= RingCapacity) {
        unsigned long remove = ringLength + length - (RingCapacity - 1);
        while (remove < ringLength && ring[remove - 1] != '\n') remove++;
        memmove(ring, ring + remove, ringLength - remove);
        ringLength -= remove;
    }
    memcpy(ring + ringLength, line, length);
    ringLength += length;
    ring[ringLength] = 0;
    if (!startupComplete) {
        if (startupLength + length < sizeof(startup)) {
            memcpy(startup + startupLength,line,length);
            startupLength += length;
            startup[startupLength] = 0;
        } else startupComplete = true;
    }
    if (logFile) {
        if (fileLength + length > FileCapacity) rotateFile();
        if (logFile) {
            if (fwrite(line, 1, length, logFile) != length || fflush(logFile)) fileErrors++;
            fileLength += length;
        }
    }
    unlockLog();
}
void XADCoreStatus(const char *status) {
    XADBootstrap(status);
    lockLog();
    snprintf(coreStatus, sizeof(coreStatus), "%s", status ? status : "未知");
    unlockLog();
    XADLog("state", "%s", status ? status : "unknown");
}
static char *snapshot(void) {
    lockLog();
    char *copy = malloc(ringLength + 1);
    if (copy) memcpy(copy, ring, ringLength + 1);
    unlockLog();
    return copy;
}
static id arrayItem(id array, unsigned long index) { return ((id (*)(id,SEL,unsigned long))objc_msgSend)(array, S("objectAtIndex:"),index); }
static void setFrame(id view, double x, double y, double w, double h) {
    Rect rect = {{x,y},{w > 0 ? w : 1,h > 0 ? h : 1}};
    ((void (*)(id,SEL,Rect))objc_msgSend)(view,S("setFrame:"),rect);
}
static void addTarget(id control, const char *action, unsigned long events) {
    ((void (*)(id,SEL,id,SEL,unsigned long))objc_msgSend)(control,S("addTarget:action:forControlEvents:"),coordinator,S(action),events);
}
static id color(const char *name) { return M0(objc_getClass("UIColor"),name); }
static void updatePanel(void) {
    if (!visible || !textView) return;
    bool exporting = N0(segment,"selectedSegmentIndex") == 1;
    SETBOOL(textView,"setHidden:",exporting);
    SETBOOL(exportView,"setHidden:",!exporting);
    if (exporting) {
        char status[1024];
        lockLog();
        snprintf(status,sizeof(status),"核心状态：%s\n\n已记录 %lu 条事件，文件写入错误 %lu 次。\n\n日志包含插件启动、方法挂钩、自动翻译触发与失败原因。记录自启动开始持续进行。\n\n日志不采集帖子正文、账号标识、请求头或令牌。导出文件后通过系统分享界面保存或提交。",coreStatus,lineCount,fileErrors);
        unlockLog();
        V1(statusLabel,"setText:",string(status));
    } else {
        /* Do not reset the user's selection or scroll position when no log changed. */
        static unsigned long lastDisplayed;
        lockLog(); unsigned long current = lineCount; unlockLog();
        if (lastDisplayed == current && M0(textView,"text") && N0(M0(textView,"text"),"length")) return;
        char *copy = snapshot();
        if (copy) {
            Point offset = ((Point (*)(id,SEL))objc_msgSend)(textView,S("contentOffset"));
            Size content = ((Size (*)(id,SEL))objc_msgSend)(textView,S("contentSize"));
            Rect bounds = ((Rect (*)(id,SEL))objc_msgSend)(textView,S("bounds"));
            bool followTail = offset.y + bounds.size.height >= content.height - 50;
            V1(textView,"setText:",string(copy)); free(copy); lastDisplayed = current;
            if (followTail) {
                unsigned long length = (unsigned long)N0(M0(textView,"text"),"length");
                struct { unsigned long location,length; } range = {length,0};
                ((void (*)(id,SEL,typeof(range)))objc_msgSend)(textView,S("scrollRangeToVisible:"),range);
            } else ((void (*)(id,SEL,Point))objc_msgSend)(textView,S("setContentOffset:"),offset);
        }
    }
}
static void layoutPanel(id self, SEL command) {
    struct ObjCSuper super = {self,class_getSuperclass(object_getClass(self))};
    ((void (*)(struct ObjCSuper *,SEL))objc_msgSendSuper)(&super,command);
    id view = M0(self,"view");
    Rect bounds = ((Rect (*)(id,SEL))objc_msgSend)(view,S("bounds"));
    Insets inset = ((Insets (*)(id,SEL))objc_msgSend)(view,S("safeAreaInsets"));
    double width = bounds.size.width, height = bounds.size.height;
    double top = inset.top + 12, bottom = inset.bottom + 12;
    setFrame(segment,16,top,width-32,34);
    setFrame(textView,12,top+44,width-24,height-top-bottom-44);
    setFrame(exportView,16,top+52,width-32,height-top-bottom-52);
    double available = height-top-bottom-52;
    double labelHeight = available-64 < 260 ? available-64 : 260;
    setFrame(statusLabel,0,0,width-32,labelHeight);
    setFrame(shareButton,0,labelHeight+12,width-32,48);
}
static void tick(id self, SEL command, id sender) { (void)self; (void)command; (void)sender; updatePanel(); }
static void selection(id self, SEL command, id sender) {
    (void)self; (void)command; (void)sender;
    XADLog("ui","tab selected: %s",N0(segment,"selectedSegmentIndex") == 1 ? "export" : "realtime");
    updatePanel();
}
static void closePanel(id self, SEL command, id sender) {
    (void)self; (void)command; (void)sender;
    visible = false;
    if (timer) { V0(timer,"invalidate"); objc_release(timer); timer = 0; }
    ((void (*)(id,SEL,bool,id))objc_msgSend)(navigation,S("dismissViewControllerAnimated:completion:"),true,0);
    scanWindows();
    XADLog("ui","diagnostic panel closed; background logging continues");
}
static id presenterForWindow(id window) {
    id root = M0(window,"rootViewController");
    for (unsigned i = 0; root && i < 20; i++) {
        id presented = M0(root,"presentedViewController");
        if (!presented || B0(presented,"isBeingDismissed")) break;
        root = presented;
    }
    return root;
}
static void verifyPresentation(void *unused) {
    (void)unused;
    if(!visible || M0(M0(panel,"view"),"window")) return;
    visible=false;
    if(timer) { V0(timer,"invalidate"); objc_release(timer); timer=0; }
    XADLog("ui","ERROR panel did not attach to a window; log button restored");
    scanWindows();
}
static void exportLog(id self, SEL command, id sender) {
    (void)self; (void)command; (void)sender;
    XADLog("export","export requested");
    if (snapshotHandler) snapshotHandler();
    id manager = M0(objc_getClass("NSFileManager"),"defaultManager");
    id temporary = M0(manager,"temporaryDirectory");
    const char *temporaryPath = utf8(M0(temporary,"path"));
    if (!temporaryPath) { XADLog("export","ERROR temporary directory unavailable"); updatePanel(); return; }
    struct XADTimeval tv; gettimeofday(&tv,0);
    if (exportPath[0]) unlink(exportPath);
    snprintf(exportPath,sizeof(exportPath),"%s/XAutoTranslate-diagnostic-%ld.txt",temporaryPath,tv.seconds);
    char *copy = snapshot();
    XADFile *out = copy ? fopen(exportPath,"wb") : 0;
    if (!out) { free(copy); XADLog("export","ERROR cannot create exported log file"); updatePanel(); return; }
    const char *header = "XAutoTranslate temporary diagnostics v4\nUTC timestamps; no post bodies, account identifiers or request headers recorded.\nStartup is preserved separately (first 64 KiB); current disk segment is at most 2 MiB.\nRepeated startup entries in the current segment are intentional.\n\n--- STARTUP ---\n";
    unsigned long headerLength = strlen(header), copyLength = strlen(copy);
    bool success = fwrite(header,1,headerLength,out) == headerLength;
    lockLog();
    success = success && fwrite(startup,1,startupLength,out) == startupLength;
    const char *separator = "\n--- CURRENT SESSION SEGMENT ---\n";
    success = success && fwrite(separator,1,strlen(separator),out) == strlen(separator);
    if (logFile) fflush(logFile);
    XADFile *session = logPath[0] ? fopen(logPath,"rb") : 0;
    if (session) {
        char buffer[8192]; unsigned long count, total = 0;
        while ((count = fread(buffer,1,sizeof(buffer),session)) && total < FileCapacity) {
            if (fwrite(buffer,1,count,out) != count) { success = false; break; }
            total += count;
        }
        fclose(session);
    } else success = success && fwrite(copy,1,copyLength,out) == copyLength;
    unlockLog();
    if (fclose(out)) success = false;
    free(copy);
    if (!success) { XADLog("export","ERROR incomplete export write"); updatePanel(); return; }
    id url = M1(objc_getClass("NSURL"),"fileURLWithPath:",string(exportPath));
    id items = M1(objc_getClass("NSArray"),"arrayWithObject:",url);
    id activity = ((id (*)(id,SEL,id,id))objc_msgSend)(M0(objc_getClass("UIActivityViewController"),"alloc"),S("initWithActivityItems:applicationActivities:"),items,0);
    if (!activity) { XADLog("export","ERROR native share controller unavailable"); return; }
    id popover = M0(activity,"popoverPresentationController");
    if (popover) {
        V1(popover,"setSourceView:",shareButton);
        Rect rect = ((Rect (*)(id,SEL))objc_msgSend)(shareButton,S("bounds"));
        ((void (*)(id,SEL,Rect))objc_msgSend)(popover,S("setSourceRect:"),rect);
        SETLONG(popover,"setPermittedArrowDirections:",0);
    }
    ((void (*)(id,SEL,id,bool,id))objc_msgSend)(panel,S("presentViewController:animated:completion:"),activity,true,0);
    objc_release(activity);
    XADLog("export","native share sheet presented; file prepared successfully");
}
static void openPanel(id window) {
    if (visible) return;
    id presenter = presenterForWindow(window);
    if (!presenter || !M0(M0(presenter,"view"),"window")) { XADLog("ui","ERROR no visible presentation controller"); return; }
    /* Capture visible X views before our own overlay covers them. */
    if (snapshotHandler) snapshotHandler();
    if (panel) objc_release(panel);
    if (navigation) objc_release(navigation);
    panel = M0(objc_getClass("XATDiagnosticPanelV4"),"new");
    if (!panel) { XADLog("ui","ERROR cannot allocate panel"); return; }
    V1(panel,"setTitle:",string("XAutoTranslate 诊断"));
    id view = M0(panel,"view");
    V1(view,"setBackgroundColor:",color("systemBackgroundColor"));
    id titles[2] = {string("实时日志"),string("导出日志")};
    id items = ((id (*)(id,SEL,id *,NSUInteger))objc_msgSend)(objc_getClass("NSArray"),S("arrayWithObjects:count:"),titles,2);
    segment = M1(M0(objc_getClass("UISegmentedControl"),"alloc"),"initWithItems:",items);
    SETLONG(segment,"setSelectedSegmentIndex:",0);
    addTarget(segment,"xadSelection:",1UL<<12);
    V1(view,"addSubview:",segment); objc_release(segment);
    textView = M0(objc_getClass("UITextView"),"new");
    SETBOOL(textView,"setEditable:",false); SETBOOL(textView,"setSelectable:",true);
    id font = ((id (*)(id,SEL,double,double))objc_msgSend)(objc_getClass("UIFont"),S("monospacedSystemFontOfSize:weight:"),11.0,0.0);
    V1(textView,"setFont:",font); V1(textView,"setTextColor:",color("labelColor"));
    V1(view,"addSubview:",textView); objc_release(textView);
    exportView = M0(objc_getClass("UIView"),"new");
    V1(view,"addSubview:",exportView); objc_release(exportView);
    statusLabel = M0(objc_getClass("UILabel"),"new");
    SETLONG(statusLabel,"setNumberOfLines:",0);
    id statusFont = ((id (*)(id,SEL,double))objc_msgSend)(objc_getClass("UIFont"),S("systemFontOfSize:"),14.0);
    V1(statusLabel,"setFont:",statusFont);
    V1(statusLabel,"setTextColor:",color("labelColor"));
    V1(exportView,"addSubview:",statusLabel); objc_release(statusLabel);
    shareButton = ((id (*)(id,SEL,long))objc_msgSend)(objc_getClass("UIButton"),S("buttonWithType:"),1);
    ((void (*)(id,SEL,id,unsigned long))objc_msgSend)(shareButton,S("setTitle:forState:"),string("导出日志"),0);
    addTarget(shareButton,"xadExport:",1UL<<6);
    V1(exportView,"addSubview:",shareButton);
    id done = ((id (*)(id,SEL,long,id,SEL))objc_msgSend)(M0(objc_getClass("UIBarButtonItem"),"alloc"),S("initWithBarButtonSystemItem:target:action:"),0,coordinator,S("xadClose:"));
    V1(M0(panel,"navigationItem"),"setRightBarButtonItem:",done); objc_release(done);
    navigation = M1(M0(objc_getClass("UINavigationController"),"alloc"),"initWithRootViewController:",panel);
    SETLONG(navigation,"setModalPresentationStyle:",0);
    visible = true;
    ((void (*)(id,SEL,id,bool,id))objc_msgSend)(presenter,S("presentViewController:animated:completion:"),navigation,true,0);
    timer = ((id (*)(id,SEL,double,id,SEL,id,bool))objc_msgSend)(objc_getClass("NSTimer"),S("timerWithTimeInterval:target:selector:userInfo:repeats:"),0.75,coordinator,S("xadTick:"),0,true);
    if (timer) {
        M0(timer,"retain");
        ((void (*)(id,SEL,id,id))objc_msgSend)(M0(objc_getClass("NSRunLoop"),"mainRunLoop"),S("addTimer:forMode:"),timer,string("kCFRunLoopCommonModes"));
    } else XADLog("ui","ERROR realtime refresh timer unavailable");
    XADLog("ui","diagnostic panel opened; realtime refresh interval=0.75s");
    updatePanel();
    dispatch_after_f(dispatch_time(0,1000000000LL),&_dispatch_main_q,0,verifyPresentation);
}
static void logButtonPressed(id self, SEL command, id sender) {
    (void)self; (void)command;
    XADLog("button","log button tapped");
    openPanel(M0(sender,"window"));
    if (visible) SETBOOL(sender,"setHidden:",true);
}
static void installWindow(id window) {
    if (!window || !HAS(window,"addSubview:") || !HAS(window,"rootViewController")) return;
    id button=objc_getAssociatedObject(window,&buttonKey);
    bool normal=!HAS(window,"windowLevel") || ((double (*)(id,SEL))objc_msgSend)(window,S("windowLevel"))==0.0;
    if (!normal || !M0(window,"rootViewController") || B0(window,"isHidden")) {
        if(button) SETBOOL(button,"setHidden:",true);
        return;
    }
    if (!button) {
        button=((id (*)(id,SEL,long))objc_msgSend)(objc_getClass("UIButton"),S("buttonWithType:"),1);
        if(!button) { XADBootstrap("LOG_BUTTON_ALLOCATION_FAILED"); XADLog("button","ERROR cannot allocate log button"); return; }
        ((void (*)(id,SEL,id,unsigned long))objc_msgSend)(button,S("setTitle:forState:"),string("日志"),0);
        ((void (*)(id,SEL,id,unsigned long))objc_msgSend)(button,S("setTitleColor:forState:"),color("whiteColor"),0);
        V1(button,"setBackgroundColor:",color("systemBlueColor"));
        id font=((id (*)(id,SEL,double))objc_msgSend)(objc_getClass("UIFont"),S("boldSystemFontOfSize:"),14.0);
        V1(M0(button,"titleLabel"),"setFont:",font);
        V1(button,"setAccessibilityLabel:",string("打开 X 翻译诊断日志"));
        V1(button,"setAccessibilityIdentifier:",string("XAutoTranslate.LogButton.v4"));
        SETLONG(button,"setAutoresizingMask:",1UL|8UL|32UL);
        id layer=M0(button,"layer");
        ((void (*)(id,SEL,double))objc_msgSend)(layer,S("setCornerRadius:"),22.0);
        SETBOOL(layer,"setMasksToBounds:",true);
        addTarget(button,"xadOpenLog:",1UL<<6);
        V1(window,"addSubview:",button);
        objc_setAssociatedObject(window,&buttonKey,button,1);
        ++attachedWindows;
        XADBootstrap("LOG_BUTTON_ATTACHED_TO_WINDOW");
        XADLog("button","visible log button attached to application window");
    }
    Rect bounds=((Rect (*)(id,SEL))objc_msgSend)(window,S("bounds"));
    Insets inset=((Insets (*)(id,SEL))objc_msgSend)(window,S("safeAreaInsets"));
    double x=bounds.size.width-inset.right-76;
    double y=inset.top+(bounds.size.height-inset.top-inset.bottom-44)*0.5;
    if(x<inset.left+4) x=inset.left+4;
    if(y<inset.top+4) y=inset.top+4;
    setFrame(button,x,y,64,44);
    SETBOOL(button,"setHidden:",visible);
    V1(window,"bringSubviewToFront:",button);
}
static void scanWindows(void) {
    id app = M0(objc_getClass("UIApplication"),"sharedApplication");
    id scenes = M0(M0(app,"connectedScenes"),"allObjects");
    long count = N0(scenes,"count");
    for (long i=0;i<count;i++) {
        id scene = arrayItem(scenes,(unsigned long)i);
        if (!HAS(scene,"windows")) continue;
        id windows = M0(scene,"windows");
        long windowCount = N0(windows,"count");
        for (long j=0;j<windowCount;j++) installWindow(arrayItem(windows,(unsigned long)j));
    }
    /* Older or non-scene lifecycle apps may have no connectedScenes windows. */
    id windows=HAS(app,"windows") ? M0(app,"windows") : 0;
    for(long j=0;j<N0(windows,"count");j++) installWindow(arrayItem(windows,(unsigned long)j));
    if(HAS(app,"keyWindow")) installWindow(M0(app,"keyWindow"));
    id delegate=HAS(app,"delegate") ? M0(app,"delegate") : 0;
    if(HAS(delegate,"window")) installWindow(M0(delegate,"window"));
    XADLog("button","window scan scenes=%ld attachedTotal=%u",count,attachedWindows);
}
static void rescanWindows(void *unused) {
    (void)unused;
    scanWindows();
    if(++windowRescans<5) dispatch_after_f(dispatch_time(0,(1LL<<windowRescans)*500000000LL),&_dispatch_main_q,0,rescanWindows);
}
static void windowNotification(id self, SEL command, id notification) {
    (void)self; (void)command;
    id object = M0(notification,"object");
    if (object && HAS(object,"rootViewController")) installWindow(object);
    else scanWindows();
}
static bool registerRuntime(void) {
    Class objectClass = objc_allocateClassPair(objc_getClass("NSObject"),"XATDiagnosticCoordinatorV4",0);
    Class panelClass = objc_allocateClassPair(objc_getClass("UIViewController"),"XATDiagnosticPanelV4",0);
    if (!objectClass || !panelClass) { XADBootstrap("UI_CLASS_ALLOCATION_FAILED"); XADLog("ui","ERROR diagnostic runtime class allocation failed (possible duplicate injection)"); return false; }
    bool ok = true;
    ok &= class_addMethod(objectClass,S("xadOpenLog:"),(IMP)logButtonPressed,"v@:@");
    ok &= class_addMethod(objectClass,S("xadWindow:"),(IMP)windowNotification,"v@:@");
    ok &= class_addMethod(objectClass,S("xadTick:"),(IMP)tick,"v@:@");
    ok &= class_addMethod(objectClass,S("xadSelection:"),(IMP)selection,"v@:@");
    ok &= class_addMethod(objectClass,S("xadClose:"),(IMP)closePanel,"v@:@");
    ok &= class_addMethod(objectClass,S("xadExport:"),(IMP)exportLog,"v@:@");
    ok &= class_addMethod(panelClass,S("viewDidLayoutSubviews"),(IMP)layoutPanel,"v@:");
    objc_registerClassPair(objectClass); objc_registerClassPair(panelClass);
    if (!ok) { XADLog("ui","ERROR diagnostic runtime method registration incomplete"); return false; }
    coordinator = M0(objectClass,"new");
    return coordinator != 0;
}
static void initializeFiles(void) {
    id manager = M0(objc_getClass("NSFileManager"),"defaultManager");
    id directories = ((id (*)(id,SEL,unsigned long,unsigned long))objc_msgSend)(manager,S("URLsForDirectory:inDomains:"),13,1);
    const char *base = utf8(M0(M0(directories,"lastObject"),"path"));
    if (!base) { XADLog("file","ERROR cache directory unavailable; memory logging remains active"); return; }
    char directory[4096];
    int n = snprintf(directory,sizeof(directory),"%s/XAutoTranslate",base);
    if (n < 0 || (unsigned long)n + 32 >= sizeof(directory)) { XADLog("file","ERROR cache path too long"); return; }
    mkdir(directory,0700);
    snprintf(logPath,sizeof(logPath),"%s/current.log",directory);
    snprintf(previousPath,sizeof(previousPath),"%s/previous.log",directory);
    lockLog();
    /* Retain one bounded previous-session file, including startup failures. */
    XADFile *previous = fopen(logPath,"rb");
    if (previous) { fclose(previous); unlink(previousPath); if (rename(logPath,previousPath)) fileErrors++; }
    logFile = fopen(logPath,"wb");
    if (logFile) { if (fwrite(ring,1,ringLength,logFile) != ringLength || fflush(logFile)) fileErrors++; fileLength = ringLength; }
    else fileErrors++;
    bool available = logFile != 0;
    unlockLog();
    XADBootstrap(available ? "FOUNDATION_SESSION_FILE_OPENED" : "FOUNDATION_SESSION_FILE_FAILED");
    XADLog("file","persistent session log %s; ring=512KiB file=2MiB previous=1",available ? "ready" : "FAILED; memory fallback active");
}
static void retryStartup(void *unused) { (void)unused; XADStart(); }
void XADStart(void) {
    if (started) return;
    ++startupAttempts;
    XADBootstrap("DIAGNOSTICS_START_ATTEMPT");
    XADLog("diagnostics","starting temporary diagnostic module; UIKit setup on main thread");
    if(!filesInitialized && objc_getClass("NSFileManager") && objc_getClass("NSString")) { initializeFiles(); filesInitialized=logFile != 0; }
    bool ready=objc_getClass("NSObject") && objc_getClass("UIViewController") && objc_getClass("UIApplication") && objc_getClass("UIButton");
    id app=ready ? M0(objc_getClass("UIApplication"),"sharedApplication") : 0;
    if(!ready || !app) {
        XADLog("ui","waiting for UIKit/application attempt=%u classesReady=%d app=%p",startupAttempts,ready,app);
        XADBootstrap("WAITING_FOR_UIKIT_OR_APPLICATION");
        if(startupAttempts<20) dispatch_after_f(dispatch_time(0,1000000000LL),&_dispatch_main_q,0,retryStartup);
        else XADBootstrap("UIKIT_RETRY_LIMIT_REACHED");
        return;
    }
    if (!registerRuntime()) return;
    started = true;
    XADBootstrap("DIAGNOSTIC_RUNTIME_READY");
    id notifications = M0(objc_getClass("NSNotificationCenter"),"defaultCenter");
    const char *names[] = {"UIWindowDidBecomeVisibleNotification","UIWindowDidBecomeKeyNotification","UISceneDidActivateNotification","UIApplicationDidBecomeActiveNotification","UIApplicationDidFinishLaunchingNotification"};
    for (unsigned i=0;i<sizeof(names)/sizeof(names[0]);i++)
        ((void (*)(id,SEL,id,SEL,id,id))objc_msgSend)(notifications,S("addObserver:selector:name:object:"),coordinator,S("xadWindow:"),string(names[i]),0);
    scanWindows();
    dispatch_after_f(dispatch_time(0,500000000LL),&_dispatch_main_q,0,rescanWindows);
    XADLog("diagnostics","ready; tap the visible 日志 button on the right side of the screen");
}
#endif
