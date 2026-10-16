#import "XFeatureAppearance.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Retain the imported controllers, cell classes and actual controls. Their
// targets, menus, tags, model updates and collection/drag delegates remain native.
static _Thread_local unsigned tableConstruction;
static char adaptedKey;
@interface UITableView (XATFeatureConstruction)
- (instancetype)xat_featureInitWithFrame:(CGRect)frame style:(UITableViewStyle)style __attribute__((objc_method_family(init)));
@end
@implementation UITableView (XATFeatureConstruction)
- (instancetype)xat_featureInitWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    // The alias has the init ownership convention, including consumed self.
    // After exchange this invokes UIKit's original designated initializer.
    return [self xat_featureInitWithFrame:frame style:tableConstruction ? UITableViewStyleInsetGrouped : style];
}
@end
static id Get(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id (*)(id,SEL))objc_msgSend)(object,selector) : nil;
}
static void Replace(Class cls,SEL selector,IMP replacement) {
    Method method=class_getInstanceMethod(cls,selector);if(!method) return;
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
}
static void Fonts(UIView *view,BOOL navigation) {
    if([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        BOOL small=[label.text hasPrefix:@"@"] || !navigation;
        label.font=[UIFont systemFontOfSize:small ? 12 : 17 weight:navigation && !small ? UIFontWeightSemibold : UIFontWeightRegular];
        label.textColor=small ? UIColor.secondaryLabelColor : UIColor.labelColor;
        label.numberOfLines=0;
    }
    for(UIView *child in view.subviews) Fonts(child,navigation);
}
static void CellFonts(UITableViewCell *cell) {
    UILabel *title=Get(cell,@"titleLabel"),*subtitle=Get(cell,@"subtitleLabel");
    if(![title isKindOfClass:UILabel.class]) title=cell.textLabel;
    if(![subtitle isKindOfClass:UILabel.class]) subtitle=cell.detailTextLabel;
    title.font=[UIFont systemFontOfSize:17];title.numberOfLines=0;title.textColor=UIColor.labelColor;
    subtitle.font=[UIFont systemFontOfSize:12];subtitle.numberOfLines=0;subtitle.textColor=UIColor.secondaryLabelColor;
    cell.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
}
static void CollectControls(UIView *view,NSMutableArray<UIView *> *controls) {
    for(UIView *child in view.subviews) {
        if([child isKindOfClass:UIControl.class]) [controls addObject:child];
        else CollectControls(child,controls);
    }
}
static void AdaptCell(UITableViewCell *cell) {
    UILabel *title=Get(cell,@"titleLabel"),*subtitle=Get(cell,@"subtitleLabel");
    if(![title isKindOfClass:UILabel.class]) {CellFonts(cell);return;}
    if(!objc_getAssociatedObject(cell,&adaptedKey)) {
        NSMutableArray<UIView *> *controls=NSMutableArray.new;
        CollectControls(cell.contentView,controls);
        // accessoryView already has native layout; only relocate controls that
        // the old custom cell laid out inside its oversized content area.
        if(!cell.accessoryView && controls.count) {
            for(UIView *control in controls) {
                [control removeFromSuperview];control.transform=CGAffineTransformIdentity;
                control.translatesAutoresizingMaskIntoConstraints=YES;
            }
            if(controls.count==1) cell.accessoryView=controls.firstObject;
            else {
                UIStackView *accessory=[[UIStackView alloc] initWithArrangedSubviews:controls];accessory.spacing=8;
                CGSize size=[accessory systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
                accessory.frame=(CGRect){CGPointZero,size};cell.accessoryView=accessory;
            }
        }
        BOOL disclosure=[Get(cell,@"chevronImageView") isKindOfClass:UIImageView.class];
        [title removeFromSuperview];
        if([subtitle isKindOfClass:UILabel.class]) [subtitle removeFromSuperview];
        [NSLayoutConstraint deactivateConstraints:cell.contentView.constraints];
        // Keep old views alive for original configure/theme methods and popover
        // anchors. They no longer contribute old spacing or custom typography.
        for(UIView *view in cell.contentView.subviews) view.hidden=YES;
        UIStackView *labels=[[UIStackView alloc] initWithArrangedSubviews:
            [subtitle isKindOfClass:UILabel.class] ? @[title,subtitle] : @[title]];
        labels.axis=UILayoutConstraintAxisVertical;labels.spacing=3;labels.translatesAutoresizingMaskIntoConstraints=NO;
        title.translatesAutoresizingMaskIntoConstraints=NO;subtitle.translatesAutoresizingMaskIntoConstraints=NO;
        title.hidden=NO;subtitle.hidden=NO;
        [cell.contentView addSubview:labels];
        UILayoutGuide *margin=cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [labels.leadingAnchor constraintEqualToAnchor:margin.leadingAnchor],
            [labels.trailingAnchor constraintEqualToAnchor:margin.trailingAnchor],
            [labels.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [labels.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
            [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
        if(!cell.accessoryView && disclosure) cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        objc_setAssociatedObject(cell,&adaptedKey,labels,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *labels=objc_getAssociatedObject(cell,&adaptedKey);
    for(UIView *view in cell.contentView.subviews) if(view!=labels) view.hidden=YES;
    CellFonts(cell);
}
static void StyleTable(UIViewController *controller) {
    UITableView *table=Get(controller,@"tableView");if(![table isKindOfClass:UITableView.class]) return;
    controller.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    table.backgroundColor=UIColor.systemGroupedBackgroundColor;
    table.rowHeight=UITableViewAutomaticDimension;table.estimatedRowHeight=60;
    table.separatorStyle=UITableViewCellSeparatorStyleSingleLine;
    Fonts(table.tableHeaderView,NO);Fonts(table.tableFooterView,NO);
    Fonts(controller.navigationItem.titleView,YES);
}
static void InstallList(Class cls) {
    SEL setup=NSSelectorFromString(@"setupTable");Method method=class_getInstanceMethod(cls,setup);
    if(!method) return;
    void (*original)(id,SEL)=(void *)method_getImplementation(method);
    Replace(cls,setup,imp_implementationWithBlock(^(UIViewController *controller){
        tableConstruction++;
        @try {original(controller,setup);} @finally {tableConstruction--;}
        StyleTable(controller);
    }));
    SEL cellSelector=@selector(tableView:cellForRowAtIndexPath:);method=class_getInstanceMethod(cls,cellSelector);
    if(method) {
        UITableViewCell *(*cell)(id,SEL,id,id)=(void *)method_getImplementation(method);
        Replace(cls,cellSelector,imp_implementationWithBlock(^UITableViewCell *(id controller,UITableView *table,NSIndexPath *path){
            UITableViewCell *result=cell(controller,cellSelector,table,path);AdaptCell(result);return result;
        }));
    }
    SEL nav=NSSelectorFromString(@"setupNav");method=class_getInstanceMethod(cls,nav);
    if(method) {
        void (*navigation)(id,SEL)=(void *)method_getImplementation(method);
        Replace(cls,nav,imp_implementationWithBlock(^(UIViewController *controller){navigation(controller,nav);Fonts(controller.navigationItem.titleView,YES);}));
    }
    for(NSString *name in @[@"tableView:viewForHeaderInSection:",@"tableView:viewForFooterInSection:"]) {
        SEL supplement=NSSelectorFromString(name);method=class_getInstanceMethod(cls,supplement);
        if(method) {
            UIView *(*originalSupplement)(id,SEL,id,NSInteger)=(void *)method_getImplementation(method);
            Replace(cls,supplement,imp_implementationWithBlock(^UIView *(id controller,UITableView *table,NSInteger section){
                UIView *view=originalSupplement(controller,supplement,table,section);Fonts(view,NO);return view;
            }));
        }
    }
    SEL height=@selector(tableView:heightForRowAtIndexPath:);
    if(class_getInstanceMethod(cls,height)) Replace(cls,height,imp_implementationWithBlock(^CGFloat(id receiver,UITableView *table,NSIndexPath *path){
        (void)receiver;(void)table;(void)path;return UITableViewAutomaticDimension;
    }));
}
static void StyleGrid(UIViewController *controller) {
    controller.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    Fonts(controller.navigationItem.titleView,YES);
    UILabel *header=Get(controller,@"headerLabel");if([header isKindOfClass:UILabel.class]) Fonts(header,NO);
    for(NSString *name in @[@"colorCollectionView",@"collectionView",@"appIconCollectionView"]) {
        UICollectionView *grid=Get(controller,name);if(![grid isKindOfClass:UICollectionView.class]) continue;
        grid.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
        grid.layer.cornerRadius=12;grid.clipsToBounds=YES;
        for(UICollectionViewCell *cell in grid.visibleCells) Fonts(cell.contentView,NO);
        for(NSString *kind in @[UICollectionElementKindSectionHeader,UICollectionElementKindSectionFooter])
            for(UICollectionReusableView *view in [grid visibleSupplementaryViewsOfKind:kind]) Fonts(view,NO);
    }
    UIButton *restore=Get(controller,@"restoreButton");
    if([restore isKindOfClass:UIButton.class]) restore.titleLabel.font=[UIFont systemFontOfSize:17];
}
void XATInstallFeatureAppearance(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        method_exchangeImplementations(class_getInstanceMethod(UITableView.class,@selector(initWithFrame:style:)),
            class_getInstanceMethod(UITableView.class,@selector(xat_featureInitWithFrame:style:)));
        for(NSString *name in @[@"ModernSettingsTableViewCell",@"ModernSettingsSimpleButtonCell",@"ModernSettingsCompactButtonCell",@"ModernSettingsToggleCell"]) {
            Class cls=NSClassFromString(name);SEL layout=@selector(layoutSubviews);Method layoutMethod=class_getInstanceMethod(cls,layout);
            if(!layoutMethod) continue;
            void (*original)(id,SEL)=(void *)method_getImplementation(layoutMethod);
            Replace(cls,layout,imp_implementationWithBlock(^(UITableViewCell *cell){
                if(objc_getAssociatedObject(cell,&adaptedKey)) CellFonts(cell);
                original(cell,layout);
            }));
        }
        for(NSString *name in @[@"GeneralSettingsViewController",@"TwitterBlueSettingsViewController",@"TweetsSettingsViewController",@"MediaDownloadsSettingsViewController",@"ProfilesSettingsViewController",@"WebSettingsViewController",@"BrandingSettingsViewController",@"ExperimentalSettingsViewController",@"ModernSettingsPlaceholderViewController"])
            InstallList(NSClassFromString(name));
        for(NSString *name in @[@"BHColorThemeViewController",@"BHCustomTabBarViewController",@"BHAppIconViewController"]) {
            Class cls=NSClassFromString(name);SEL layout=@selector(viewDidLayoutSubviews);Method layoutMethod=class_getInstanceMethod(cls,layout);
            if(!layoutMethod) continue;
            void (*original)(id,SEL)=(void *)method_getImplementation(layoutMethod);
            Replace(cls,layout,imp_implementationWithBlock(^(UIViewController *controller){original(controller,layout);StyleGrid(controller);}));
        }
    });
}
