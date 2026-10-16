#import "XFeatureAppearance.h"
#import "XSettingsStyle.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Retain the imported controllers, cell classes and actual controls. Their
// targets, menus, tags, model updates and collection/drag delegates remain native.
static _Thread_local unsigned tableConstruction;
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
        label.font=small ? XATDetailFont() : [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        label.textColor=small ? UIColor.secondaryLabelColor : UIColor.labelColor;
        label.numberOfLines=1;
    }
    for(UIView *child in view.subviews) Fonts(child,navigation);
}
static void CollectControls(UIView *view,NSMutableArray<UIView *> *controls) {
    for(UIView *child in view.subviews) {
        if([child isKindOfClass:UIControl.class]) [controls addObject:child];
        else CollectControls(child,controls);
    }
}
static void AdaptCell(UITableViewCell *cell) {
    UILabel *title=Get(cell,@"titleLabel"),*subtitle=Get(cell,@"subtitleLabel");
    if(![title isKindOfClass:UILabel.class]) {XATStyleCell(cell,cell.textLabel,cell.detailTextLabel);return;}
    if(!XATHasCellLayout(cell)) {
        NSMutableArray<UIView *> *controls=NSMutableArray.new;
        CollectControls(cell.contentView,controls);
        // accessoryView already has native layout; only relocate controls that
        // the old custom cell laid out inside its oversized content area.
        if(!cell.accessoryView && controls.count) {
            for(UIView *control in controls) {
                [control removeFromSuperview];control.transform=CGAffineTransformIdentity;
                control.translatesAutoresizingMaskIntoConstraints=YES;
                CGSize size=[control sizeThatFits:CGSizeMake(160,44)];
                if(size.width>0 && size.height>0) control.frame=(CGRect){CGPointZero,size};
            }
            if(controls.count==1) cell.accessoryView=controls.firstObject;
            else {
                UIStackView *accessory=[[UIStackView alloc] initWithArrangedSubviews:controls];accessory.spacing=8;
                CGSize size=[accessory systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
                accessory.frame=(CGRect){CGPointZero,size};cell.accessoryView=accessory;
            }
        }
        BOOL disclosure=[Get(cell,@"chevronImageView") isKindOfClass:UIImageView.class];
        if(!cell.accessoryView && disclosure) cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    XATStyleCell(cell,title,[subtitle isKindOfClass:UILabel.class] ? subtitle : nil);
}
static void StyleTable(UIViewController *controller) {
    UITableView *table=Get(controller,@"tableView");if(![table isKindOfClass:UITableView.class]) return;
    XATFitTable(controller,table);
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
    for(NSString *name in @[@"tableView:viewForHeaderInSection:",@"tableView:viewForFooterInSection:",@"tableView:titleForHeaderInSection:",@"tableView:titleForFooterInSection:"])
        Replace(cls,NSSelectorFromString(name),imp_implementationWithBlock(^id(id receiver,UITableView *table,NSInteger section){(void)receiver;(void)table;(void)section;return nil;}));
    for(NSString *name in @[@"tableView:heightForHeaderInSection:",@"tableView:heightForFooterInSection:"]){
        BOOL header=[name containsString:@"Header"];
        Replace(cls,NSSelectorFromString(name),imp_implementationWithBlock(^CGFloat(id receiver,UITableView *table,NSInteger section){(void)receiver;(void)table;(void)section;return header ? 24 : 8;}));
    }
    SEL height=@selector(tableView:heightForRowAtIndexPath:);
    if(class_getInstanceMethod(cls,height)) Replace(cls,height,imp_implementationWithBlock(^CGFloat(id receiver,UITableView *table,NSIndexPath *path){
        (void)receiver;(void)table;(void)path;return 60;
    }));
}
static void ItemFonts(UIView *view) {
    if([view isKindOfClass:UILabel.class]) XATSingleLine((UILabel *)view,NO,view.bounds.size.width);
    for(UIView *child in view.subviews) ItemFonts(child);
}
static char gridLayoutKey;
static void FitGrid(UIViewController *controller,UICollectionView *grid) {
    if(objc_getAssociatedObject(grid,&gridLayoutKey) || !grid.superview) return;
    UIView *parent=grid.superview;
    for(UIView *view=parent;view;view=view.superview) {
        NSMutableArray *old=NSMutableArray.new;
        for(NSLayoutConstraint *c in view.constraints) {
            BOOL first=c.firstItem==grid && (c.firstAttribute==NSLayoutAttributeTop || c.firstAttribute==NSLayoutAttributeLeading || c.firstAttribute==NSLayoutAttributeTrailing || c.firstAttribute==NSLayoutAttributeLeft || c.firstAttribute==NSLayoutAttributeRight || c.firstAttribute==NSLayoutAttributeWidth || c.firstAttribute==NSLayoutAttributeCenterX);
            BOOL second=c.secondItem==grid && (c.secondAttribute==NSLayoutAttributeTop || c.secondAttribute==NSLayoutAttributeLeading || c.secondAttribute==NSLayoutAttributeTrailing || c.secondAttribute==NSLayoutAttributeLeft || c.secondAttribute==NSLayoutAttributeRight || c.secondAttribute==NSLayoutAttributeWidth || c.secondAttribute==NSLayoutAttributeCenterX);
            if(first || second) [old addObject:c];
        }
        [NSLayoutConstraint deactivateConstraints:old];if(view==controller.view) break;
    }
    grid.translatesAutoresizingMaskIntoConstraints=NO;
    UILayoutGuide *guide=parent==controller.view ? parent.safeAreaLayoutGuide : parent.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:20],
        [grid.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-20],
        [grid.topAnchor constraintEqualToAnchor:guide.topAnchor constant:24]]];
    BOOL vertical=NO;
    for(UIView *view=grid;view;view=view.superview) {
        for(NSLayoutConstraint *c in view.constraints)
            if((c.firstItem==grid && (c.firstAttribute==NSLayoutAttributeHeight || c.firstAttribute==NSLayoutAttributeBottom)) ||
               (c.secondItem==grid && (c.secondAttribute==NSLayoutAttributeHeight || c.secondAttribute==NSLayoutAttributeBottom))) vertical=YES;
        if(view==controller.view) break;
    }
    if(!vertical) [grid.heightAnchor constraintEqualToConstant:MAX(60,grid.bounds.size.height)].active=YES;
    objc_setAssociatedObject(grid,&gridLayoutKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void StyleGrid(UIViewController *controller) {
    controller.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    Fonts(controller.navigationItem.titleView,YES);
    UILabel *header=Get(controller,@"headerLabel");if([header isKindOfClass:UILabel.class]) {header.hidden=YES;header.text=nil;}
    for(NSString *name in @[@"colorCollectionView",@"collectionView",@"appIconCollectionView"]) {
        UICollectionView *grid=Get(controller,name);if(![grid isKindOfClass:UICollectionView.class]) continue;
        FitGrid(controller,grid);
        grid.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
        grid.layer.cornerRadius=12;grid.clipsToBounds=YES;
        for(UICollectionViewCell *cell in grid.visibleCells) ItemFonts(cell.contentView);
        for(NSString *kind in @[UICollectionElementKindSectionHeader,UICollectionElementKindSectionFooter])
            for(UICollectionReusableView *view in [grid visibleSupplementaryViewsOfKind:kind]) Fonts(view,NO);
    }
    UIButton *restore=Get(controller,@"restoreButton");
    if([restore isKindOfClass:UIButton.class]) restore.titleLabel.font=XATTitleFont();
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
                original(cell,layout);
                XATLayoutCell(cell);
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
