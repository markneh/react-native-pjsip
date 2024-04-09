#import "PjSipEndpoint.h"
#import "PjSipModule.h"
#import "PjSipUtil.h"

#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTUtils.h>

@interface PjSipModule ()

@end

@implementation PjSipModule

@synthesize bridge = _bridge;

- (dispatch_queue_t)methodQueue {
    // TODO: Use special thread may be ?
    // return dispatch_queue_create("com.carusto.PJSipMdule", DISPATCH_QUEUE_SERIAL);
    return dispatch_get_main_queue();
}

- (instancetype)init {
    self = [super init];
    return self;
}

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

RCT_EXPORT_METHOD(start: (NSDictionary *) config callback: (RCTResponseSenderBlock) callback) {

    [PjSipEndpoint instanceWithConfig:config].bridge = self.bridge;
    
    if ([[PjSipEndpoint instanceWithConfig:config] isStarted]) {
        NSDictionary *initialState = [[PjSipEndpoint instance] getInitialState:config];
        callback(@[@(YES), initialState]);
        return;
    }

    BOOL success = [[PjSipEndpoint instance] startWithConfig:config];
    NSDictionary *initialState = [[PjSipEndpoint instance] getInitialState:config];
    callback(@[@(success), initialState]);
}

RCT_EXPORT_METHOD(stop: (RCTResponseSenderBlock)callback) {
    BOOL success = [[PjSipEndpoint instance] stop];
    callback(@[@(success), @{}]);
}

RCT_EXPORT_METHOD(reconnect:(RCTResponseSenderBlock)callback) {
    BOOL success = [[PjSipEndpoint instance] relaunchUDPConnection];
    callback(@[@(success), @{}]);
}

RCT_EXPORT_METHOD(isStarted: (RCTResponseSenderBlock)callback) {
    callback(@[@YES, @{ @"is_started": @([[PjSipEndpoint instance] isStarted]) }]);
}

RCT_EXPORT_METHOD(updateStunServers: (int) accountId stunServerList:(NSArray *) stunServerList callback:(RCTResponseSenderBlock) callback) {
    [[PjSipEndpoint instance] updateStunServers:accountId stunServerList:stunServerList];
    callback(@[@TRUE]);
}

#pragma mark - Account Actions

RCT_EXPORT_METHOD(createAccount: (NSDictionary *) config callback:(RCTResponseSenderBlock) callback) {
    PjSipAccount *account = [[PjSipEndpoint instance] createAccount:config];
    callback(@[@TRUE, [account toJsonDictionary]]);
}

RCT_EXPORT_METHOD(updateAccount: (int)accountId
                  withCredentials: (NSDictionary *)credentials
                  callback:(RCTResponseSenderBlock) callback) {
    @try {
        PjSipEndpoint *endpoint = [PjSipEndpoint instance];
        PjSipAccount *account = [endpoint findAccount:accountId];

        if (!account) {
            callback(@[@FALSE, @"User was not found"]);
        } else {
            BOOL result = [account updateCredentials:credentials];
            callback(@[@(result)]);
        }
    } @catch (NSException *exception) {
        callback(@[@FALSE, @"User was not found"]);
    }
}

RCT_EXPORT_METHOD(deleteAccount: (int) accountId callback:(RCTResponseSenderBlock) callback) {
    [[PjSipEndpoint instance] deleteAccount:accountId];
    callback(@[@TRUE]);
}

RCT_EXPORT_METHOD(registerAccount: (int) accountId renew:(BOOL) renew callback:(RCTResponseSenderBlock) callback) {
    @try {
        PjSipEndpoint* endpoint = [PjSipEndpoint instance];
        PjSipAccount *account = [endpoint findAccount:accountId];

        [account register:renew];

        callback(@[@TRUE]);
    }
    @catch (NSException * e) {
        callback(@[@FALSE, e.reason]);
    }
}

#pragma mark - Call Actions

RCT_EXPORT_METHOD(makeCall: (int) accountId destination: (NSString *) destination callSettings:(NSDictionary*) callSettings msgData:(NSDictionary*) msgData callback:(RCTResponseSenderBlock) callback) {
    @try {
        PjSipEndpoint* endpoint = [PjSipEndpoint instance];
        PjSipAccount *account = [endpoint findAccount:accountId];
        PjSipCall *call = [endpoint makeCall:account destination:destination callSettings:callSettings msgData:msgData];

        // TODO: Remove this function
        // Automatically put other calls on hold.
        [endpoint pauseParallelCalls:call];

        callback(@[@TRUE, [call toJsonDictionary:endpoint.isSpeaker]]);
    }
    @catch (NSException * e) {
        callback(@[@FALSE, e.reason]);
    }
}

RCT_EXPORT_METHOD(hangupCall: (int) callId callback:(RCTResponseSenderBlock) callback) {
    PjSipCall *call = [[PjSipEndpoint instance] findCall:callId];

    if (call) {
        [call hangup];
        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(declineCall:(NSDictionary *)params callback:(RCTResponseSenderBlock) callback) {
    int callId = [params[@"callId"] intValue];
    int reason = [params[@"reason"] intValue];

    PjSipCall *call = [[PjSipEndpoint instance] findCall:callId];

    if (call) {
        BOOL success = [call declineWithReason:(PJSIPCallDeclineReason)reason];
        callback(@[@(success)]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(answerCall: (int) callId callback:(RCTResponseSenderBlock) callback) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    PjSipCall *call = [endpoint findCall:callId];

    if (call) {
        [call answer];

        // Automatically put other calls on hold.
        [endpoint pauseParallelCalls:call];

        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(holdCall: (int) callId callback:(RCTResponseSenderBlock) callback) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    PjSipCall *call = [endpoint findCall:callId];

    if (call) {
        [call hold];
        [endpoint emmitCallChanged:call];

        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(unholdCall: (int) callId callback:(RCTResponseSenderBlock) callback) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    PjSipCall *call = [endpoint findCall:callId];

    if (call) {
        [call unhold];
        [endpoint emmitCallChanged:call];

        // Automatically put other calls on hold.
        [endpoint pauseParallelCalls:call];

        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(muteCall: (int) callId callback:(RCTResponseSenderBlock) callback) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    PjSipCall *call = [endpoint findCall:callId];

    if (call) {
        [call mute];
        [endpoint emmitCallChanged:call];
        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(unMuteCall: (int) callId callback:(RCTResponseSenderBlock) callback) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    PjSipCall *call = [endpoint findCall:callId];

    if (call) {
        [call unmute];
        [endpoint emmitCallChanged:call];
        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(xferCall: (int) callId destination: (NSString *) destination callback:(RCTResponseSenderBlock) callback) {
    PjSipCall *call = [[PjSipEndpoint instance] findCall:callId];

    if (call) {
        [call xfer:destination];
        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(xferReplacesCall: (int) callId destinationCallId: (int) destinationCallId callback:(RCTResponseSenderBlock) callback) {
    PjSipCall *call = [[PjSipEndpoint instance] findCall:callId];

    if (call) {
        [call xferReplaces:destinationCallId];
        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(redirectCall: (int) callId destination: (NSString *) destination callback:(RCTResponseSenderBlock) callback) {
    PjSipCall *call = [[PjSipEndpoint instance] findCall:callId];

    if (call) {
        [call redirect:destination];
        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(dtmfCall: (int) callId digits: (NSString *) digits callback:(RCTResponseSenderBlock) callback) {
    PjSipCall *call = [[PjSipEndpoint instance] findCall:callId];

    if (call) {
        [call dtmf:digits];
        callback(@[@TRUE]);
    } else {
        callback(@[@FALSE, @"Call not found"]);
    }
}

RCT_EXPORT_METHOD(useSpeaker: (int) callId callback:(RCTResponseSenderBlock) callback) {
    [[PjSipEndpoint instance] useSpeaker];
}

RCT_EXPORT_METHOD(useEarpiece: (int) callId callback:(RCTResponseSenderBlock) callback) {
    [[PjSipEndpoint instance] useEarpiece];
}

RCT_EXPORT_METHOD(activateAudioSession: (RCTResponseSenderBlock) callback) {
    pjsua_set_no_snd_dev();
    pj_status_t status;
    status = pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    if (status != PJ_SUCCESS) {
        NSLog(@"Failed to active audio session");
    }
}

RCT_EXPORT_METHOD(deactivateAudioSession: (RCTResponseSenderBlock) callback) {
    pjsua_set_no_snd_dev();
}

#pragma mark - Settings

RCT_EXPORT_METHOD(changeCodecSettings: (NSDictionary*) codecSettings callback:(RCTResponseSenderBlock) callback) {
    [[PjSipEndpoint instance] changeCodecSettings:codecSettings];
    callback(@[@TRUE]);
}

RCT_EXPORT_METHOD(getCodecs: (RCTResponseSenderBlock)callback) {
    NSDictionary *codecs = [[PjSipEndpoint instance] getCodecs];
    callback(@[codecs]);
}

#pragma mark - Utility

RCT_EXPORT_METHOD(logMessage:(NSDictionary *)message callback:(RCTResponseSenderBlock)callback) {
    NSString *type = message[@"type"];
    NSString *content = message[@"content"];
    [PjSipUtil logPjMessage:type content:content];
    callback(@[@YES]);
}

RCT_EXPORT_METHOD(getLogsFilePathUrl:(RCTResponseSenderBlock)callback) {
    NSURL *url = [PjSipUtil getLogFilePathUrl];
    callback(@[url.absoluteString]);
}

RCT_EXPORT_MODULE();

@end
