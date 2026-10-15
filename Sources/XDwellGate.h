#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface XDwellGate : NSObject
- (instancetype)initWithClock:(NSTimeInterval (^)(void))clock delay:(NSTimeInterval)delay;
- (BOOL)eligible:(id)view key:(NSString *)key visible:(BOOL)visible stationary:(BOOL)stationary position:(double)position;
- (void)reset:(id)view;
@end
NS_ASSUME_NONNULL_END
