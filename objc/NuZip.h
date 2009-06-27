

#import <Foundation/Foundation.h>

@interface NuZip : NSObject {}

+ (int) unzip:(NSString *) command;
+ (int) zip:(NSString *) command;

@end
