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

static NSUInteger featureChanges;
@interface ModernSettingsToggleCell : UITableViewCell
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UISwitch *toggleSwitch;
@end
@implementation ModernSettingsToggleCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.titleLabel=UILabel.new;self.subtitleLabel=UILabel.new;self.toggleSwitch=UISwitch.new;
        self.titleLabel.text=@"保留原功能";self.subtitleLabel.text=@"这是一段较长的原有说明，换行后仍然完整显示。";
        self.titleLabel.font=[UIFont boldSystemFontOfSize:24];self.subtitleLabel.font=[UIFont boldSystemFontOfSize:22];
        self.toggleSwitch.tag=37;self.toggleSwitch.on=YES;self.toggleSwitch.transform=CGAffineTransformMakeScale(1.3,1.3);
        for(UIView *view in @[self.titleLabel,self.subtitleLabel,self.toggleSwitch]) [self.contentView addSubview:view];
    }return self;
}
@end
@interface GeneralSettingsViewController : UIViewController <UITableViewDelegate,UITableViewDataSource>
@property(nonatomic,strong) UITableView *tableView;
- (void)setupTable;
- (void)switchChanged:(UISwitch *)toggle;
@end
@implementation GeneralSettingsViewController
- (void)viewDidLoad {[super viewDidLoad];[self setupTable];}
- (void)setupTable {
    self.tableView=[[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate=self;self.tableView.dataSource=self;
    [self.tableView registerClass:ModernSettingsToggleCell.class forCellReuseIdentifier:@"toggle"];
    [self.view addSubview:self.tableView];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {(void)table;(void)section;return 1;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    ModernSettingsToggleCell *cell=[table dequeueReusableCellWithIdentifier:@"toggle" forIndexPath:path];
    [cell.toggleSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];return cell;
}
- (void)switchChanged:(UISwitch *)toggle {if(toggle.tag==37) featureChanges++;}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {(void)table;(void)path;return 130;}
@end
@interface BHCustomTabBarViewController : UIViewController <UICollectionViewDataSource,UICollectionViewDelegate>
@property(nonatomic,strong) UICollectionView *collectionView;
@property(nonatomic,strong) UILabel *headerLabel;
@property(nonatomic,strong) UIButton *restoreButton;
@end
@implementation BHCustomTabBarViewController
- (void)viewDidLoad {
    [super viewDidLoad];self.headerLabel=UILabel.new;self.headerLabel.text=@"布局调整";self.headerLabel.font=[UIFont boldSystemFontOfSize:24];[self.view addSubview:self.headerLabel];
    self.restoreButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.restoreButton setTitle:@"恢复默认" forState:UIControlStateNormal];[self.view addSubview:self.restoreButton];
    self.collectionView=[[UICollectionView alloc] initWithFrame:CGRectMake(20,100,300,300) collectionViewLayout:UICollectionViewFlowLayout.new];
    self.collectionView.delegate=self;self.collectionView.dataSource=self;[self.collectionView registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"item"];[self.view addSubview:self.collectionView];
}
- (NSInteger)collectionView:(UICollectionView *)grid numberOfItemsInSection:(NSInteger)section {(void)grid;(void)section;return 4;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)grid cellForItemAtIndexPath:(NSIndexPath *)path {return [grid dequeueReusableCellWithReuseIdentifier:@"item" forIndexPath:path];}
- (void)collectionView:(UICollectionView *)grid didSelectItemAtIndexPath:(NSIndexPath *)path {(void)grid;(void)path;}
@end
static void CheckFeatureAppearance(UITableViewCell *reference) {
    GeneralSettingsViewController *controller=GeneralSettingsViewController.new;[controller loadViewIfNeeded];
    UITableView *table=controller.tableView;
    Check(table.style==UITableViewStyleInsetGrouped && table.delegate==controller && table.dataSource==controller,"feature grouped table retains original delegates");
    Check([table.backgroundColor isEqual:UIColor.systemGroupedBackgroundColor],"feature matches translation background");
    NSIndexPath *path=[NSIndexPath indexPathForRow:0 inSection:0];
    ModernSettingsToggleCell *cell=(id)[controller tableView:table cellForRowAtIndexPath:path];
    Check([cell isKindOfClass:ModernSettingsToggleCell.class],"original feature cell class retained for native updates");
    Check(cell.accessoryView==cell.toggleSwitch && cell.toggleSwitch.on && cell.toggleSwitch.tag==37,"same switch object, value and tag retained");
    Check(CGAffineTransformIsIdentity(cell.toggleSwitch.transform),"native switch size restored");
    [cell.toggleSwitch sendActionsForControlEvents:UIControlEventValueChanged];Check(featureChanges==1,"original switch target/action still fires");
    Check([cell.titleLabel.font.fontDescriptor isEqual:reference.textLabel.font.fontDescriptor] && [cell.subtitleLabel.font.fontDescriptor isEqual:reference.detailTextLabel.font.fontDescriptor],"feature title and detail match translation fonts exactly");
    cell.subtitleLabel.text=@"原控制器更新说明";[cell setNeedsLayout];[cell layoutIfNeeded];
    Check([cell.subtitleLabel.text isEqual:@"原控制器更新说明"] && !cell.subtitleLabel.hidden,"native text updates remain visible");
    Check([controller tableView:table heightForRowAtIndexPath:path]==UITableViewAutomaticDimension,"old fixed row height removed");
    UITableView *unrelated=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    Check(unrelated.style==UITableViewStylePlain,"X tables outside feature setup unaffected");
    BHCustomTabBarViewController *grid=BHCustomTabBarViewController.new;[grid loadViewIfNeeded];[grid viewDidLayoutSubviews];
    Check(grid.collectionView.delegate==grid && grid.collectionView.dataSource==grid && [grid collectionView:grid.collectionView numberOfItemsInSection:0]==4,"layout grid and native selection data retained");
    Check(grid.collectionView.layer.cornerRadius==12 && [grid.collectionView.backgroundColor isEqual:UIColor.secondarySystemGroupedBackgroundColor],"grid rounded card and grouped background");
    Check(grid.headerLabel.font.pointSize==12 && grid.restoreButton.titleLabel.font.pointSize==17,"grid description and action typography");
    puts("PASS feature settings: retained cell/control identity, callbacks, dynamic labels, scoped table styles, native grid/delegates");
}

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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
    [UIView setAnimationsEnabled:NO];
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
    [navigation setViewControllers:@[root] animated:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
    [root tableView:root.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:8 inSection:0]];
    UITableViewController *translation=(UITableViewController *)navigation.topViewController;[translation loadViewIfNeeded];
    printf("UIKit route: class=%s title=%s style=%ld stack=%lu\n",NSStringFromClass(translation.class).UTF8String,translation.title.UTF8String,(long)translation.tableView.style,(unsigned long)navigation.viewControllers.count);fflush(stdout);
    Check([translation.title isEqual:@"自动翻译"] && translation.tableView.style==UITableViewStyleInsetGrouped,"translation module remains reachable");
    UITableViewCell *details=[translation tableView:translation.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    Check(feature.textLabel.font.pointSize==details.textLabel.font.pointSize && [feature.textLabel.font.fontDescriptor isEqual:details.textLabel.font.fontDescriptor],"main and translation titles share font and size");
    Check([feature.detailTextLabel.font.fontDescriptor isEqual:details.detailTextLabel.font.fontDescriptor],"main and translation subtitles share font and size");
    Check(![translation tableView:translation.tableView titleForFooterInSection:0] && ![translation tableView:translation.tableView titleForFooterInSection:1],"both highlighted translation footnotes removed");
    CheckFeatureAppearance(details);
    puts("PASS UIKit settings: grouped layout, shared fonts, all feature rows, original selection/account/lifecycle, Zzy-X branding, removed highlighted regions");fflush(stdout);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{exit(0);});
    });
    });
    return YES;
}
@end
int main(int argc,char **argv) {@autoreleasepool {return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}

