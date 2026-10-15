#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface XGTXResult : NSObject
@property(nonatomic,copy) NSString *text;
@property(nonatomic,copy) NSString *language;
@property(nonatomic,strong,nullable) id nativeTranslation;
@end

FOUNDATION_EXPORT NSString *XGTXDigest(NSString *text);
FOUNDATION_EXPORT BOOL XGTXChinese(NSString *language);
FOUNDATION_EXPORT BOOL XGTXTranslationChanged(NSString *translation,NSString *original);
FOUNDATION_EXPORT XGTXResult * _Nullable XGTXParse(NSData *data);
FOUNDATION_EXPORT NSArray<NSString *> *XGTXChunks(NSString *text);

@interface XGTXEngine : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic,copy,nullable) void (^didFinish)(NSString *key);
// All scheduling APIs run on main; successful cache reads are safe on any thread.
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration
                                clock:(NSTimeInterval (^)(void))clock
                             interval:(NSTimeInterval)interval;
- (nullable XGTXResult *)cached:(NSString *)key;
- (void)storeSuccess:(NSString *)key text:(NSString *)text language:(NSString *)language;
- (void)storeResult:(NSString *)key result:(XGTXResult *)result;
- (void)enqueue:(NSString *)key text:(NSString *)text language:(NSString *)language;
- (void)keepQueuedKeys:(NSSet<NSString *> *)visibleKeys;
- (void)pump;
- (NSDictionary<NSString *,NSNumber *> *)statistics;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
