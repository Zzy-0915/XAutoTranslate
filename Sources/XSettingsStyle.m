#import "XSettingsStyle.h"
#import <objc/runtime.h>

static char layoutKey,sourceKey,renderedKey;
UIFont *XATTitleFont(void) {
    static UIFont *font;static dispatch_once_t once;
    dispatch_once(&once,^{font=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil].textLabel.font;});return font;
}
UIFont *XATDetailFont(void) {
    static UIFont *font;static dispatch_once_t once;
    dispatch_once(&once,^{font=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil].detailTextLabel.font;});return font;
}
static CGFloat Width(NSString *text,UIFont *font) {return [text sizeWithAttributes:@{NSFontAttributeName:font}].width;}
static NSString *Compact(NSString *source,UIFont *font,CGFloat width) {
    NSString *text=[[source componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    text=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(Width(text,font)<=width) return text;
    for(NSString *prefix in @[@"启用此功能后，",@"开启此功能后，",@"开启后，",@"启用后，",@"允许您",@"您可以",@"此功能可以",@"此功能将",@"使用此功能",@"Enable this option to ",@"This option allows you to "])
        if([text hasPrefix:prefix]) {text=[text substringFromIndex:prefix.length];break;}
    // Select the leading meaningful clause before resorting to a width-bound
    // composed-character abbreviation. Never shrink the shared font to fit.
    NSArray *clauses=[text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"。；;\n"]];
    if(clauses.count>1 && [clauses.firstObject length]) text=clauses.firstObject;
    if(Width(text,font)>width) {
        NSArray *phrases=[text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"，,（("]];
        if(phrases.count>1 && [phrases.firstObject length]) text=phrases.firstObject;
    }
    if(Width(text,font)<=width) return text;
    NSMutableString *result=NSMutableString.new;
    [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *part,NSRange range,NSRange enclosing,BOOL *stop){
        (void)range;(void)enclosing;
        if(Width([[result stringByAppendingString:part] stringByAppendingString:@"…"],font)>width) {*stop=YES;return;}
        [result appendString:part];
    }];return [result stringByAppendingString:@"…"];
}
void XATSingleLine(UILabel *label,BOOL detail,CGFloat width) {
    if(!label) return;
    label.font=detail ? XATDetailFont() : XATTitleFont();label.numberOfLines=1;
    label.adjustsFontSizeToFitWidth=NO;label.lineBreakMode=NSLineBreakByTruncatingTail;
    label.textColor=detail ? UIColor.secondaryLabelColor : UIColor.labelColor;
    if(!detail || width<=0) return;
    NSString *last=objc_getAssociatedObject(label,&renderedKey);
    NSString *source=objc_getAssociatedObject(label,&sourceKey);
    if(![label.text isEqualToString:last]) source=label.text ?: @"";
    NSString *rendered=Compact(source ?: @"",label.font,width);
    objc_setAssociatedObject(label,&sourceKey,source,OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(label,&renderedKey,rendered,OBJC_ASSOCIATION_COPY_NONATOMIC);
    label.text=rendered;
}
void XATStyleTable(UITableView *table) {
    table.backgroundColor=UIColor.systemGroupedBackgroundColor;
    table.rowHeight=60;table.estimatedRowHeight=60;
    table.sectionHeaderHeight=24;table.sectionFooterHeight=8;table.sectionHeaderTopPadding=0;
    table.separatorStyle=UITableViewCellSeparatorStyleSingleLine;
    table.separatorInset=UIEdgeInsetsMake(0,20,0,20);
    table.cellLayoutMarginsFollowReadableWidth=NO;
    table.contentInset=UIEdgeInsetsZero;table.tableHeaderView=nil;table.tableFooterView=nil;
}
void XATFitTable(UIViewController *controller,UITableView *table) {
    XATStyleTable(table);controller.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    if(controller.view==table || !table.superview) return;
    for(UIView *parent=table.superview;parent;parent=parent.superview) {
        NSMutableArray *constraints=NSMutableArray.new;
        for(NSLayoutConstraint *constraint in parent.constraints)
            if(constraint.firstItem==table || constraint.secondItem==table) [constraints addObject:constraint];
        [NSLayoutConstraint deactivateConstraints:constraints];
        if(parent==controller.view) break;
    }
    table.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[
        [table.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:controller.view.topAnchor],
        [table.bottomAnchor constraintEqualToAnchor:controller.view.bottomAnchor]]];
}
BOOL XATHasCellLayout(UITableViewCell *cell) {return objc_getAssociatedObject(cell,&layoutKey)!=nil;}
void XATStyleCell(UITableViewCell *cell,UILabel *title,UILabel *detail) {
    if(!title) return;
    if(!XATHasCellLayout(cell)) {
        [title removeFromSuperview];[detail removeFromSuperview];
        [NSLayoutConstraint deactivateConstraints:cell.contentView.constraints];
        for(UIView *view in cell.contentView.subviews) view.hidden=YES;
        [cell.contentView addSubview:title];if(detail) [cell.contentView addSubview:detail];
        title.translatesAutoresizingMaskIntoConstraints=YES;detail.translatesAutoresizingMaskIntoConstraints=YES;
        objc_setAssociatedObject(cell,&layoutKey,detail ? @[title,detail] : @[title],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    XATLayoutCell(cell);
}
void XATLayoutCell(UITableViewCell *cell) {
    NSArray<UILabel *> *labels=objc_getAssociatedObject(cell,&layoutKey);if(!labels.count) return;
    UILabel *title=labels[0],*detail=labels.count>1 ? labels[1] : nil;
    for(UIView *view in cell.contentView.subviews) view.hidden=view!=title && view!=detail;
    CGFloat width=MAX(0,cell.contentView.bounds.size.width-40),height=cell.contentView.bounds.size.height;
    XATSingleLine(title,NO,width);XATSingleLine(detail,YES,width);
    CGFloat titleHeight=ceil(title.font.lineHeight),detailHeight=detail.text.length ? ceil(detail.font.lineHeight) : 0;
    CGFloat y=MAX(0,(height-titleHeight-detailHeight-(detailHeight ? 3 : 0))/2);
    title.frame=CGRectMake(20,y,width,titleHeight);
    detail.frame=CGRectMake(20,y+titleHeight+3,width,detailHeight);
    title.hidden=NO;detail.hidden=!detailHeight;
    cell.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    cell.separatorInset=UIEdgeInsetsMake(0,20,0,20);
}
