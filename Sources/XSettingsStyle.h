#import <UIKit/UIKit.h>

FOUNDATION_EXPORT UIFont *XATTitleFont(void);
FOUNDATION_EXPORT UIFont *XATDetailFont(void);
FOUNDATION_EXPORT void XATStyleTable(UITableView *table);
FOUNDATION_EXPORT void XATFitTable(UIViewController *controller,UITableView *table);
FOUNDATION_EXPORT void XATStyleCell(UITableViewCell *cell,UILabel *title,UILabel *detail);
FOUNDATION_EXPORT void XATLayoutCell(UITableViewCell *cell);
FOUNDATION_EXPORT void XATSingleLine(UILabel *label,BOOL detail,CGFloat width);
FOUNDATION_EXPORT BOOL XATHasCellLayout(UITableViewCell *cell);
