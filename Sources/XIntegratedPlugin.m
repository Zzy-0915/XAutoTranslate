#import "XIntegratedPlugin.h"
#import "XSettingsAppearance.h"
#import "XFeatureAppearance.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>

static NSString *const enabledKey=@"dev.zzy0915.XAutoTranslate.enabled";
static NSString *integrationFailure;
static void (*originalSections)(id,SEL);

BOOL XATTranslationEnabled(void) {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:enabledKey];
    return value ? [value boolValue] : YES;
}
@interface XATTranslationModuleController : UITableViewController
@end
@implementation XATTranslationModuleController
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad {[super viewDidLoad];self.title=@"自动翻译";self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=60;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {(void)table;return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {(void)table;return section==0 ? 1 : 3;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table;(void)section;return nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=XATSettingsCell(table,@"XATTranslationSetting");
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
    XATInstallSettingsAppearance(cls);
    XATInstallFeatureAppearance();
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
        Dl_info image={0};
        NSString *root=nil;
        if(dladdr((const void *)&XATPrepareIntegratedPlugin,&image) && image.dli_fname) {
            NSString *directory=[NSString stringWithUTF8String:image.dli_fname].stringByDeletingLastPathComponent;
            if([NSFileManager.defaultManager fileExistsAtPath:[directory stringByAppendingPathComponent:@"BHTwitter.bundle/Info.plist"]]) root=directory;
        }
        if(!root && [NSBundle.mainBundle URLForResource:@"BHTwitter" withExtension:@"bundle"]) root=NSBundle.mainBundle.bundlePath;
        if(NSClassFromString(@"ModernSettingsViewController") && root) InstallModule(root);
        else integrationFailure=@"原插件或资源缺失。请移除 v11，并通过注入器导入 v14 完整注入包，不能只导入主 dylib。";
        if(integrationFailure) {
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;ShowFailure();}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ShowFailure();});
        }
    }});
}
