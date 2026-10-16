#import "XNativeTranslation.h"
#import <objc/runtime.h>
#import <objc/message.h>
@interface NSObject (XATNativeTranslationAPI)
- (instancetype)initWithTranslation:(NSString *)translation previewTranslation:(id)preview entities:(id)entities translationSource:(NSString *)provider localizedSourceLanguage:(NSString *)name sourceLanguage:(NSString *)source destinationLanguage:(NSString *)destination polls:(id)polls translationState:(NSString *)state;
- (instancetype)initWithTranslation:(id)translation forUnderlyingViewModel:(id)model;
- (instancetype)initWithURLs:(id)urls mentions:(id)mentions hashtags:(id)hashtags symbols:(id)symbols timestamps:(id)timestamps;
- (id)getInfoFor:(id)model;
- (id)getOrCreateInfoFor:(id)model;
- (void)setInfo:(id)info for:(id)model;
- (void)setOriginalStatus:(id)model;
- (void)setTranslatedStatus:(id)model;
- (void)setTranslationError:(id)error;
- (void)setState:(NSInteger)state;
@end
static id Get(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    return signature.numberOfArguments==2 && signature.methodReturnType[0]=='@' ? ((id (*)(id,SEL))objc_msgSend)(object,selector) : nil;
}
static NSString *Text(id value) {return [value isKindOfClass:NSString.class] ? value : nil;}
static NSInteger State(id info) {
    SEL selector=NSSelectorFromString(@"state");
    return [info respondsToSelector:selector] ? ((NSInteger (*)(id,SEL))objc_msgSend)(info,selector) : -1;
}
static id TranslationFromInfo(id info) {return Get(Get(info,@"translatedStatus"),@"translation");}
static XGTXResult *Result(id translation,NSString *original,NSString *language) {
    NSString *text=Text(Get(translation,@"translation"));
    NSString *destination=Text(Get(translation,@"destinationLanguage"));
    if(!text.length || !destination.length || !XGTXChinese(destination) || !XGTXTranslationChanged(text,original)) return nil;
    XGTXResult *result=XGTXResult.new;result.text=text;
    result.language=Text(Get(translation,@"sourceLanguage")) ?: language;result.nativeTranslation=translation;
    return result;
}
XGTXResult *XATNativeResult(id model,id info,NSString *original,NSString *language) {
    @try {
        XGTXResult *manual=State(info)==3 ? Result(TranslationFromInfo(info),original,language) : nil;
        return manual ?: Result(Get(model,@"grokTranslatedPost"),original,language);
    } @catch(NSException *e) {(void)e;return nil;}
}
BOOL XATNativeMatches(id info,NSString *text) {
    NSInteger state=State(info);
    return (state==0 || state==3 || state==4) && [Text(Get(TranslationFromInfo(info),@"translation")) isEqual:text] && [Text(Get(Get(info,@"translatedStatus"),@"text")) isEqual:text];
}
NSInteger XATNativeDisplayOverride(id model,id info,XGTXResult *cached,NSString *original,NSString *language,NSUInteger kind) {
    if(XGTXChinese(language)) return -1;
    NSInteger state=State(info);
    if(cached && XATNativeMatches(info,cached.text)) {
        if(kind==0) return state==3 || state==4;
        return kind==1 ? 1 : 0;
    }
    XGTXResult *valid=XATNativeResult(model,info,original,language);
    if((state==3 || state==4) && !valid && kind<2) return 0;
    if(Get(model,@"grokTranslatedPost") && !valid && kind>=2) return 0;
    return -1;
}
NSUInteger XATNativePublish(id model,id helper,XGTXResult *result,NSString *original) {
    if(!XGTXTranslationChanged(result.text,original) || ![helper respondsToSelector:@selector(getInfoFor:)] || ![helper respondsToSelector:@selector(setInfo:for:)]) return 0;
    @try {
        if(XATNativeMatches([helper getInfoFor:model],result.text)) return 1;
        Class translationClass=NSClassFromString(@"TFSTwitterTranslation");
        Class wrapperClass=NSClassFromString(@"T1TranslatedStatusViewModel");
        if(!class_getInstanceMethod(translationClass,@selector(initWithTranslation:previewTranslation:entities:translationSource:localizedSourceLanguage:sourceLanguage:destinationLanguage:polls:translationState:)) || !class_getInstanceMethod(wrapperClass,@selector(initWithTranslation:forUnderlyingViewModel:))) return 0;
        id translation=result.nativeTranslation;
        if(![Text(Get(translation,@"translation")) isEqual:result.text] || !XGTXChinese(Text(Get(translation,@"destinationLanguage")))) {
            Class entityClass=NSClassFromString(@"TFSTwitterEntitySet");
            if(!class_getInstanceMethod(entityClass,@selector(initWithURLs:mentions:hashtags:symbols:timestamps:))) return 0;
            id entities=[[entityClass alloc] initWithURLs:@[] mentions:@[] hashtags:@[] symbols:@[] timestamps:@[]];
            id provider=Get(NSClassFromString(@"T1TranslationProvider"),@"googleTranslationProvider");
            NSString *providerSource=Text(Get(provider,@"translationSource"));
            if(!entities || !providerSource.length) return 0;
            NSString *name=[[[NSLocale alloc] initWithLocaleIdentifier:@"zh_CN"] localizedStringForLanguageCode:result.language] ?: result.language;
            translation=[[translationClass alloc] initWithTranslation:result.text previewTranslation:nil entities:entities translationSource:providerSource localizedSourceLanguage:name sourceLanguage:result.language destinationLanguage:@"zh-CN" polls:nil translationState:@""];
        }
        id wrapper=[[wrapperClass alloc] initWithTranslation:translation forUnderlyingViewModel:model];
        // Verify the exact getter consumed by native text layout, before publishing success.
        if(![Text(Get(wrapper,@"text")) isEqual:result.text]) return 0;
        // T1PostTranslationInfo.init traps in X 12.33. Only X's factory may create it.
        if(![helper respondsToSelector:@selector(getOrCreateInfoFor:)]) return 0;
        id info=[helper getOrCreateInfoFor:model];
        if(![info respondsToSelector:@selector(setState:)] || ![info respondsToSelector:@selector(setOriginalStatus:)] || ![info respondsToSelector:@selector(setTranslatedStatus:)] || ![info respondsToSelector:@selector(setTranslationError:)]) return 0;
        [info setOriginalStatus:model];[info setTranslatedStatus:wrapper];[info setTranslationError:nil];[info setState:3];
        [helper setInfo:info for:model];
        return XATNativeMatches([helper getInfoFor:model],result.text) ? 2 : 0;
    } @catch(NSException *e) {(void)e;return 0;}
}
BOOL XATNativeNotify(id model,NSString *dynamicKey,NSString *animatedKey) {
    NSString *name=Text(Get(model,@"statusItemViewModelDidUpdateNotificationName"));
    if(!name.length || !dynamicKey.length || !animatedKey.length) return NO;
    [NSNotificationCenter.defaultCenter postNotificationName:name object:model userInfo:@{dynamicKey:@YES,animatedKey:@NO}];
    return YES;
}
