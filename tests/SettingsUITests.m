#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "XIntegratedPlugin.h"
#include <stdio.h>
#include <stdlib.h>

static NSUInteger nativeSelections,nativeLoads,footerCreations;
static void Check(BOOL condition,const char *message) {if(!condition) {fprintf(stderr,"FAIL UIKit: %s\n",message);exit(1);}}
@interface ModernSettingsViewController : UIViewController <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) id account;
@property(nonatomic,strong) UITableView *tableView;
@property(nonatomic,copy) NSArray *sections;
- (instancetype)initWithAccount:(id)account;
- (void)setupSections;
- (void)setupNavigationBar;
- (void)setupTableView;
- (void)setupLayout;
- (void)setupFooterLabel;
- (void)nativeAction;
@end
@implementation ModernSettingsViewController
- (instancetype)initWithAccount:(id)account {if((self=[super init])) {self.account=account;[self setupSections];}return self;}
- (void)setupSections {
    NSMutableArray *rows=NSMutableArray.new;
    for(NSString *title in @[@"常规功能",@"高级功能",@"推文回复",@"媒体下载",@"个人资料",@"浏览链接",@"标识定义",@"实验功能"])
        [rows addObject:@{@"title":title,@"subtitle":@"原有功能说明保持不变。",@"icon":@"settings",@"action":@"nativeAction"}];
    self.sections=rows;
}
- (void)viewDidLoad {[super viewDidLoad];nativeLoads++;[self setupNavigationBar];[self setupTableView];[self setupLayout];[self setupFooterLabel];}
- (void)setupNavigationBar {
    UILabel *title=UILabel.new;title.text=@"NFB-X";
    UILabel *account=UILabel.new;account.text=@"@Zzyy0915";
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[title,account]];stack.axis=UILayoutConstraintAxisVertical;self.navigationItem.titleView=stack;
}
- (void)setupTableView {self.tableView=[[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];}
- (void)setupLayout {}
- (void)setupFooterLabel {footerCreations++;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {(void)table;return 5;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {(void)table;(void)section;return 1;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {(void)table;(void)path;return UITableViewCell.new;}
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {(void)table;(void)section;return UIView.new;}
- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {(void)table;(void)section;return UIView.new;}
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {(void)table;(void)section;return 150;}
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {(void)table;(void)section;return 150;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:NO];SEL action=NSSelectorFromString(self.sections[path.row][@"action"]);
    ((void (*)(id,SEL))[self methodForSelector:action])(self,action);
}
- (void)nativeAction {nativeSelections++;UIViewController *child=UIViewController.new;child.title=@"原功能";[self.navigationController pushViewController:child animated:NO];}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;(void)options;
    IMP selection=class_getMethodImplementation(ModernSettingsViewController.class,@selector(tableView:didSelectRowAtIndexPath:));
    XATPrepareIntegratedPlugin();
    Check(selection==class_getMethodImplementation(ModernSettingsViewController.class,@selector(tableView:didSelectRowAtIndexPath:)),"native action handler preserved");
    id account=NSObject.new;ModernSettingsViewController *root=[[ModernSettingsViewController alloc] initWithAccount:account];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:root];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=navigation;[self.window makeKeyAndVisible];
    [root loadViewIfNeeded];
    Check(nativeLoads==1 && footerCreations==0,"native lifecycle retained, footer builder suppressed");
    Check(root.account==account && [root.title isEqual:@"Zzy-X"],"account retained and title renamed");
    Check(root.tableView.style==UITableViewStyleInsetGrouped,"same inset grouped style as translation");
    Check([root numberOfSectionsInTableView:root.tableView]==1 && [root tableView:root.tableView numberOfRowsInSection:0]==9,"all eight features and translation retained");
    Check(![root tableView:root.tableView viewForHeaderInSection:0] && ![root tableView:root.tableView viewForFooterInSection:0],"highlighted introduction and footer hidden");
    UIStackView *title=(UIStackView *)root.navigationItem.titleView;
    Check([((UILabel *)title.arrangedSubviews[0]).text isEqual:@"Zzy-X"] && [((UILabel *)title.arrangedSubviews[1]).text isEqual:@"@Zzyy0915"],"title changed while account subtitle retained");
    UITableViewCell *feature=[root tableView:root.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    Check([feature.textLabel.text isEqual:@"常规功能"] && feature.accessoryType==UITableViewCellAccessoryDisclosureIndicator,"feature label and navigation affordance");
    [root tableView:root.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    Check(nativeSelections==1 && navigation.viewControllers.count==2 && root.account==account,"original action still opens original feature");
    [navigation popViewControllerAnimated:NO];
    [root tableView:root.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:8 inSection:0]];
    UITableViewController *translation=(UITableViewController *)navigation.topViewController;[translation loadViewIfNeeded];
    Check([translation.title isEqual:@"自动翻译"] && translation.tableView.style==UITableViewStyleInsetGrouped,"translation module remains reachable");
    UITableViewCell *details=[translation tableView:translation.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    Check(feature.textLabel.font.pointSize==details.textLabel.font.pointSize && [feature.textLabel.font.fontDescriptor isEqual:details.textLabel.font.fontDescriptor],"main and translation titles share font and size");
    Check([feature.detailTextLabel.font.fontDescriptor isEqual:details.detailTextLabel.font.fontDescriptor],"main and translation subtitles share font and size");
    Check(![translation tableView:translation.tableView titleForFooterInSection:0] && ![translation tableView:translation.tableView titleForFooterInSection:1],"both highlighted translation footnotes removed");
    puts("PASS UIKit settings: grouped layout, shared fonts, all feature rows, original selection/account/lifecycle, Zzy-X branding, removed highlighted regions");fflush(stdout);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{exit(0);});
    return YES;
}
@end
int main(int argc,char **argv) {@autoreleasepool {return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}
