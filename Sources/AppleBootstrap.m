#import <Foundation/Foundation.h>

extern void XATScheduleInitialization(void);

// A native ObjC image supplies an independent loader entry; the C side deduplicates it.
@interface XATAppleBootstrapV14 : NSObject
@end
@implementation XATAppleBootstrapV14
+ (void)load {

    XATScheduleInitialization();
}
@end
