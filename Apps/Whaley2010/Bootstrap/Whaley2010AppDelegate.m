#import <UIKit/UIKit.h>
@interface Whaley2010AppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation Whaley2010AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application
     configurationForConnectingSceneSession:(UISceneSession *)session
                                     options:(UISceneConnectionOptions *)options {
    // Configure explicitly: XcodeGen may generate the final Info.plist without
    // preserving the named UISceneConfigurations entry.
    UISceneConfiguration *configuration = [[[UISceneConfiguration alloc] initWithName:@"Whaley2010" sessionRole:session.role] autorelease];
    configuration.delegateClass = NSClassFromString(@"Whaley2010SceneDelegate");
    return configuration;
}
@end
