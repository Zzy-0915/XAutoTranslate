#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include "XDiagnostics.h"

extern void XATScheduleInitialization(void);

// A native ObjC image supplies an independent loader entry; the C side deduplicates it.
@interface XATAppleBootstrapV8 : NSObject
@end
@implementation XATAppleBootstrapV8
+ (void)load {
    XADBootstrap("OBJC_LOAD_ENTER");
    XATScheduleInitialization();
}
@end
