@import AVFoundation;

#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <VialerPJSIP/pjsua.h>

#import "PjSipUtil.h"
#import "PjSipEndpoint.h"
#import "PjSipMessage.h"

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

@property (nonatomic, assign, readwrite) BOOL isStarted;

@end

@implementation PjSipEndpoint

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


- (BOOL)startWithConfig:(NSDictionary *)config {

    if (self.isStarted) {
        return FALSE;
    }

    BOOL success = [self performStartWithConfig:config];

    self.isStarted = success;

    return success;
}

- (BOOL)performStartWithConfig:(NSDictionary *)config {

    self.accounts = [[NSMutableDictionary alloc] initWithCapacity:12];
    self.calls = [[NSMutableDictionary alloc] initWithCapacity:12];

    pj_status_t status;

    // Create pjsua first
    status = pjsua_create();
    if (status != PJ_SUCCESS) {
        NSLog(@"Error in pjsua_create()");
        return false;
    }

    status = pjsip_endpt_register_module(pjsua_get_pjsip_endpt(), &mod_default_handler);
    if (status != PJ_SUCCESS) {
        NSLog(@"Error registering module");
        return false;
    }

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
            NSLog(@"Error in pjsua_init()");
            return FALSE;
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
            NSLog(@"Error creating UDP transport");
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
        NSLog(@"Error starting pjsua");
        return FALSE;
    }

    return TRUE;
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

    return @{@"accounts": accountsResult, @"calls": callsResult, @"settings": settingsResult, @"connectivity": @YES};
}

- (BOOL)stop {

    if (!self.isStarted) {
        return FALSE;
    }

    pj_status_t status = pjsua_destroy2(PJSUA_DESTROY_NO_RX_MSG);

    BOOL success = status == PJ_SUCCESS;

    self.isStarted = success;

    return success;
}

- (void)setIsStarted:(BOOL)isStarted {
    _isStarted = isStarted;
    [self emmitLaunchStatusUpdate:isStarted];
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
    NSLog([NSString stringWithFormat: @"I AM ACC ID: %d", accountId]);
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

    [self emmitEvent:@"pjSipRegistrationChanged" body:body];
}

-(void)emmitCallReceived:(PjSipCall*) call {
    [self emmitEvent:@"pjSipCallReceived" body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitCallChanged:(PjSipCall*) call {
    [self emmitEvent:@"pjSipCallChanged" body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitCallTerminated:(PjSipCall*) call {
    [self emmitEvent:@"pjSipCallTerminated" body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitMessageReceived:(PjSipMessage*) message {
    [self emmitEvent:@"pjSipMessageReceived" body:[message toJsonDictionary]];
}

-(void)emmitLogMessage:(NSString *)message {
    [self emmitEvent:@"pjSipLogReceived" body:message];
}

-(void)emmitLaunchStatusUpdate:(BOOL)isLaunched {
    [self emmitEvent:@"pjSipLaunchStatusUpdated" body:@{@"isLaunched":@(isLaunched)}];
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

    if (callInfo.state == PJSIP_INV_STATE_DISCONNECTED) {
        [endpoint.calls removeObjectForKey:@(callId)];
        [endpoint emmitCallTerminated:call];
    } else {
        [endpoint emmitCallChanged:call];
    }
}

static void onCallMediaStateChanged(pjsua_call_id callId) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];

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
        });
    }
}

@end
