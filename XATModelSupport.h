#ifndef XAT_MODEL_SUPPORT_H
#define XAT_MODEL_SUPPORT_H

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Only call implemented getters with a matching ABI. In particular, never use
// KVC or reinterpret an integer statusID as an Objective-C object.
static const char *XATUnqualifiedType(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

static char XATGetterReturnType(id object, SEL selector) {
    if (!object || !selector) return '\0';
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return '\0';
    char *encoding = method_copyReturnType(method);
    char result = XATUnqualifiedType(encoding)[0];
    free(encoding);
    return result;
}

static id SafeCallZeroArgObject(id object, SEL selector) {
    if (XATGetterReturnType(object, selector) != '@') return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (NSException *exception) {
        (void)exception;
        return nil;
    }
}

static BOOL SafeCallZeroArgBool(id object, SEL selector) {
    @try {
        switch (XATGetterReturnType(object, selector)) {
            case 'B': return ((_Bool (*)(id, SEL))objc_msgSend)(object, selector);
            case 'c': return ((signed char (*)(id, SEL))objc_msgSend)(object, selector) != 0;
            case 'C': return ((unsigned char (*)(id, SEL))objc_msgSend)(object, selector) != 0;
            default: return NO;
        }
    } @catch (NSException *exception) {
        (void)exception;
        return NO;
    }
}

// Timeline models may wrap another model before exposing their status. Identity
// based cycle detection and both node/depth limits bound even malformed graphs.
static NSArray *XATModelObjects(id model) {
    if (!model) return @[];
    static const NSUInteger maxNodes = 32;
    static const NSUInteger maxDepth = 8;
    NSArray<NSString *> *wrappers = @[@"status", @"representedStatus", @"viewModel",
                                       @"statusViewModel", @"coreStatus", @"tweet"];
    NSMutableArray *objects = [NSMutableArray arrayWithObject:model];
    NSMutableArray<NSNumber *> *depths = [NSMutableArray arrayWithObject:@0];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality |
                                                        NSPointerFunctionsStrongMemory];
    [seen addObject:model];
    for (NSUInteger index = 0; index < objects.count && objects.count < maxNodes; index++) {
        NSUInteger depth = depths[index].unsignedIntegerValue;
        if (depth >= maxDepth) continue;
        for (NSString *name in wrappers) {
            id nested = SafeCallZeroArgObject(objects[index], NSSelectorFromString(name));
            if (!nested || [seen containsObject:nested]) continue;
            [seen addObject:nested];
            [objects addObject:nested];
            [depths addObject:@(depth + 1)];
            if (objects.count >= maxNodes) break;
        }
    }
    return objects;
}

// Reject zero, signs, non-digits and overflow; canonicalize leading zeros so a
// string ID and the same 64-bit integer ID share one deduplication key.
static NSString *XATDecimalID(NSString *string) {
    if (![string isKindOfClass:[NSString class]] || string.length == 0 || string.length > 20) return nil;
    uint64_t value = 0;
    for (NSUInteger index = 0; index < string.length; index++) {
        unichar character = [string characterAtIndex:index];
        if (character < '0' || character > '9') return nil;
        uint64_t digit = character - '0';
        if (value > (UINT64_MAX - digit) / 10) return nil;
        value = value * 10 + digit;
    }
    return value ? [NSString stringWithFormat:@"%llu", (unsigned long long)value] : nil;
}

static NSString *XATIDFromGetter(id object, SEL selector) {
    @try {
        char type = XATGetterReturnType(object, selector);
        if (type == '@') {
            id value = SafeCallZeroArgObject(object, selector);
            if ([value isKindOfClass:[NSString class]]) return XATDecimalID(value);
            if ([value isKindOfClass:[NSNumber class]]) return XATDecimalID([value stringValue]);
            return nil;
        }
        unsigned long long unsignedValue = 0;
        long long signedValue = 0;
        BOOL isSigned = YES;
        switch (type) {
            case 'q': signedValue = ((long long (*)(id, SEL))objc_msgSend)(object, selector); break;
            case 'l': signedValue = ((long (*)(id, SEL))objc_msgSend)(object, selector); break;
            case 'i': signedValue = ((int (*)(id, SEL))objc_msgSend)(object, selector); break;
            case 's': signedValue = ((short (*)(id, SEL))objc_msgSend)(object, selector); break;
            case 'Q': unsignedValue = ((unsigned long long (*)(id, SEL))objc_msgSend)(object, selector); isSigned = NO; break;
            case 'L': unsignedValue = ((unsigned long (*)(id, SEL))objc_msgSend)(object, selector); isSigned = NO; break;
            case 'I': unsignedValue = ((unsigned int (*)(id, SEL))objc_msgSend)(object, selector); isSigned = NO; break;
            case 'S': unsignedValue = ((unsigned short (*)(id, SEL))objc_msgSend)(object, selector); isSigned = NO; break;
            default: return nil;
        }
        if (isSigned) {
            if (signedValue <= 0) return nil;
            unsignedValue = (unsigned long long)signedValue;
        }
        return unsignedValue ? [NSString stringWithFormat:@"%llu", unsignedValue] : nil;
    } @catch (NSException *exception) {
        (void)exception;
        return nil;
    }
}

static NSString *XATOwnTweetID(id object) {
    NSArray<NSString *> *fields = @[@"statusIDString", @"tweetIDString", @"statusID", @"tweetID",
                                     @"statusId", @"tweetId", @"restID", @"restId", @"idStr"];
    for (NSString *field in fields) {
        NSString *identifier = XATIDFromGetter(object, NSSelectorFromString(field));
        if (identifier) return identifier;
    }
    return nil;
}

static NSString *ExtractTweetID(id model) {
    for (id object in XATModelObjects(model)) {
        NSString *identifier = XATOwnTweetID(object);
        if (identifier) return identifier;
    }
    return nil; // An object address is never a tweet ID.
}

static NSString *XATOwnSourceText(id object) {
    NSArray<NSString *> *fields = @[@"originalText", @"fullText", @"primaryText", @"displayText", @"text"];
    for (NSString *field in fields) {
        id value = SafeCallZeroArgObject(object, NSSelectorFromString(field));
        if ([value isKindOfClass:[NSAttributedString class]]) value = [value string];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

static NSString *XATSourceText(id model) {
    for (id object in XATModelObjects(model)) {
        NSString *text = XATOwnSourceText(object);
        if (text) return text;
    }
    return nil;
}

static NSString *XATSourceLanguage(id model) {
    NSArray<NSString *> *fields = @[@"language", @"primaryLanguage", @"languageCode", @"lang"];
    for (id object in XATModelObjects(model)) {
        for (NSString *field in fields) {
            id value = SafeCallZeroArgObject(object, NSSelectorFromString(field));
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
        }
    }
    return nil;
}

static NSString *XATModelIdentity(id model) {
    NSString *identifier = ExtractTweetID(model);
    if (identifier) return [@"id:" stringByAppendingString:identifier];
    NSString *text = XATSourceText(model);
    return text.length ? [@"text:" stringByAppendingString:text] : nil;
}

// Body and translate-button adapters can have different wrapper models for one
// status. Keep the submitted marker on the deepest matching status object so a
// second adapter cannot toggle the same shared status back to its original text.
static id XATRequestOwner(id model) {
    NSString *identifier = ExtractTweetID(model);
    NSString *text = identifier ? nil : XATSourceText(model);
    id owner = model;
    for (id object in XATModelObjects(model)) {
        if (identifier) {
            if ([identifier isEqualToString:XATOwnTweetID(object)]) owner = object;
        } else if (text && [text isEqualToString:XATOwnSourceText(object)]) {
            owner = object;
        }
    }
    return owner;
}

static BOOL XATModelIsShowingTranslation(id model) {
    for (id object in XATModelObjects(model)) {
        if (SafeCallZeroArgBool(object, NSSelectorFromString(@"showingTranslation")) ||
            SafeCallZeroArgBool(object, NSSelectorFromString(@"isShowingTranslation"))) return YES;
    }
    return NO;
}

#endif
