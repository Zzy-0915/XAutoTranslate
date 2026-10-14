#import "../XATModelSupport.h"
#include <stdio.h>

// Compile/run on macOS:
// xcrun clang -fobjc-arc -framework Foundation tests/ModelSupportTests.m -o /tmp/xat-model-tests
// /tmp/xat-model-tests

@interface XATMockStatus : NSObject
@property(nonatomic, strong) id statusIDString;
@property(nonatomic, strong) id statusID;
@property(nonatomic, strong) id primaryText;
@property(nonatomic, strong) id originalText;
@property(nonatomic, strong) id displayText;
@property(nonatomic, strong) id fullText;
@property(nonatomic, strong) id text;
@property(nonatomic, strong) id language;
@property(nonatomic, strong) id primaryLanguage;
@property(nonatomic, strong) id languageCode;
@property(nonatomic) BOOL showingTranslation;
@end
@implementation XATMockStatus
@end

@interface XATMockWrapper : NSObject
@property(nonatomic, strong) id status;
@property(nonatomic, strong) id representedStatus;
@property(nonatomic, strong) id viewModel;
@property(nonatomic, strong) id statusViewModel;
@property(nonatomic, strong) id coreStatus;
@property(nonatomic, strong) id tweet;
@end
@implementation XATMockWrapper
@end

@interface XATSignedStatus : NSObject
@property(nonatomic) long long statusID;
@end
@implementation XATSignedStatus
@end

@interface XATUnsignedStatus : NSObject
@property(nonatomic) unsigned long long statusID;
@end
@implementation XATUnsignedStatus
@end

// Calling these with an object ABI would be unsafe. Their counters prove that
// invalid fields are rejected before invoking their implementations.
@interface XATInvalidGetters : NSObject
@property(nonatomic) NSUInteger reads;
@end
@implementation XATInvalidGetters
- (double)status { self.reads++; return 1.5; }
- (void *)representedStatus { self.reads++; return NULL; }
- (long long)primaryText { self.reads++; return 99; }
- (int)language { self.reads++; return 1; }
- (id)showingTranslation { self.reads++; return @YES; }
@end

@interface XATThrowingGetter : NSObject
@end
@implementation XATThrowingGetter
- (id)status { @throw [NSException exceptionWithName:@"MockGetter" reason:@"unavailable" userInfo:nil]; }
@end

@interface XATAlternateTranslationFlag : NSObject
@property(nonatomic) BOOL isShowingTranslation;
@property(nonatomic) BOOL isTranslated;
@end
@implementation XATAlternateTranslationFlag
@end

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #condition); return 1; \
} } while (0)

int main(void) {
    @autoreleasepool {
        CHECK(ExtractTweetID(nil) == nil);
        CHECK(XATModelIdentity(nil) == nil);
        CHECK(XATRequestOwner(nil) == nil);
        CHECK(XATSourceText(nil) == nil);
        CHECK(XATSourceLanguage(nil) == nil);
        CHECK(!XATModelIsShowingTranslation(nil));
        CHECK(ExtractTweetID([NSObject new]) == nil);
        CHECK(XATModelIdentity([NSObject new]) == nil);
        CHECK(SafeCallZeroArgObject(nil, @selector(status)) == nil);
        CHECK(!SafeCallZeroArgBool(nil, @selector(showingTranslation)));

        XATMockStatus *status = [XATMockStatus new];
        status.statusIDString = @"00012345678901234567";
        status.primaryText = @"Timeline body";
        status.language = @"en";
        CHECK([ExtractTweetID(status) isEqualToString:@"12345678901234567"]);
        CHECK([XATModelIdentity(status) isEqualToString:@"id:12345678901234567"]);

        XATMockWrapper *outer = [XATMockWrapper new];
        XATMockWrapper *inner = [XATMockWrapper new];
        outer.viewModel = inner;
        inner.statusViewModel = outer; // Deliberate cycle.
        inner.representedStatus = status;
        CHECK(XATModelObjects(outer).count == 3);
        CHECK([ExtractTweetID(outer) isEqualToString:ExtractTweetID(status)]);
        CHECK([XATSourceText(outer) isEqualToString:@"Timeline body"]);
        CHECK([XATSourceLanguage(outer) isEqualToString:@"en"]);
        CHECK([XATModelIdentity(outer) isEqualToString:XATModelIdentity(status)]);
        CHECK(XATRequestOwner(outer) == status);
        XATMockWrapper *buttonWrapper = [XATMockWrapper new];
        buttonWrapper.coreStatus = status;
        CHECK(XATRequestOwner(buttonWrapper) == XATRequestOwner(outer));
        CHECK(XATRequestOwner(status) == status);
        NSObject *unidentified = [NSObject new];
        CHECK(XATRequestOwner(unidentified) == unidentified);
        CHECK(!XATModelIsShowingTranslation(outer));
        status.showingTranslation = YES;
        CHECK(XATModelIsShowingTranslation(outer));

        XATMockWrapper *other = [XATMockWrapper new];
        XATMockStatus *sameStatus = [XATMockStatus new];
        sameStatus.statusID = @12345678901234567ULL;
        other.status = sameStatus;
        CHECK([XATModelIdentity(other) isEqualToString:XATModelIdentity(outer)]);

        // Every supported wrapper accessor can reach a status without a UI API.
        XATMockWrapper *first = [XATMockWrapper new];
        XATMockWrapper *second = [XATMockWrapper new];
        XATMockWrapper *third = [XATMockWrapper new];
        first.status = second;
        second.coreStatus = third;
        third.tweet = status;
        CHECK([ExtractTweetID(first) isEqualToString:ExtractTweetID(status)]);

        status.statusIDString = @"0";
        status.statusID = @0;
        CHECK(ExtractTweetID(status) == nil);
        CHECK([XATModelIdentity(status) isEqualToString:@"text:Timeline body"]);
        CHECK(XATRequestOwner(outer) == status);
        CHECK(XATRequestOwner(buttonWrapper) == status);
        status.primaryText = nil;
        CHECK(XATModelIdentity(status) == nil);
        status.statusIDString = @"000";
        CHECK(ExtractTweetID(status) == nil);
        status.statusIDString = @"not-a-tweet";
        status.statusID = [NSDate date];
        CHECK(ExtractTweetID(status) == nil);
        status.statusIDString = @"18446744073709551616"; // UINT64_MAX + 1.
        CHECK(ExtractTweetID(status) == nil);
        status.statusIDString = @"-1";
        CHECK(ExtractTweetID(status) == nil);
        status.statusIDString = @"1.5";
        CHECK(ExtractTweetID(status) == nil);
        status.statusIDString = @" 123";
        CHECK(ExtractTweetID(status) == nil);
        status.statusIDString = nil;
        status.statusID = @1.5;
        CHECK(ExtractTweetID(status) == nil);
        status.statusID = @987654321012345678ULL;
        CHECK([ExtractTweetID(status) isEqualToString:@"987654321012345678"]);

        XATSignedStatus *signedStatus = [XATSignedStatus new];
        signedStatus.statusID = 9223372036854775807LL;
        CHECK([ExtractTweetID(signedStatus) isEqualToString:@"9223372036854775807"]);
        CHECK(SafeCallZeroArgObject(signedStatus, @selector(statusID)) == nil);
        signedStatus.statusID = 0;
        CHECK(ExtractTweetID(signedStatus) == nil);
        signedStatus.statusID = -1;
        CHECK(ExtractTweetID(signedStatus) == nil);
        XATUnsignedStatus *unsignedStatus = [XATUnsignedStatus new];
        unsignedStatus.statusID = UINT64_MAX;
        CHECK([ExtractTweetID(unsignedStatus) isEqualToString:@"18446744073709551615"]);
        unsignedStatus.statusID = 0;
        CHECK(ExtractTweetID(unsignedStatus) == nil);

        status.primaryText = @42;
        status.originalText = [NSNull null];
        status.fullText = @[];
        status.displayText = [[NSAttributedString alloc] initWithString:@"Attributed timeline body"];
        status.language = @42;
        status.primaryLanguage = [NSNull null];
        status.languageCode = @"ja";
        CHECK([XATSourceText(status) isEqualToString:@"Attributed timeline body"]);
        CHECK([XATSourceLanguage(status) isEqualToString:@"ja"]);
        status.displayText = @"";
        status.text = @"Plain fallback body";
        CHECK([XATSourceText(status) isEqualToString:@"Plain fallback body"]);
        status.originalText = @"Original body";
        CHECK([XATSourceText(status) isEqualToString:@"Original body"]);
        status.languageCode = nil;
        status.primaryLanguage = @"ko";
        CHECK([XATSourceLanguage(status) isEqualToString:@"ko"]);

        XATInvalidGetters *invalid = [XATInvalidGetters new];
        CHECK(XATModelIdentity(invalid) == nil);
        CHECK(XATSourceLanguage(invalid) == nil);
        CHECK(!XATModelIsShowingTranslation(invalid));
        CHECK(invalid.reads == 0);
        CHECK(XATModelIdentity([XATThrowingGetter new]) == nil);
        XATAlternateTranslationFlag *translation = [XATAlternateTranslationFlag new];
        translation.isTranslated = YES; // A cached translation does not mean it is displayed.
        CHECK(!XATModelIsShowingTranslation(translation));
        translation.isShowingTranslation = YES;
        CHECK(XATModelIsShowingTranslation(translation));

        // A long chain must stop after a bounded number of getter calls.
        XATMockWrapper *chain = [XATMockWrapper new];
        XATMockWrapper *tail = chain;
        for (NSUInteger index = 0; index < 100; index++) {
            XATMockWrapper *next = [XATMockWrapper new];
            tail.status = next;
            tail = next;
        }
        tail.status = status;
        CHECK(XATModelObjects(chain).count <= 32);
        CHECK(ExtractTweetID(chain) == nil);

        inner.statusViewModel = nil; // Break the intentional strong-reference cycle.
        puts("PASS: model ID, wrappers, source fields, ABI checks and translation-state tests");
    }
    return 0;
}
