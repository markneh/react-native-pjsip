#import <Foundation/Foundation.h>

@interface PjSipMessage : NSObject

@property NSDictionary * data;

+ (instancetype)itemConfig:(NSDictionary *)config;
- (id)initWithConfig:(NSDictionary *)config;

- (NSDictionary *)toJsonDictionary;

@end
