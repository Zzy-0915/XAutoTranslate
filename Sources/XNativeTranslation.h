#import "XGTXEngine.h"
NS_ASSUME_NONNULL_BEGIN
// Read the translation wrapper itself. representedStatus deliberately points to original text.
FOUNDATION_EXPORT XGTXResult * _Nullable XATNativeResult(id model,id _Nullable info,NSString *original,NSString *language);
FOUNDATION_EXPORT BOOL XATNativeMatches(id _Nullable info,NSString *text);
// kind: manual text, manual button, auto text, auto button. -1 preserves X's decision.
FOUNDATION_EXPORT NSInteger XATNativeDisplayOverride(id model,id _Nullable info,XGTXResult * _Nullable cached,NSString *original,NSString *language,NSUInteger kind);
// 0 = failure, 1 = already registered (including user's show-original state), 2 = published.
FOUNDATION_EXPORT NSUInteger XATNativePublish(id model,id helper,XGTXResult *result,NSString *original);
FOUNDATION_EXPORT BOOL XATNativeNotify(id model,NSString * _Nullable dynamicKey,NSString * _Nullable animatedKey);
NS_ASSUME_NONNULL_END
