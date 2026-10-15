#import "XGTXEngine.h"
NS_ASSUME_NONNULL_BEGIN
@interface XOfficialObservation : NSObject
@property(nonatomic,strong,nullable) XGTXResult *result;
@property(nonatomic) BOOL failed,inFlight,unavailable;
@property(nonatomic) NSInteger code;
@end
@interface XTranslationRouter : NSObject
@property(nonatomic,copy,nullable) void (^didFinish)(NSString *key);
- (instancetype)initWithEngine:(XGTXEngine *)engine clock:(NSTimeInterval (^)(void))clock
                        start:(BOOL (^)(id context))start
                      inspect:(XOfficialObservation *(^)(id context))inspect;
- (void)submit:(NSString *)key text:(NSString *)text language:(NSString *)language context:(id)context;
- (void)tickWithVisibleKeys:(NSSet<NSString *> *)visible;
- (NSDictionary<NSString *,NSNumber *> *)statistics;
@end
NS_ASSUME_NONNULL_END
