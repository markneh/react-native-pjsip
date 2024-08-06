#import <React/RCTBridgeModule.h>

#import "PjSipAccount.h"
#import "PjSipCall.h"

typedef void (^SIPEventCallback)(NSString *name, id metadata);

@interface PjSipEndpoint : NSObject

@property (nonatomic, assign, readonly) BOOL isStarted;
@property (nonatomic, strong) SIPEventCallback sipEventCallback;

@property NSMutableDictionary* accounts;
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

-(PjSipAccount *)createAccount:(NSDictionary*) config;
-(void) deleteAccount:(int) accountId;
-(PjSipAccount *)findAccount:(int)accountId;
-(PjSipCall *)makeCall:(PjSipAccount *) account destination:(NSString *)destination callSettings: (NSDictionary *)callSettings msgData: (NSDictionary *)msgData;
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
@end
