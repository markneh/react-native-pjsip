@import AVFoundation;

#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <pjsua.h>

#import "PjSipUtil.h"
#import "PjSipEndpoint.h"
#import "PjSipMessage.h"

/* Ringtones            US           UK  */
#define RINGBACK_FREQ1        440        /* 400 */
#define RINGBACK_FREQ2        480        /* 450 */
#define RINGBACK_ON        2000    /* 400 */
#define RINGBACK_OFF        4000    /* 200 */
#define RINGBACK_CNT        1        /* 2   */
#define RINGBACK_INTERVAL   4000    /* 2000 */

#define RING_FREQ1        800
#define RING_FREQ2        640
#define RING_ON            200
#define RING_OFF        100
#define RING_CNT        3
#define RING_INTERVAL        3000

static NSString * const PjSipEndpointErrorDomain = @"com.react.native.pjsip";
static NSString * const PjSipEndpointErrorStatusKey = @"pjsip.status.key";

NSString * const PjSipEndpointRegistrationEventName = @"pjSipRegistrationChanged";
NSString * const PjSipEndpointCallReceiveEventName = @"pjSipCallReceived";
NSString * const PjSipEndpointCallChangeEventName = @"pjSipCallChanged";
NSString * const PjSipEndpointCallTerminationEventName = @"pjSipCallTerminated";
NSString * const PjSipEndpointMessageReceiveEventName = @"pjSipMessageReceived";
NSString * const PjSipEndpointLogEventName = @"pjSipLogReceived";
NSString * const PjSipEndpointLaunchStatusEventName = @"pjSipLaunchStatusUpdated";

typedef NS_ENUM(NSInteger, PjSipEndpointErrorCode) {
    PjSipEndpointAlreadyLaunchedError = 1001,
    PjSipEndpointCreateError = 1002,
    PjSipEndpointRegModuleError = 1003,
    PjSipEndpointInitError = 1004,
    PjSipEndpointToneGenCreateError = 1005,
    PjSipEndpointToneGenAddPortError = 1006,
    PjSipEndpointUDPCreateError = 1007,
    PjSipEndpointStartError = 1008,
    PjSipEndpointAudioActivateError = 1009,
    PjSipEndpointAudioDeactivateError = 1010
};

static pj_status_t on_tx_response(pjsip_tx_data *tdata)
{
    NSString *method = [PjSipUtil toString:&tdata->msg->line.req.method.name];

    if ([[method lowercaseString] isEqualToString:@"ok"]) {
        pjsip_msg_find_remove_hdr(tdata->msg, PJSIP_H_ALLOW, NULL);
        pjsip_msg_find_remove_hdr(tdata->msg, PJSIP_H_SUPPORTED, NULL);
        pjsip_msg_find_remove_hdr(tdata->msg, PJSIP_H_REQUIRE, NULL);

        // Get the User-Agent header
        const pj_str_t sess_exp_name = pj_str([@"Session-Expires" cStringUsingEncoding:NSUTF8StringEncoding]);

        pjsip_generic_string_hdr *session_exp_header = (pjsip_generic_string_hdr *)
        pjsip_msg_find_hdr_by_name(tdata->msg,
                                   &sess_exp_name,
                                   NULL);

        // Remove the User-Agent header
        if (session_exp_header != NULL) {
            pj_list_erase(session_exp_header);
        }
    }

    if ([[method lowercaseString] isEqualToString:@"ringing"]) {
        pjsip_msg_find_remove_hdr(tdata->msg, PJSIP_H_ALLOW, NULL);
    }

    return PJ_SUCCESS;
}


/* The module instance. */
static pjsip_module mod_default_handler =
{
    NULL, NULL,                /* prev, next.        */
    { "mod-default-handler", 19 },    /* Name.        */
    -1,                    /* Id            */
    PJSIP_MOD_PRIORITY_APPLICATION+99,    /* Priority            */
    NULL,                /* load()        */
    NULL,                /* start()        */
    NULL,                /* stop()        */
    NULL,                /* unload()        */
    NULL,                /* on_rx_request()    */
    NULL,                /* on_rx_response()    */
    NULL,                /* on_tx_request.    */
    &on_tx_response,                /* on_tx_response()    */
    NULL,                /* on_tsx_state()    */

};

@interface PjSipEndpoint()
@property (nonatomic, strong) NSDictionary *lastRegInfo;
@end

@implementation PjSipEndpoint

pj_bool_t ringback_on;
int ringback_slot;
pjsua_conf_port_id dtmf_port_id;
pjmedia_port *ringback_port;
pjmedia_port *dtmf_port;
pj_pool_t *pool;

+ (instancetype) instance {
    return [self instanceWithConfig:nil];
}

+ (instancetype) instanceWithConfig:(NSDictionary *)config {
    static PjSipEndpoint *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PjSipEndpoint alloc] initWithConfig:config];
    });

    return sharedInstance;
}

- (instancetype) initWithConfig:(NSDictionary *)config {
    self = [super init];
    return self;
}

- (void)dealloc {
    pj_pool_release(pool);
}

- (BOOL)startWithConfig:(NSDictionary *)config error:(NSError **)startError {

    pjsua_state state = pjsua_get_state();
    if (state != PJSUA_STATE_NULL) {
        *startError = [NSError errorWithDomain:PjSipEndpointErrorDomain
                                          code:PjSipEndpointAlreadyLaunchedError
                                     userInfo:nil];
        return FALSE;
    }

    BOOL success = [self performStartWithConfig:config error:startError];

    [self emmitLaunchStatusUpdate:success];

    return success;
}

- (BOOL)performStartWithConfig:(NSDictionary *)config error:(NSError **)startError {

    self.accounts = [[NSMutableDictionary alloc] initWithCapacity:12];
    self.calls = [[NSMutableDictionary alloc] initWithCapacity:12];

    pj_status_t status;

    // Create pjsua first
    status = pjsua_create();
    if (status != PJ_SUCCESS) {
        [self logStatus:status];
        *startError = [self errorFromStatus:status code:PjSipEndpointCreateError];
        return false;
    }

    status = pjsip_endpt_register_module(pjsua_get_pjsip_endpt(), &mod_default_handler);
    if (status != PJ_SUCCESS) {
        [self logStatus:status];
        *startError = [self errorFromStatus:status code:PjSipEndpointRegModuleError];
        return false;
    }

    [PjSipUtil clearLogsFile];

    // Init pjsua
    {
        // Init the config structure
        pjsua_config cfg;
        pjsua_config_default(&cfg);

        // cfg.cb.on_reg_state = [self performSelector:@selector(onRegState:) withObject: o];
        cfg.cb.on_reg_state = &onRegStateTest;
        cfg.cb.on_reg_state2 = &onRegStateChanged;
        cfg.cb.on_reg_started2 = &onRegStarted;
        cfg.cb.on_incoming_call = &onCallReceived;
        cfg.cb.on_call_state = &onCallStateChanged;
        cfg.cb.on_call_media_state = &onCallMediaStateChanged;

        cfg.cb.on_pager2 = &onMessageReceived;

        NSString *ua = config[@"service"][@"ua"];
        if (ua && ua.length > 0) {
            char *uaAsCstring = (char *)[ua cStringUsingEncoding:NSUTF8StringEncoding];
            cfg.user_agent =  pj_str(uaAsCstring);
        }


        // Init the logging config structure
        pjsua_logging_config log_cfg;
        pjsua_logging_config_default(&log_cfg);
        log_cfg.level = 5;
        log_cfg.console_level = 4;
        log_cfg.cb = &onLog;

        // Init media config
        pjsua_media_config mediaConfig;
        pjsua_media_config_default(&mediaConfig);
        mediaConfig.clock_rate = PJSUA_DEFAULT_CLOCK_RATE;
        mediaConfig.snd_clock_rate = 0;

        // Init the pjsua
        status = pjsua_init(&cfg, &log_cfg, &mediaConfig);
        if (status != PJ_SUCCESS) {
            [self logStatus:status];
            *startError = [self errorFromStatus:status code:PjSipEndpointInitError];
            return FALSE;
        }

        // init ringback tone
        unsigned samples_per_frame;
        pjmedia_tone_desc tone[RING_CNT+RINGBACK_CNT];
        pj_str_t name;

        samples_per_frame = mediaConfig.audio_frame_ptime * mediaConfig.clock_rate * mediaConfig.channel_count / 1000;

        /* Ringback tone (call is ringing) */
        name = pj_str("ringback");
        pool = pjsua_pool_create("tmp-pjsua", 1000, 1000);

        status = pjmedia_tonegen_create2(pool, &name,
                         mediaConfig.clock_rate,
                         mediaConfig.channel_count,
                         samples_per_frame,
                         16, PJMEDIA_TONEGEN_LOOP,
                         &ringback_port);

        if (status != PJ_SUCCESS) {
            [self logStatus:status];
            *startError = [self errorFromStatus:status code:PjSipEndpointToneGenCreateError];
            return NO;
        }

        pj_bzero(&tone, sizeof(tone));
        for (unsigned i=0; i<RINGBACK_CNT; ++i) {
            tone[i].freq1 = RINGBACK_FREQ1;
            tone[i].freq2 = RINGBACK_FREQ2;
            tone[i].on_msec = RINGBACK_ON;
            tone[i].off_msec = RINGBACK_OFF;
        }
        tone[RINGBACK_CNT-1].off_msec = RINGBACK_INTERVAL;

        pjmedia_tonegen_play(ringback_port, RINGBACK_CNT, tone, PJMEDIA_TONEGEN_LOOP);

        status = pjsua_conf_add_port(pool, ringback_port, &ringback_slot);

        if (status != PJ_SUCCESS) {
            [self logStatus:status];
            *startError = [self errorFromStatus:status code:PjSipEndpointToneGenAddPortError];
            return NO;
        }

    }

    // Add UDP transport.
    {
        // Init transport config structure
        pjsua_transport_config cfg;
        pjsua_transport_config_default(&cfg);
        pjsua_transport_id id;

        // Add TCP transport.
        status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &cfg, &id);

        if (status != PJ_SUCCESS) {
            [self logStatus:status];
            *startError = [self errorFromStatus:status code:PjSipEndpointUDPCreateError];
            return NO;
        } else {
            self.udpTransportId = id;
        }
    }

//    // Add TCP transport.
//    {
//        pjsua_transport_config cfg;
//        pjsua_transport_config_default(&cfg);
//        pjsua_transport_id id;
//
//        status = pjsua_transport_create(PJSIP_TRANSPORT_TCP, &cfg, &id);
//
//        if (status != PJ_SUCCESS) {
//            NSLog(@"Error creating TCP transport");
//        } else {
//            self.tcpTransportId = id;
//        }
//    }
//
//    // Add TLS transport.
//    {
//        pjsua_transport_config cfg;
//        pjsua_transport_config_default(&cfg);
//        pjsua_transport_id id;
//
//        status = pjsua_transport_create(PJSIP_TRANSPORT_TLS, &cfg, &id);
//
//        if (status != PJ_SUCCESS) {
//            NSLog(@"Error creating TLS transport");
//        } else {
//            self.tlsTransportId = id;
//        }
//    }

    // Initialization is done, now start pjsua
    status = pjsua_start();
    if (status != PJ_SUCCESS) {
        [self logStatus:status];
        *startError = [self errorFromStatus:status code:PjSipEndpointStartError];
        return FALSE;
    }

    return TRUE;
}

- (BOOL)relaunchUDPConnection {
    if (!self.isStarted) {
        return FALSE;
    }

    pj_status_t status = [self recreateUDPTransport];
    return status == PJ_SUCCESS;
}

- (pj_status_t)recreateUDPTransport {

    pjsua_transport_id id = [self getIdOfFirstTransportIfPossible];

    if (id == -1) {
        return PJ_SUCCESS + 1; // pj_fail is 0 and pj_success is also 0
    }

    pj_status_t status = pjsua_transport_close(id, PJ_FALSE);
    if (status != PJ_SUCCESS) {
        [self logStatus:status];
        return status;
    }

    status = [self launchUDPTransport];

    return status;
}

- (pjsua_transport_id)getIdOfFirstTransportIfPossible {
    pjsua_transport_id ids[PJSIP_MAX_TRANSPORTS];
    unsigned int count = PJ_ARRAY_SIZE(ids);
    pj_status_t status = pjsua_enum_transports(ids, &count);

    if (status != PJ_SUCCESS) {
        [self logStatus:status];
        return -1;
    }

    if (count == 0) {
        return -1;
    }

    pjsua_transport_id id = ids[0];
    pjsua_transport_info info;
    status = pjsua_transport_get_info(id, &info);
    if (status != PJ_SUCCESS) {
        [self logStatus:status];
        return -1;
    }

    return id;
}

- (pj_status_t)launchUDPTransport {
    pjsua_transport_config cfg;
    pjsua_transport_config_default(&cfg);
    pjsua_transport_id id;

    pj_status_t status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &cfg, &id);

    if (status != PJ_SUCCESS) {
        [self logStatus:status];
    } else {
        self.udpTransportId = id;
    }

    return status;
}

- (void)logStatus:(pj_status_t)status {
    NSString *errorMessage = [self errorMessageFromStatus:status];
    [self emmitLogMessage:errorMessage];
}

- (NSError *)errorFromStatus:(pj_status_t)status code:(NSInteger)errorCode {
    return [self errorFromStatus:status code:errorCode userInfo:nil];
}

- (NSError *)errorFromStatus:(pj_status_t)status code:(NSInteger)errorCode userInfo:(NSDictionary *)providedUserInfo {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    userInfo[PjSipEndpointErrorStatusKey] = [self errorMessageFromStatus:status];
    
    if (providedUserInfo) {
        [userInfo addEntriesFromDictionary:providedUserInfo];
    }
    
    return [NSError errorWithDomain:PjSipEndpointErrorDomain code:errorCode userInfo:userInfo]; }

- (NSString *)errorMessageFromStatus:(pj_status_t)status {
    char errmsg[PJ_ERR_MSG_SIZE];
    pj_strerror(status, errmsg, sizeof(errmsg));
    NSString *message = [NSString stringWithFormat:@"%s", errmsg];
    return message;
}

- (NSDictionary *)getInitialState:(NSDictionary *)config {
    NSMutableArray *accountsResult = [[NSMutableArray alloc] initWithCapacity:[@([self.accounts count]) unsignedIntegerValue]];
    NSMutableArray *callsResult = [[NSMutableArray alloc] initWithCapacity:[@([self.calls count]) unsignedIntegerValue]];
    NSDictionary *settingsResult = @{ @"codecs": [self getCodecs] };

    for (NSString *key in self.accounts) {
        PjSipAccount *acc = self.accounts[key];
        [accountsResult addObject:[acc toJsonDictionary]];
    }

    for (NSString *key in self.calls) {
        PjSipCall *call = self.calls[key];
        [callsResult addObject:[call toJsonDictionary:self.isSpeaker]];
    }

    if ([accountsResult count] > 0 && config[@"service"] && config[@"service"][@"stun"]) {
        for (NSDictionary *account in accountsResult) {
            int accountId = account[@"_data"][@"id"];
            [[PjSipEndpoint instance] updateStunServers:accountId stunServerList:config[@"service"][@"stun"]];
        }
    }
    
    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
    
    info[@"accounts"] = accountsResult;
    info[@"calls"] = callsResult;
    info[@"settings"] = settingsResult;
    info[@"connectivity"] = @YES;
    
    if (self.lastRegInfo) {
        info[@"regInfo"] = self.lastRegInfo;
    }
    
    return info;
}

- (BOOL)isStarted {
    return pjsua_get_state() == PJSUA_STATE_RUNNING;
}

- (BOOL)stop {

    if (!self.isStarted) {
        return FALSE;
    }
    
    // cleanup before destroying
    self.accounts = [[NSMutableDictionary alloc] init];
    self.calls = [[NSMutableDictionary alloc] init];
    
    pj_status_t status = pjsua_destroy2(PJSUA_DESTROY_NO_RX_MSG);

    BOOL success = status == PJ_SUCCESS;
    
    if (success) {
        self.lastRegInfo = nil;
        [self emmitLaunchStatusUpdate:false];
    }

    return success;
}

- (void)updateStunServers:(int)accountId stunServerList:(NSArray *)stunServerList {
    int size = [stunServerList count];
    int count = 0;
    pj_str_t srv[size];
    for (NSString *stunServer in stunServerList) {
        srv[count] = pj_str([stunServer UTF8String]);
        count++;
    }

    pjsua_acc_config cfg_update;
    pj_pool_t *pool = pjsua_pool_create("tmp-pjsua", 1000, 1000);
    pjsua_acc_config_default(&cfg_update);
    pjsua_acc_get_config(accountId, pool, &cfg_update);
    pjsua_update_stun_servers(size, srv, false);

    pjsua_acc_modify(accountId, &cfg_update);
}

- (PjSipAccount *)createAccount:(NSDictionary *)config {
    PjSipAccount *account = [PjSipAccount itemConfig:config];
    self.accounts[@(account.id)] = account;

    return account;
}

- (void)deleteAccount:(int) accountId {
    // TODO: Destroy function ?
    if (self.accounts[@(accountId)] == nil) {
        [NSException raise:@"Failed to delete account" format:@"Account with %@ id not found", @(accountId)];
    }

    [self.accounts removeObjectForKey:@(accountId)];
}

- (PjSipAccount *) findAccount: (int) accountId {
    return self.accounts[@(accountId)];
}

- (void)playDTMFDigitsAudioFeedback:(NSString *)digitsString {
    char *digits = (char *)[digitsString cStringUsingEncoding:NSUTF8StringEncoding];
    
    [self initDTMFIfNeeded];
   
    pjmedia_tone_digit d[1];
    d[0].digit = digits[0];
    d[0].on_msec = 100;
    d[0].off_msec = 500;
    d[0].volume = 0;
    
    pjmedia_tonegen_play_digits(dtmf_port, 1, d, 0);
}

- (BOOL)activateAudioSessionWithError:(NSError *__autoreleasing *)error {
    pjsua_set_no_snd_dev();
    pj_status_t status;
    status = pjsua_set_snd_dev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV, PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    
    if (status != PJ_SUCCESS) {
        *error = [self errorFromStatus:status code:PjSipEndpointAudioActivateError];
        [self logStatus:status];
    }
    
    pjsua_call_info call_info;
    pjsua_call_id ids[PJSUA_MAX_CALLS];
    unsigned count = PJSUA_MAX_CALLS;
    
    pjsua_enum_calls(ids, &count);
    for (unsigned i = 0; i < count; i++) {
        pjsua_call_get_info(i, &call_info);
        
        for (unsigned mi = 0; mi < call_info.media_cnt; ++mi) {
            if (call_info.media[mi].type == PJMEDIA_TYPE_AUDIO &&
                (call_info.media[mi].status == PJSUA_CALL_MEDIA_ACTIVE ||
                 call_info.media[mi].status == PJSUA_CALL_MEDIA_REMOTE_HOLD))
            {
                pjsua_conf_port_id call_conf_slot;
                call_conf_slot = call_info.media[mi].stream.aud.conf_slot;
                pjsua_conf_connect(0, call_conf_slot);
                pjsua_conf_connect(call_conf_slot, 0);
            }
        }
    }
    
    return status == PJ_SUCCESS;
}

- (BOOL)deactivateAudioSessionWithError:(NSError *__autoreleasing *)error {
    @try {
        pjsua_set_no_snd_dev();
        return YES;
    } @catch (NSException *exception) {
        *error = [self errorFromStatus:PJ_FALSE code:PjSipEndpointAudioDeactivateError userInfo:@{ @"exception" : exception }];
        return NO;
    }
}

- (BOOL)initDTMFIfNeeded {
    
    if (!dtmf_port) {
        // create dtmf tonegen
        pj_status_t status = pjmedia_tonegen_create(pool, 8000, 1, 160, 16, 0, &dtmf_port);
        if (status != PJ_SUCCESS) {
            [self logStatus:status];
            return NO;
        }
            
        // add dtmf port
        status = pjsua_conf_add_port(pool, dtmf_port, &dtmf_port_id);
        if (status != PJ_SUCCESS) {
            [self logStatus:status]; // not critical
            return NO;
        }
    }
    
    if (dtmf_port_id != PJSUA_INVALID_ID) {
        pjsua_conf_connect(dtmf_port_id, 0);
    }
    
    return YES;
}

- (void)deinitDTMFTonegenIfNeeded {
    if (dtmf_port_id) {
        pjsua_conf_remove_port(dtmf_port_id);
    }
    if (dtmf_port) {
        pjmedia_port_destroy(dtmf_port);
        dtmf_port = NULL;
    }
}

#pragma mark Calls

-(PjSipCall *) makeCall:(PjSipAccount *) account destination:(NSString *)destination callSettings: (NSDictionary *)callSettingsDict msgData: (NSDictionary *)msgDataDict {
    pjsua_call_setting callSettings;
    [PjSipUtil fillCallSettings:&callSettings dict:callSettingsDict];

    pj_caching_pool cp;
    pj_pool_t *pool;

    pj_caching_pool_init(&cp, &pj_pool_factory_default_policy, 0);
    pool = pj_pool_create(&cp.factory, "header", 1000, 1000, NULL);

    pjsua_msg_data msgData;
    pjsua_msg_data_init(&msgData);
    [PjSipUtil fillMsgData:&msgData dict:msgDataDict pool:pool];


    pjsua_call_id callId;
    pj_str_t callDest = pj_str((char *) [destination UTF8String]);

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    
    NSError *activationError;
    [[AVAudioSession sharedInstance] setActive:YES error:&activationError];
    
    if (activationError) {
        [NSException raise:@"Failed to make a call" format:@"Error while trying to activate AVAudioSession: %@", activationError];
    }

    pj_status_t status = pjsua_call_make_call(account.id, &callDest, &callSettings, NULL, &msgData, &callId);

    if (status != PJ_SUCCESS) {
        [NSException raise:@"Failed to make a call" format:@"See device logs for more details."];
    }
    pj_pool_release(pool);

    PjSipCall *call = [self createCallIfNeeded:callId];

    return call;
}

- (PjSipCall *) findCall: (int) callId {
    return self.calls[@(callId)];
}

- (PjSipCall *)createCallIfNeeded: (int) callId {
    PjSipCall *call = self.calls[@(callId)];
    if (!call) {
        call = [PjSipCall itemConfig:callId];
        self.calls[@(callId)] = call;
    }

    return call;
}

-(void) pauseParallelCalls:(PjSipCall*) call {
    for(id key in self.calls) {
        if (key != call.id) {
            for (NSString *key in self.calls) {
                PjSipCall *parallelCall = self.calls[key];

                if (call.id != parallelCall.id && !parallelCall.isHeld) {
                    [parallelCall hold];
                    [self emmitCallChanged:parallelCall];
                }
            }
        }
    }
}

-(void)useSpeaker {
    self.isSpeaker = true;

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];

    for (NSString *key in self.calls) {
        PjSipCall *call = self.calls[key];
        [self emmitCallChanged:call];
    }
}

-(void)useEarpiece {
    self.isSpeaker = false;

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];

    for (NSString *key in self.calls) {
        PjSipCall *call = self.calls[key];
        [self emmitCallChanged:call];
    }
}

- (void)resetSpeaker {
    self.isSpeaker = NO;
}

#pragma mark - Settings

-(void) changeCodecSettings: (NSDictionary*) codecSettings {

    for (NSString * key in codecSettings) {
        pj_str_t codec_id = pj_str((char *) [key UTF8String]);
        NSNumber * priority = codecSettings[key];
        pj_uint8_t convertedPriority = [priority integerValue];
        pjsua_codec_set_priority(&codec_id, convertedPriority);
    }
}

- (NSMutableDictionary *) getCodecs {
    //32 max possible codecs
    pjsua_codec_info codec[32];
    NSMutableDictionary *codecs = [[NSMutableDictionary alloc] initWithCapacity:32];
    unsigned uCount = 32;
    
    if (codecs.allKeys.count == 0) {
        return codecs;
    }

    if (pjsua_enum_codecs(codec, &uCount) == PJ_SUCCESS) {
        for (unsigned i = 0; i < uCount; ++i) {
            NSString * codecName = [NSString stringWithFormat:@"%s", codec[i].codec_id.ptr];
            [codecs setObject:[NSNumber numberWithInt: codec[i].priority] forKey: codecName];
        }
    }
    return codecs;
}


#pragma mark - Events

-(void)emmitRegistrationChanged:(PjSipAccount*) account  regInfo:(NSDictionary *)regInfo {
    NSMutableDictionary *body = [[NSMutableDictionary alloc] init];
    body[@"account"] = [account toJsonDictionary];
    body[@"regInfo"] = regInfo;
    
    self.lastRegInfo = regInfo;

    [self emmitEvent:PjSipEndpointRegistrationEventName body:body];
}

-(void)emmitCallReceived:(PjSipCall*) call {
    [self emmitEvent:PjSipEndpointCallReceiveEventName body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitCallChanged:(PjSipCall*) call {
    [self emmitEvent:PjSipEndpointCallChangeEventName body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitCallTerminated:(PjSipCall*) call {
    [self emmitEvent:PjSipEndpointCallTerminationEventName body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitMessageReceived:(PjSipMessage*) message {
    [self emmitEvent:PjSipEndpointMessageReceiveEventName body:[message toJsonDictionary]];
}

-(void)emmitLogMessage:(NSString *)message {
    [self emmitEvent:PjSipEndpointLogEventName body:message];
}

-(void)emmitLaunchStatusUpdate:(BOOL)isLaunched {
    [self emmitEvent:PjSipEndpointLaunchStatusEventName body:@{@"isLaunched":@(isLaunched)}];
}

-(void)emmitEvent:(NSString*) name body:(id)body {
    if (self.bridge) {
        [[self.bridge eventDispatcher] sendAppEventWithName:name body:body];
    }
    if (self.sipEventCallback) {
        self.sipEventCallback(name, body);
    }
}

#pragma mark - Callbacks

static void onRegStarted(pjsua_acc_id acc_id, pjsua_reg_info *info) {

}

static void onRegStateTest(pjsua_acc_id acc_id) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    PjSipAccount* account = [endpoint findAccount:acc_id];

}

static void onRegStateChanged(pjsua_acc_id acc_id, pjsua_reg_info *info) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    PjSipAccount* account = [endpoint findAccount:acc_id];
    NSDictionary *regInfo = [PjSipUtil mapRegInfo:info];

    if (account) {
        [endpoint emmitRegistrationChanged:account regInfo:regInfo];
    }
}

static void onCallReceived(pjsua_acc_id accId, pjsua_call_id callId, pjsip_rx_data *rx) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];

    PjSipCall *call = [PjSipCall itemConfig:callId];
    endpoint.calls[@(callId)] = call;

    pjsip_msg *messageInfo = rx->msg_info.msg;

    pjsip_hdr *hdr ;
    for (hdr = messageInfo->hdr.next ; hdr != &messageInfo->hdr ; hdr = hdr->next) {
        NSString *name = [PjSipUtil toString:&hdr->name]; //X-UUID

        if ([[name lowercaseString] isEqualToString:[@"X-UUID" lowercaseString]]) {
            /* write header value to buffer */
            char value[ 512 ] = { 0 };
            hdr->vptr->print_on( hdr, value, 512 );

            NSString *fullHeader = [NSString stringWithCString:value encoding:NSUTF8StringEncoding];
            NSString *stringToRemove = [NSString stringWithFormat:@"%@: ", name];
            NSString *xCallId = [fullHeader stringByReplacingOccurrencesOfString:stringToRemove withString:@""];
            call.xCallId = xCallId;
        }
    }

    [endpoint emmitCallReceived:call];

    [call reportRinging];
}

static void onCallStateChanged(pjsua_call_id callId, pjsip_event *event) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];

    pjsua_call_info callInfo;
    pjsua_call_get_info(callId, &callInfo);

    PjSipCall* call = [endpoint findCall:callId];

    if (!call && callInfo.state == PJSIP_INV_STATE_CALLING) {
        call = [endpoint createCallIfNeeded:callId];
    } else if (!call) {
        return;
    }

    [call onStateChanged:callInfo];

    ring_stop();

    if (callInfo.state == PJSIP_INV_STATE_CALLING) {
        ringback_start();
    }

    if (callInfo.state == PJSIP_INV_STATE_EARLY) {
        pjsip_msg *msg;

        if (event->body.tsx_state.type == PJSIP_EVENT_RX_MSG) {
            msg = event->body.tsx_state.src.rdata->msg_info.msg;
        } else {
            msg = event->body.tsx_state.src.tdata->msg;
        }

        int code = msg->line.status.code;

        if (callInfo.role == PJSIP_ROLE_UAC && code == 180 && msg->body == NULL && callInfo.media_status == PJSUA_CALL_MEDIA_NONE) {
            ringback_start();
        }
    }

    if (callInfo.state == PJSIP_INV_STATE_DISCONNECTED) {
        [endpoint.calls removeObjectForKey:@(callId)];
        [endpoint emmitCallTerminated:call];
        [endpoint resetSpeaker]; // this might be triggered if there's another incoming call which is automatically declined
        [endpoint deinitDTMFTonegenIfNeeded];
    } else {
        [endpoint emmitCallChanged:call];
    }
}

static void onCallMediaStateChanged(pjsua_call_id callId) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];

    ring_stop();

    pjsua_call_info callInfo;
    pjsua_call_get_info(callId, &callInfo);

    PjSipCall* call = [endpoint findCall:callId];

    if (call) {
        [call onMediaStateChanged:callInfo];
    }

    [endpoint emmitCallChanged:call];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"PjSipInvalidateVideo"
                                                        object:nil];
}

static void onMessageReceived(pjsua_call_id call_id, const pj_str_t *from,
                          const pj_str_t *to, const pj_str_t *contact,
                          const pj_str_t *mime_type, const pj_str_t *body,
                          pjsip_rx_data *rdata, pjsua_acc_id acc_id) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    NSDictionary* data = [NSDictionary dictionaryWithObjectsAndKeys:
                          [NSNull null], @"test",
                          @(call_id), @"callId",
                          @(acc_id), @"accountId",
                          [PjSipUtil toString:contact], @"contactUri",
                          [PjSipUtil toString:from], @"fromUri",
                          [PjSipUtil toString:to], @"toUri",
                          [PjSipUtil toString:body], @"body",
                          [PjSipUtil toString:mime_type], @"contentType",
                          nil];
    PjSipMessage* message = [PjSipMessage itemConfig:data];

    [endpoint emmitMessageReceived:message];
}

static void onLog(int level, const char *data, int len) {
    NSString *message = [NSString stringWithCString:data encoding:NSUTF8StringEncoding];
    if (message && message.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[PjSipEndpoint instance] emmitLogMessage:message];
            [PjSipUtil appendLogMessage:message];
        });
    }
}


static void ringback_start(void)
{
    if (ringback_on) {
        return;
    }

    ringback_on = PJ_TRUE;

    if (ringback_slot != PJSUA_INVALID_ID) {
        pjsua_conf_connect(ringback_slot, 0);
    }
}

static void ring_stop(void)
{
    if (ringback_on) {

        ringback_on = PJ_FALSE;

        if (ringback_slot!=PJSUA_INVALID_ID) {
            pjsua_conf_disconnect(ringback_slot, 0);
            pjmedia_tonegen_rewind(ringback_port);
        }
    }
}

@end
