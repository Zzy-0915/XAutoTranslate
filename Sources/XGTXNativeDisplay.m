#import "XGTXNativeDisplay.h"
#include "XDiagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface NSObject (XATNativeTextFactory)
- (instancetype)initWithStatusID:(long long)statusID cardData:(id)card originalText:(NSString *)text fromUserID:(long long)userID date:(NSDate *)date;
- (instancetype)initWithCanonicalStatus:(id)canonical fromUser:(id)user;
@end
static id ObjectValue(id object,NSString *name) {
    SEL sel=NSSelectorFromString(name);NSMethodSignature *signature=[object methodSignatureForSelector:sel];
    return signature.numberOfArguments==2 && signature.methodReturnType[0]=='@' ? ((id (*)(id,SEL))objc_msgSend)(object,sel) : nil;
}
static long long IntegerValue(id object,NSString *name) {
    SEL sel=NSSelectorFromString(name);NSMethodSignature *signature=[object methodSignatureForSelector:sel];
    return signature.numberOfArguments==2 && (signature.methodReturnType[0]=='q' || signature.methodReturnType[0]=='Q') ? ((long long (*)(id,SEL))objc_msgSend)(object,sel) : 0;
}
id XGTXNativeDisplay(id status,NSString *translation,NSString *language,NSUInteger options,id (*original)(id,SEL,NSUInteger)) {
    if(!status || !translation.length || !original) return nil;
    Class canonicalClass=NSClassFromString(@"TFNTwitterCanonicalStatus"),statusClass=NSClassFromString(@"TFNTwitterStatus");
    if(!class_getInstanceMethod(canonicalClass,@selector(initWithStatusID:cardData:originalText:fromUserID:date:)) ||
        !class_getInstanceMethod(statusClass,@selector(initWithCanonicalStatus:fromUser:))) return nil;
    NSString *name=[[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"] localizedStringForLanguageCode:language] ?: language;
    NSString *display=[NSString stringWithFormat:@"%@ 已翻译\n\n%@",name,translation];
    NSString *escaped=[[[display stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"] stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"] stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    @try {
        id canonical=[[canonicalClass alloc] initWithStatusID:IntegerValue(status,@"statusID") cardData:nil originalText:escaped
            fromUserID:IntegerValue(status,@"fromUserID") date:ObjectValue(status,@"date") ?: NSDate.date];
        id proxy=[[statusClass alloc] initWithCanonicalStatus:canonical fromUser:ObjectValue(status,@"fromUser")];
        // Return X's own model: both its sizing and drawing paths consume this object.
        return proxy ? original(proxy,NSSelectorFromString(@"_tfn_displayTextModelForOptions:"),options) : nil;
    } @catch(NSException *exception) {
        XADLog("RENDER","native text factory exception=%s; preserve original layout",exception.name.UTF8String);
        return nil;
    }
}
