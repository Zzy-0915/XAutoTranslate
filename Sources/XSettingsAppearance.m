#import "XSettingsAppearance.h"
#import <objc/runtime.h>
#import <objc/message.h>

static void (*originalNavigation)(id,SEL);
static id Get(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id (*)(id,SEL))objc_msgSend)(object,selector) : nil;
}
static NSArray *Rows(id controller) {
    id rows=Get(controller,@"sections");return [rows isKindOfClass:NSArray.class] ? rows : @[];
}
UITableViewCell *XATSettingsCell(UITableView *table,NSString *identifier) {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:identifier];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
    cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryNone;cell.imageView.image=nil;
    cell.textLabel.text=nil;cell.detailTextLabel.text=nil;
    return cell;
}
static void NavigationLabels(UIView *view) {
    if([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        label.text=[label.text stringByReplacingOccurrencesOfString:@"NFB-X" withString:@"Zzy-X"];
        if([label.text containsString:@"Zzy-X"]) label.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    }
    for(UIView *child in view.subviews) NavigationLabels(child);
}
static void Navigation(UIViewController *controller,SEL selector) {
    if(originalNavigation) originalNavigation(controller,selector);
    controller.title=@"Zzy-X";
    NavigationLabels(controller.navigationItem.titleView);
}
static void SetupTable(UIViewController *controller,SEL selector) {
    (void)selector;
    UITableView *table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    table.translatesAutoresizingMaskIntoConstraints=NO;table.dataSource=(id<UITableViewDataSource>)controller;table.delegate=(id<UITableViewDelegate>)controller;
    table.rowHeight=UITableViewAutomaticDimension;table.estimatedRowHeight=60;
    table.backgroundColor=UIColor.systemGroupedBackgroundColor;
    ((void (*)(id,SEL,id))objc_msgSend)(controller,NSSelectorFromString(@"setTableView:"),table);
    [controller.view addSubview:table];
}
static void Layout(UIViewController *controller,SEL selector) {
    (void)selector;UITableView *table=Get(controller,@"tableView");
    if(![table isKindOfClass:UITableView.class]) return;
    [NSLayoutConstraint activateConstraints:@[
        [table.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:controller.view.topAnchor],
        [table.bottomAnchor constraintEqualToAnchor:controller.view.bottomAnchor]]];
}
static void NoFooter(id controller,SEL selector) {(void)controller;(void)selector;}
static NSInteger Sections(id controller,SEL selector,UITableView *table) {(void)controller;(void)selector;(void)table;return 1;}
static NSInteger Count(id controller,SEL selector,UITableView *table,NSInteger section) {(void)selector;(void)table;return section==0 ? (NSInteger)Rows(controller).count : 0;}
static UIView *NoSupplement(id controller,SEL selector,UITableView *table,NSInteger section) {(void)controller;(void)selector;(void)table;(void)section;return nil;}
static CGFloat SupplementHeight(id controller,SEL selector,UITableView *table,NSInteger section) {(void)controller;(void)selector;(void)table;(void)section;return UITableViewAutomaticDimension;}
static UITableViewCell *Cell(id controller,SEL selector,UITableView *table,NSIndexPath *path) {
    (void)selector;UITableViewCell *cell=XATSettingsCell(table,@"XATSettingsNavigation");
    NSArray *rows=Rows(controller);id row=path.row<(NSInteger)rows.count ? rows[path.row] : nil;
    NSDictionary *item=[row isKindOfClass:NSDictionary.class] ? row : @{};
    cell.textLabel.text=[item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : @"";
    cell.detailTextLabel.text=[item[@"subtitle"] isKindOfClass:NSString.class] ? item[@"subtitle"] : nil;
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleDefault;
    return cell;
}
static void Replace(Class cls,NSString *name,IMP replacement,IMP *old) {
    SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(cls,selector);if(!method) return;
    if(old) *old=method_getImplementation(method);
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
}
void XATInstallSettingsAppearance(Class cls) {
    // Only replace this controller's presentation. Its lifecycle, account, row data,
    // didSelectRowAtIndexPath and every original feature controller stay intact.
    if(!class_getInstanceMethod(cls,NSSelectorFromString(@"setTableView:"))) return;
    Replace(cls,@"setupNavigationBar",(IMP)Navigation,(IMP *)&originalNavigation);
    Replace(cls,@"setupTableView",(IMP)SetupTable,NULL);
    Replace(cls,@"setupLayout",(IMP)Layout,NULL);
    Replace(cls,@"setupFooterLabel",(IMP)NoFooter,NULL);
    Replace(cls,@"numberOfSectionsInTableView:",(IMP)Sections,NULL);
    Replace(cls,@"tableView:numberOfRowsInSection:",(IMP)Count,NULL);
    Replace(cls,@"tableView:cellForRowAtIndexPath:",(IMP)Cell,NULL);
    Replace(cls,@"tableView:viewForHeaderInSection:",(IMP)NoSupplement,NULL);
    Replace(cls,@"tableView:viewForFooterInSection:",(IMP)NoSupplement,NULL);
    Replace(cls,@"tableView:heightForHeaderInSection:",(IMP)SupplementHeight,NULL);
    Replace(cls,@"tableView:heightForFooterInSection:",(IMP)SupplementHeight,NULL);
}
