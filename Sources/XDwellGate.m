#import "XDwellGate.h"
#include <math.h>
@interface XDwellEntry : NSObject
@property(nonatomic,copy) NSString *key;
@property(nonatomic) NSTimeInterval began;
@property(nonatomic) double position;
@end
@implementation XDwellEntry
@end
@interface XDwellGate ()
@property(nonatomic,strong) NSMapTable<id,XDwellEntry *> *entries;
@property(nonatomic,copy) NSTimeInterval (^clock)(void);
@property(nonatomic) NSTimeInterval delay;
@end
@implementation XDwellGate
- (instancetype)initWithClock:(NSTimeInterval (^)(void))clock delay:(NSTimeInterval)delay {
    if((self=[super init])) {_clock=[clock copy];_delay=delay;_entries=NSMapTable.weakToStrongObjectsMapTable;}return self;
}
- (void)reset:(id)view {[self.entries removeObjectForKey:view];}
- (BOOL)eligible:(id)view key:(NSString *)key visible:(BOOL)visible stationary:(BOOL)stationary position:(double)position {
    if(!visible || !stationary) {[self reset:view];return NO;}
    XDwellEntry *entry=[self.entries objectForKey:view];NSTimeInterval now=self.clock();
    if(!entry || ![entry.key isEqual:key] || fabs(entry.position-position)>2) {
        entry=XDwellEntry.new;entry.key=key;entry.began=now;entry.position=position;[self.entries setObject:entry forKey:view];return NO;
    }
    return now-entry.began>=self.delay;
}
@end
