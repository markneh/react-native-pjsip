#import <React/RCTUtils.h>
#import <pjsua.h>

typedef NS_ENUM(NSUInteger, PJSIPCallDeclineReason) {
    PJSIPCallDeclineReasonUnknown = 0,
    PJSIPCallDeclineReasonBusy = 1,
};

@interface PjSipCall : NSObject

@property int id;
@property bool isHeld;
@property bool isMuted;

@property (nonatomic, strong) NSString *xCallId;

+ (instancetype)itemConfig:(int)id;

- (void)hangup;
- (BOOL)decline;
- (BOOL)declineWithReason:(PJSIPCallDeclineReason)reason;
- (void)answer;
- (void)reportRinging;
- (void)hold;
- (void)unhold;
- (void)mute;
- (void)unmute;
- (void)xfer:(NSString*) destination;
- (void)xferReplaces:(int) destinationCallId;
- (void)redirect:(NSString*) destination;
- (void)dtmf:(NSString*) digits;

- (void)onStateChanged:(pjsua_call_info) callInfo;
- (void)onMediaStateChanged:(pjsua_call_info) callInfo;

- (NSDictionary *)toJsonDictionary:(bool) isSpeaker;

@end
