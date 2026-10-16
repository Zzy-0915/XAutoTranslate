#import <Foundation/Foundation.h>

extern void XATScheduleInitialization(void);

// A native ObjC image supplies an independent loader entry; the C side deduplicates it.
@interface XATAppleBootstrapV11 : NSObject
@end
@implementation XATAppleBootstrapV11
+ (void)load {

    XATScheduleInitialization();
}
@end
