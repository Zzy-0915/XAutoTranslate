#import "XIntegratedPlugin.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <zlib.h>

static NSString *const enabledKey=@"dev.zzy0915.XAutoTranslate.enabled";
static NSString *integrationFailure;
static void (*originalSections)(id,SEL);
static void *vendorHandles[3];

BOOL XATTranslationEnabled(void) {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:enabledKey];
    return value ? [value boolValue] : YES;
}
static NSString *Digest(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    NSMutableString *result=[NSMutableString stringWithCapacity:64];
    for(unsigned i=0;i<sizeof(bytes);i++) [result appendFormat:@"%02x",bytes[i]];
    return result;
}
static NSData *Section(const char *name) {
    Dl_info image={0};unsigned long size=0;
    if(!dladdr((const void *)&XATPrepareIntegratedPlugin,&image)) return nil;
    const uint8_t *bytes=getsectiondata((const struct mach_header_64 *)image.dli_fbase,"__TEXT",name,&size);
    return bytes && size ? [NSData dataWithBytesNoCopy:(void *)bytes length:size freeWhenDone:NO] : nil;
}
static BOOL SafePath(NSString *path) {
    return [path isKindOfClass:NSString.class] && path.length && !path.isAbsolutePath && ![path.pathComponents containsObject:@".."] && ![path containsString:@"\\"];
}
static BOOL ValidFile(NSString *path,NSDictionary *expected) {
    NSNumber *regular=nil;NSURL *url=[NSURL fileURLWithPath:path];
    if(![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL] || !regular.boolValue) return NO;
    NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    return data && data.length==[expected[@"size"] unsignedLongLongValue] && [Digest(data) isEqual:expected[@"sha256"]];
}
static NSString *PrepareFiles(void) {
    NSData *manifestData=Section("__xat_manifest");
    NSDictionary *manifest=manifestData ? [NSPropertyListSerialization propertyListWithData:manifestData options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    if(![manifest isKindOfClass:NSDictionary.class] || [manifest[@"format"] integerValue]!=1) return nil;
    NSDictionary *files=manifest[@"files"];
    if(![files isKindOfClass:NSDictionary.class] || !files.count) return nil;
    NSString *base=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"XAutoTranslate/Integrated"];
    NSString *root=[base stringByAppendingPathComponent:Digest(manifestData)];
    BOOL complete=YES;
    for(NSString *name in files) {
        if(!SafePath(name) || ![files[name] isKindOfClass:NSDictionary.class]) return nil;
        if(!ValidFile([root stringByAppendingPathComponent:name],files[name])) complete=NO;
    }
    if(complete) return root;
    NSData *payload=Section("__xat_payload");
    NSUInteger size=[manifest[@"uncompressedSize"] unsignedIntegerValue];
    if(!payload || ![Digest(payload) isEqual:manifest[@"payloadSHA256"]] || !size || size>64*1024*1024) return nil;
    NSMutableData *raw=[NSMutableData dataWithLength:size];uLongf decoded=size;
    if(uncompress(raw.mutableBytes,&decoded,payload.bytes,payload.length)!=Z_OK || decoded!=size) return nil;
    NSDictionary *contents=[NSPropertyListSerialization propertyListWithData:raw options:NSPropertyListImmutable format:NULL error:NULL];
    if(![contents isKindOfClass:NSDictionary.class] || contents.count!=files.count) return nil;
    NSFileManager *manager=NSFileManager.defaultManager;
    for(NSString *name in files) {
        NSData *data=contents[name];NSDictionary *expected=files[name];
        if(![data isKindOfClass:NSData.class] || data.length!=[expected[@"size"] unsignedLongLongValue] || ![Digest(data) isEqual:expected[@"sha256"]]) return nil;
        NSString *path=[root stringByAppendingPathComponent:name];
        if(![manager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL] || ![data writeToFile:path options:NSDataWritingAtomic error:NULL]) return nil;
        if([name.pathExtension isEqual:@"dylib"] && chmod(path.fileSystemRepresentation,0755)) return nil;
    }
    [[NSURL fileURLWithPath:root] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
    return root;
}

@interface XATTranslationModuleController : UITableViewController
@end
@implementation XATTranslationModuleController
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad {[super viewDidLoad];self.title=@"自动翻译";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=60;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {(void)table;return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {(void)table;return section==0 ? 1 : 3;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;return section==0 ? @"开关改动在完全退出并重新打开 X 后生效。默认开启，中文不翻译。" : @"基于 v10 精简版。翻译缓存仅保留至本次进程结束。Google 补位会发送待翻译文本，仍可能限流。";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)table;UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
    if(path.section==0) {
        cell.textLabel.text=@"自动翻译推文和评论";
        UISwitch *toggle=UISwitch.new;toggle.on=XATTranslationEnabled();[toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
    } else {
        NSArray *titles=@[@"翻译通道",@"翻译方式",@"译文显示"];
        NSArray *details=@[@"官方优先；确认官方失败后 Google GTX 补位，保留冷却与退避。",@"可见内容快速排队；成功结果缓存并去重。",@"使用 X 原生已翻译提示和显示原文功能。"];
        cell.textLabel.text=titles[path.row];cell.detailTextLabel.text=details[path.row];
    }return cell;
}
- (void)toggle:(UISwitch *)toggle {[NSUserDefaults.standardUserDefaults setBool:toggle.on forKey:enabledKey];}
@end

static void OpenModule(UIViewController *controller,SEL selector) {
    (void)selector;
    [controller.navigationController pushViewController:XATTranslationModuleController.new animated:YES];
}
static void SetupSections(id controller,SEL selector) {
    originalSections(controller,selector);
    SEL getter=NSSelectorFromString(@"sections"),setter=NSSelectorFromString(@"setSections:");
    if(![controller respondsToSelector:getter] || ![controller respondsToSelector:setter]) return;
    NSArray *items=((id (*)(id,SEL))objc_msgSend)(controller,getter);
    if(![items isKindOfClass:NSArray.class]) return;
    for(id item in items) if([item isKindOfClass:NSDictionary.class] && [item[@"action"] isEqual:@"xatOpenTranslationModule"]) return;
    NSMutableArray *updated=items.mutableCopy;
    [updated addObject:@{@"title":@"自动翻译",@"subtitle":@"官方优先 · Google 失败补位",@"icon":@"translate",@"action":@"xatOpenTranslationModule"}];
    ((void (*)(id,SEL,id))objc_msgSend)(controller,setter,updated);
}
static void InstallModule(NSString *root) {
    Class bundleClass=NSClassFromString(@"BHTBundle");SEL shared=NSSelectorFromString(@"sharedBundle"),set=NSSelectorFromString(@"setMainBundle:");
    if([bundleClass respondsToSelector:shared]) {
        id bundle=((id (*)(id,SEL))objc_msgSend)(bundleClass,shared);
        if([bundle respondsToSelector:set]) ((void (*)(id,SEL,id))objc_msgSend)(bundle,set,[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"BHTwitter.bundle"]]);
    }
    Class cls=NSClassFromString(@"ModernSettingsViewController");SEL setup=NSSelectorFromString(@"setupSections");
    Method method=class_getInstanceMethod(cls,setup);
    if(method && class_addMethod(cls,NSSelectorFromString(@"xatOpenTranslationModule"),(IMP)OpenModule,"v@:")) {
        originalSections=(void (*)(id,SEL))method_getImplementation(method);
        if(!class_addMethod(cls,setup,(IMP)SetupSections,method_getTypeEncoding(method))) method_setImplementation(method,(IMP)SetupSections);
    }
    // Keep the imported optional custom API translator from competing with this module.
    if(XATTranslationEnabled()) {
        Class manager=object_getClass(NSClassFromString(@"BHTManager"));SEL enable=NSSelectorFromString(@"enableTranslate");
        Method gate=class_getInstanceMethod(manager,enable);
        if(gate) {
            IMP disabled=imp_implementationWithBlock(^BOOL(id receiver){(void)receiver;return NO;});
            if(!class_addMethod(manager,enable,disabled,method_getTypeEncoding(gate))) method_setImplementation(gate,disabled);
        }
    }
}
static void ProvideBundleResource(NSString *root) {
    NSBundle *main=NSBundle.mainBundle;Class cls=object_getClass(main);
    SEL selector=@selector(URLForResource:withExtension:);Method method=class_getInstanceMethod(cls,selector);
    if(!method) return;
    IMP original=method_getImplementation(method);
    NSURL *resource=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"BHTwitter.bundle"] isDirectory:YES];
    IMP replacement=imp_implementationWithBlock(^NSURL *(NSBundle *bundle,NSString *name,NSString *extension){
        if(bundle==main && [name isEqual:@"BHTwitter"] && [extension isEqual:@"bundle"]) return resource;
        return ((id (*)(id,SEL,id,id))original)(bundle,selector,name,extension);
    });
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
}
static void ShowFailure(void) {
    if(!integrationFailure) return;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) if(window.isKeyWindow) {
            UIViewController *host=window.rootViewController;while(host.presentedViewController) host=host.presentedViewController;
            if(!host) continue;
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"整合插件未完整加载" message:[integrationFailure stringByAppendingString:@"\n自动翻译仍按独立模块尝试加载。"] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [host presentViewController:alert animated:YES completion:nil];integrationFailure=nil;return;
        }
    }
}
void XATPrepareIntegratedPlugin(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{@autoreleasepool {
        NSString *root=PrepareFiles();
        if(!root) {integrationFailure=@"内置插件或资源校验、释放失败。";}
        else {
            ProvideBundleResource(root);
            NSArray *libraries=@[@"libellekit.dylib",@"libbhFLEX.dylib",@"BHTwitter.dylib"];
            if(!NSClassFromString(@"ModernSettingsViewController")) for(NSUInteger i=0;i<libraries.count;i++) {
                NSString *path=[root stringByAppendingPathComponent:libraries[i]];
                vendorHandles[i]=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_GLOBAL);
                if(!vendorHandles[i]) {const char *error=dlerror();integrationFailure=[NSString stringWithFormat:@"加载 %@ 失败：%s",libraries[i],error ?: "unknown"];break;}
            }
            if(NSClassFromString(@"ModernSettingsViewController")) InstallModule(root);
            else if(!integrationFailure) integrationFailure=@"原插件设置类未注册。";
        }
        if(integrationFailure) {
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;ShowFailure();}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ShowFailure();});
        }
    }});
}
