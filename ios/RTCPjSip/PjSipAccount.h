#import <React/RCTUtils.h>

#import "PjSipCall.h"

@interface PjSipAccount : NSObject

+ (instancetype)itemConfig:(NSDictionary *)config status:(pj_status_t *)status;

- (BOOL)shouldUpdateWithNewConfig:(NSDictionary *)newConfig;
- (BOOL)isRegInProgress;

- (pj_status_t)updateAccount:(NSDictionary *)newConfig;
    
- (pjsua_acc_id)accountId;
- (NSDictionary *)toJsonDictionary;

- (NSString *)printStatusInfo;

- (pj_status_t)unregister;
- (pj_status_t)reregister;

- (BOOL)isUnregistered;
- (pj_status_t)lastRegError;


@end
