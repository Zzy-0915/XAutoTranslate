#import <Foundation/Foundation.h>

extern void XATScheduleInitialization(void);

// A native ObjC image supplies an independent loader entry; the C side deduplicates it.
@interface XATAppleBootstrapV10 : NSObject
@end
@implementation XATAppleBootstrapV10
+ (void)load {

    XATScheduleInitialization();
}
@end
