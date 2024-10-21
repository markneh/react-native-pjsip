#import <React/RCTBridgeModule.h>

#import "PjSipAccount.h"
#import "PjSipCall.h"

typedef void (^SIPEventCallback)(NSString *name, id metadata);

typedef NS_ENUM(NSUInteger, PjSipEndpointLogType) {
    PjSipEndpointLogTypeVerbose,
    PjSipEndpointLogTypeDebug,
    PjSipEndpointLogTypeInfo,
    PjSipEndpointLogTypeWarning,
    PjSipEndpointLogTypeError,
};

extern NSString * const PjSipEndpointRegistrationEventName;
extern NSString * const PjSipEndpointCallReceiveEventName;
extern NSString * const PjSipEndpointCallChangeEventName;
extern NSString * const PjSipEndpointCallTerminationEventName;
extern NSString * const PjSipEndpointMessageReceiveEventName;
extern NSString * const PjSipEndpointLogEventName;
extern NSString * const PjSipEndpointLaunchStatusEventName;

extern NSString * const PjSipEndpointLogEventTypeKey;
extern NSString * const PjSipEndpointLogEventMessageKey;

@interface PjSipEndpoint : NSObject

@property (nonatomic, assign, readonly) BOOL isStarted;
@property (nonatomic, strong) SIPEventCallback sipEventCallback;

@property NSMutableDictionary* calls;
@property(nonatomic, strong) RCTBridge *bridge;

@property pjsua_transport_id tcpTransportId;
@property pjsua_transport_id udpTransportId;
@property pjsua_transport_id tlsTransportId;

@property bool isSpeaker;

+(instancetype)instance;
+(instancetype)instanceWithConfig:(NSDictionary *)config;

-(BOOL)startWithConfig:(NSDictionary *)config error:(NSError **)startError;
-(NSDictionary *)getInitialState: (NSDictionary *)config;
-(BOOL)stop;

-(void) updateStunServers: (int) accountId stunServerList:(NSArray *)stunServerList;

- (void)setAccountCreds:(NSDictionary *)config;
- (void)scheduleExistingAccountUnregisterWithCompletion:(void (^)(void))completion;
- (void)registerExistingAccountIfNeeded;
- (void)unregisterExistingAccountIfNeeded;
- (void)cancelScheduledAccountUnregister;
- (PjSipAccount *)getCurrentAccount;

-(PjSipCall *)makeCallToDestination:(NSString *)destination callSettings: (NSDictionary *)callSettings msgData: (NSDictionary *)msgData;
-(void)pauseParallelCalls:(PjSipCall*) call; // TODO: Remove this feature.
-(PjSipCall *)findCall:(int)callId;
-(void)useSpeaker;
-(void)useEarpiece;

-(void)changeCodecSettings: (NSDictionary*) codecSettings;
-(NSDictionary *)getCodecs;

-(void)emmitRegistrationChanged:(PjSipAccount*) account regInfo:(NSDictionary *)regInfo;
-(void)emmitCallReceived:(PjSipCall*) call;
-(void)emmitCallUpdated:(PjSipCall*) call;
-(void)emmitCallChanged:(PjSipCall*) call;
-(void)emmitCallTerminated:(PjSipCall*) call;

- (BOOL)relaunchUDPConnection;

-(void)playDTMFDigitsAudioFeedback:(NSString *)digitsString;
- (BOOL)activateAudioSessionWithError:(NSError **)error;
- (BOOL)deactivateAudioSessionWithError:(NSError **)error;

- (void)logDebugMessageWithType:(PjSipEndpointLogType)logType context:(NSString *)context message:(NSString *)message;

@end
