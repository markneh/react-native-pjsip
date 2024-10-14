#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>

#import "PjSipEndpoint.h"
#import "PjSipAccount.h"
#import "PjSipUtil.h"

@interface PjSipAccountData: NSObject
@property int id;
@property NSString * name;
@property NSString * username;
@property NSString * domain;
@property NSString * password;
@property NSString * proxy;
@property NSString * transport;

@property NSString * contactParams;
@property NSString * contactUriParams;


@property NSString * regServer;
@property NSNumber * regTimeout;
@property NSDictionary * regHeaders;
@property NSString * regContactParams;
@property bool regOnAdd;
@end

@implementation PjSipAccountData

- (id)initWithConfig:(NSDictionary *)config {
    self = [super init];
    
    if (self) {
        self.name = config[@"name"] == nil ? [NSNull null] : config[@"name"];
        self.username = config[@"username"];
        self.domain = config[@"domain"];
        self.password = config[@"password"];
        
        self.proxy = config[@"proxy"] == nil ? [NSNull null] : config[@"proxy"];
        self.transport = config[@"transport"] == nil ? [NSNull null] : config[@"transport"];
        
        self.contactParams = config[@"contactParams"] == nil ? [NSNull null] : config[@"contactParams"];
        self.contactUriParams = config[@"contactUriParams"] == nil ? [NSNull null] : config[@"contactUriParams"];
        
        self.regServer = config[@"regServer"] == nil ? [NSNull null] : config[@"regServer"];
        self.regTimeout = config[@"regTimeout"] == nil ? [NSNumber numberWithInteger:600] : config[@"regTimeout"];
        self.regHeaders = config[@"regHeaders"] == nil ? [NSNull null] : config[@"regHeaders"];
        self.regContactParams = config[@"regContactParams"] == nil ? [NSNull null] : config[@"regContactParams"];
        self.regOnAdd = [config[@"regOnAdd"]  isEqual: @YES] || config[@"regOnAdd"] == nil ? true : false;
    }
    
    return self;
}

- (BOOL)isEqual:(PjSipAccountData *)data {
    
    if (!data || ![data isKindOfClass:[PjSipAccountData class]]) {
        return NO;
    }
    
    BOOL (^safeStringEqual)(NSString *, NSString *) = ^BOOL(NSString *str1, NSString *str2) {
        return (str1 == str2) || (str1 && str2 && [str1 isKindOfClass:[NSString class]] && [str1 isEqualToString:str2]);
    };
    
    BOOL (^safeNumberEqual)(NSNumber *, NSNumber *) = ^BOOL(NSNumber *num1, NSNumber *num2) {
        return (num1 == num2) || (num1 && num2 && [num1 isKindOfClass:[NSNumber class]] && [num1 isEqualToNumber:num2]);
    };
    
    BOOL (^safeDictionaryEqual)(NSDictionary *, NSDictionary *) = ^BOOL(NSDictionary *dict1, NSDictionary *dict2) {
        return (dict1 == dict2) || (dict1 && dict2 && [dict1 isKindOfClass:[NSDictionary class]] && [dict1 isEqualToDictionary:dict2]);
    };
    
    return
    safeStringEqual(self.name, data.name) &&
    safeStringEqual(self.username, data.username) &&
    safeStringEqual(self.domain, data.domain) &&
    safeStringEqual(self.password, data.password) &&
    safeStringEqual(self.proxy, data.proxy) &&
    safeStringEqual(self.transport, data.transport) &&
    safeStringEqual(self.contactParams, data.contactParams) &&
    safeStringEqual(self.contactUriParams, data.contactUriParams) &&
    safeStringEqual(self.regServer, data.regServer) &&
    safeNumberEqual(self.regTimeout, data.regTimeout) &&
    safeDictionaryEqual(self.regHeaders, data.regHeaders) &&
    safeStringEqual(self.regContactParams, data.regContactParams) &&
    self.regOnAdd == data.regOnAdd;
}

- (pjsua_acc_config)pjsuaConfig {
    
    pjsua_acc_config cfg;
    pjsua_acc_config_default(&cfg);
    
    cfg.vid_in_auto_show = PJ_FALSE;
    cfg.vid_out_auto_transmit = PJ_FALSE;
    cfg.ka_interval = 0;
    cfg.use_rfc5626 = PJ_TRUE;
    cfg.allow_sdp_nat_rewrite = PJ_TRUE;
    cfg.sip_stun_use = PJSUA_STUN_RETRY_ON_FAILURE;
    cfg.media_stun_use = PJSUA_STUN_USE_DEFAULT;
    
    // General settings
    {
        NSString *cfgId;
        NSString *cfgURI = [NSString stringWithFormat:@"sip:%@", self.domain];
        
        if (![PjSipUtil isEmptyString:self.name]) {
            cfgId = [NSString stringWithFormat:@"%@ <sip:%@@%@>", self.name, self.username, self.domain];
        } else {
            cfgId = [NSString stringWithFormat:@"<sip:%@@%@>", self.username, self.domain];
        }
        
        cfg.id = pj_str((char *) [cfgId UTF8String]);
        cfg.reg_uri = pj_str((char *) [cfgURI UTF8String]);
        
        pjsip_cred_info cred;
        cred.scheme = pj_str("digest");
        cred.realm = ![PjSipUtil isEmptyString:self.regServer] ? pj_str((char *) [self.regServer UTF8String]) : pj_str("*");
        cred.username = pj_str((char *) [self.username UTF8String]);
        if (self.password.length) {
            cred.data = pj_str((char *) [self.password UTF8String]);
            cred.data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
        }
        
        cfg.cred_count = 1;
        cfg.cred_info[0] = cred;
        
        if (![PjSipUtil isEmptyString:self.contactParams]) {
            cfg.contact_params = pj_str((char *) [self.contactParams UTF8String]);
        }
        if (![PjSipUtil isEmptyString:self.contactUriParams]) {
            cfg.contact_uri_params = pj_str((char *) [self.contactUriParams UTF8String]);
        }
    }
    
    // Registration settings
    {
        if (![self.regHeaders isKindOfClass:[NSNull class]]) {
            pj_list_init(&cfg.reg_hdr_list);
            
            for(NSString* key in self.regHeaders) {
                struct pjsip_generic_string_hdr hdr;
                pj_str_t name = pj_str((char *) [key UTF8String]);
                pj_str_t value = pj_str((char *) [[self.regHeaders objectForKey:key] UTF8String]);
                pjsip_generic_string_hdr_init2(&hdr, &name, &value);
                pj_list_push_back(&cfg.reg_hdr_list, &hdr);
            }
        }
        
        if (![PjSipUtil isEmptyString:self.regContactParams]) {
            cfg.reg_contact_params = pj_str((char *) [self.regContactParams UTF8String]);
        }
        
        if (self.regTimeout != nil && ![self.regTimeout isKindOfClass:[NSNull class]]) {
            cfg.reg_timeout = (unsigned) [self.regTimeout intValue];
        }
        
        cfg.register_on_acc_add = self.regOnAdd;
    }
    
    // Transport settings
    {
        if (![PjSipUtil isEmptyString:self.proxy]) {
            cfg.proxy_cnt = 1;
            cfg.proxy[0] = pj_str((char *) [[NSString stringWithFormat:@"%@", self.proxy] UTF8String]);
        }
        
        cfg.transport_id = [[PjSipEndpoint instance] tcpTransportId];
        
        if (![PjSipUtil isEmptyString:self.transport] && ![self.transport isEqualToString:@"TCP"]) {
            if ([self.transport isEqualToString:@"UDP"]) {
                cfg.transport_id = [[PjSipEndpoint instance] udpTransportId];
            } else if ([self.transport isEqualToString:@"TLS"]) {
                cfg.transport_id = [[PjSipEndpoint instance] tlsTransportId];
            } else {
                NSLog(@"Illegal \"%@\" transport (possible values are UDP, TCP or TLS) use TCP instead", self.transport);
            }
        }
    }
    
    return cfg;
}

- (NSDictionary *)jsonDictionary {
    return @{
        @"name": self.name,
        @"username": self.username,
        @"domain": self.domain,
        @"password": self.password,
        @"proxy": self.proxy,
        @"transport": self.transport,
        @"contactParams": self.contactParams,
        @"contactUriParams": self.contactUriParams,
        @"regServer": self.regServer,
        @"regTimeout": self.regTimeout,
        @"regContactParams": self.regContactParams,
        @"regHeaders": self.regHeaders,
    };
}

@end

@interface PjSipAccount ()
@property (nonatomic, assign) pjsua_acc_id accountId;
@property (nonatomic, strong) PjSipAccountData *data;
@end

@implementation PjSipAccount

+ (instancetype)itemConfig:(NSDictionary *)config status:(pj_status_t *)status {
    return [[self alloc] initWithConfig:config status:status];
}

- (id)initWithConfig:(NSDictionary *)config status:(pj_status_t *)status {
    self = [super init];
    
    if (self) {
        
        self.data = [[PjSipAccountData alloc] initWithConfig:config];
        
        pjsua_acc_id account_id;
        pjsua_acc_config cfg = [self.data pjsuaConfig];
        *status = pjsua_acc_add(&cfg, PJ_TRUE, &account_id);
        
        self.accountId = account_id;
    }
    
    return self;
}

- (BOOL)shouldUpdateWithNewConfig:(NSDictionary *)newConfig {
    PjSipAccountData *newData = [[PjSipAccountData alloc] initWithConfig:newConfig];
    return ![self.data isEqual:newData];
}

- (pj_status_t)updateAccount:(NSDictionary *)newConfig {
    
    PjSipAccountData *data = [[PjSipAccountData alloc] initWithConfig:newConfig];
    
    pj_pool_t *tmp_pool = pjsua_pool_create("tmp-pjsua", 1000, 1000);
    pjsua_acc_config config = [data pjsuaConfig];
    pj_status_t status = pjsua_acc_modify(self.accountId, &config);
    
    if (status == PJ_SUCCESS) {
        self.data = data;
    }
    
    pj_pool_release(tmp_pool);
    
    return status;
}

- (void) dealloc {
    pjsua_acc_set_registration(self.accountId, PJ_FALSE);
    pjsua_acc_del(self.accountId);
}

- (pj_status_t)unregister {
    pj_status_t status = pjsua_acc_set_registration(self.accountId, PJ_FALSE);
    return status;
}

- (pj_status_t)reregister {
    pj_status_t status = pjsua_acc_set_registration(self.accountId, PJ_TRUE);
    return status;
}

- (BOOL)isRegInProgress {
    pjsua_acc_info info;
    pjsua_acc_get_info(self.accountId, &info);
    return info.status == PJSIP_SC_TRYING;
}

- (BOOL)isUnregistered {
    pjsua_acc_info info;
    pjsua_acc_get_info(self.accountId, &info);
    return info.has_registration == PJ_TRUE && info.expires == PJSIP_EXPIRES_NOT_SPECIFIED;
}

- (pj_status_t)lastRegError {
    pjsua_acc_info info;
    pjsua_acc_get_info(self.accountId, &info);
    return info.reg_last_err;
}

- (NSString *)printStatusInfo {
    pjsua_acc_info info;
    pjsua_acc_get_info(self.accountId, &info);
    
    char errmsg[PJ_ERR_MSG_SIZE];
    pj_strerror(info.reg_last_err, errmsg, sizeof(errmsg));
    NSString *regLastError = [NSString stringWithFormat:@"%s", errmsg];
    NSString *statusText = [PjSipUtil toString:&info.status_text];
    NSString *onlineText = [PjSipUtil toString:&info.online_status_text];
    
    return [NSString stringWithFormat:@"[PjSipAccount][printStatusInfo]:\nhas registration: %d\nstatus: %u\nreg last error: %@\nstatus text: %@\nonline: %d\nonline text: %@\nreg_expires: %ul",
            info.has_registration,
            info.status,
            regLastError,
            statusText,
            info.online_status,
            onlineText,
            info.expires
    ];

}

#pragma mark -


- (NSDictionary *)toJsonDictionary {
    pjsua_acc_info info;
    pjsua_acc_get_info(self.accountId, &info);
    
    // Format registration status
    NSDictionary * registration = @{
        @"status": [PjSipUtil toString:(pj_str_t *) pjsip_get_status_text(info.status)],
        @"statusText": [PjSipUtil toString:&info.status_text],
        @"active": @"test",
        @"reason": @"test"
    };
    
    NSMutableDictionary *result = [[self.data jsonDictionary] mutableCopy];
    
    [result addEntriesFromDictionary:@{
        @"id": @(self.accountId),
        @"uri": [PjSipUtil toString:&info.acc_uri],
        @"registration": registration
    }];
    
    return result;
}

@end
