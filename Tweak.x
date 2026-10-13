#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface TFNTwitterStatus : NSObject
@property (nonatomic, readonly) long long statusID;
@property (nonatomic, copy, readonly) NSString *statusIDString;
@property (nonatomic, copy, readonly) NSString *primaryText;
@property (nonatomic, copy, readonly) NSString *legacyLanguage;
@end

@interface T1StatusView : UIView
@property (nonatomic, strong) TFNTwitterStatus *status;
@end

static NSCache *gTranslationCache = nil;
static NSMutableSet *gPendingRequests = nil;
static dispatch_queue_t gTranslateQueue = nil;
static NSString *const kXAutoTranslateNotification = @"kXAutoTranslateDidCompleteNotification";

static BOOL IsChineseText(NSString *text) {
    if (!text || text.length == 0) return YES;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= 0x4e00 && c <= 0x9fff) {
            return YES;
        }
    }
    return NO;
}

static void RequestTranslation(NSString *text, NSString *statusID) {
    if (!text || text.length == 0 || !statusID) return;

    @synchronized (gPendingRequests) {
        if ([gPendingRequests containsObject:statusID]) return;
        [gPendingRequests addObject:statusID];
    }

    dispatch_async(gTranslateQueue, ^{
        NSString *encodedText = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *urlString = [NSString stringWithFormat:@"https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q=%@", encodedText];
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)" forHTTPHeaderField:@"User-Agent"];
        request.timeoutInterval = 10.0;

        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            @synchronized (gPendingRequests) {
                [gPendingRequests removeObject:statusID];
            }

            if (error || !data) return;

            NSError *jsonErr = nil;
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if (!jsonErr && [json isKindOfClass:[NSArray class]] && [json count] > 0) {
                NSArray *segments = json[0];
                NSMutableString *translatedFull = [NSMutableString string];
                
                if ([segments isKindOfClass:[NSArray class]]) {
                    for (id seg in segments) {
                        if ([seg isKindOfClass:[NSArray class]] && [seg count] > 0) {
                            [translatedFull appendString:seg[0]];
                        }
                    }
                }

                if (translatedFull.length > 0) {
                    [gTranslationCache setObject:[translatedFull copy] forKey:statusID];

                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:kXAutoTranslateNotification
                                                                            object:statusID];
                    });
                }
            }
        }];
        [task resume];
    });
}

%hook TFNTwitterStatus

- (NSString *)primaryText {
    NSString *orig = %orig;
    if (!orig || orig.length == 0) return orig;

    NSString *sid = self.statusIDString ?: [NSString stringWithFormat:@"%lld", self.statusID];
    if (!sid || [sid isEqualToString:@"0"]) return orig;

    NSString *cached = [gTranslationCache objectForKey:sid];
    if (cached) {
        if ([cached isEqualToString:orig]) return orig;
        return [NSString stringWithFormat:@"%@\n\n🇨🇳 [自动翻译]\n%@", orig, cached];
    }

    if (IsChineseText(orig) && orig.length < 15) {
        [gTranslationCache setObject:orig forKey:sid];
        return orig;
    }

    RequestTranslation(orig, sid);
    return orig;
}

%end

%hook T1StatusView

- (instancetype)initWithFrame:(CGRect)frame {
    id orig = %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_xAutoTranslateHandleRefresh:)
                                                 name:kXAutoTranslateNotification
                                               object:nil];
    return orig;
}

%new
- (void)_xAutoTranslateHandleRefresh:(NSNotification *)note {
    NSString *updatedSid = note.object;
    NSString *mySid = self.status.statusIDString ?: [NSString stringWithFormat:@"%lld", self.status.statusID];
    if ([mySid isEqualToString:updatedSid]) {
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        gTranslationCache = [[NSCache alloc] init];
        gTranslationCache.countLimit = 500;
        gPendingRequests = [[NSMutableSet alloc] init];
        gTranslateQueue = dispatch_queue_create("com.hook.x.autotranslate", DISPATCH_QUEUE_SERIAL);
    }
}
