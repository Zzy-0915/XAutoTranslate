#import <Foundation/Foundation.h>

extern void XATScheduleInitialization(void);

// A native ObjC image supplies an independent loader entry; the C side deduplicates it.
@interface XATAppleBootstrapV12 : NSObject
@end
@implementation XATAppleBootstrapV12
+ (void)load {

    XATScheduleInitialization();
}
@end
