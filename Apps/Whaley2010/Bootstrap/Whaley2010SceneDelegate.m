#import <UIKit/UIKit.h>
#import "cocos2d.h"
#import "SimpleAudioEngine.h"
#import "CDAudioManager.h"
#import "GameState.h"
#import "MainMenu.h"
#import "Constants.h"

@class Whaley2010SceneDelegate;

// A layout callback is necessary on iPad: safe areas and window dimensions can
// change after scene:willConnectToSession:options: has already returned.
@interface Whaley2010ContainerController : UIViewController
@property (nonatomic, assign) Whaley2010SceneDelegate *sceneDelegate;
@end

@interface Whaley2010SceneDelegate : UIResponder <UIWindowSceneDelegate, CCDirectorDelegate>
@property (nonatomic, retain) UIWindow *window;
@property (nonatomic, retain) Whaley2010ContainerController *container;
@property (nonatomic, assign) CCDirectorIOS *director;
- (void)resizeGameSurface;
@end

@implementation Whaley2010ContainerController
@synthesize sceneDelegate = _sceneDelegate;

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.sceneDelegate resizeGameSurface];
}
@end

@implementation Whaley2010SceneDelegate
@synthesize window = _window, container = _container, director = _director;

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
                                     options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;

    [GameState loadGameStateFromFile];
    // MediaPlayback is CocosDenshion's category that ignores the hardware silent switch.
    [CDAudioManager configure:kAMM_MediaPlayback];
    [[CDAudioManager sharedManager] setResignBehavior:kAMRBStopPlay autoHandle:YES];

    self.window = [[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene] autorelease];
    self.window.backgroundColor = UIColor.blackColor;

    Whaley2010ContainerController *container =
        [[[Whaley2010ContainerController alloc] init] autorelease];
    container.sceneDelegate = self;
    self.container = container;
    self.container.view.backgroundColor = UIColor.blackColor;

    // Keep this view's *bounds* fixed to the original logical resolution.
    // Applying a frame resize would change CCDirector.winSize and game physics.
    CCGLView *glView = [CCGLView viewWithFrame:CGRectMake(0, 0, 320, 568)
                                  pixelFormat:kEAGLColorFormatRGBA8
                                  depthFormat:0
                           preserveBackbuffer:NO
                                   sharegroup:nil
                                multiSampling:NO
                              numberOfSamples:0];
    _director = (CCDirectorIOS *)[CCDirector sharedDirector];
    [_director setDisplayStats:NO];
    [_director setAnimationInterval:1.0 / 60.0];
    [_director setView:glView];
    [_director setDelegate:self];
    [_director setProjection:kCCDirectorProjection2D];
    [CCTexture2D setDefaultAlphaPixelFormat:kCCTexture2DPixelFormat_RGBA8888];
    [CCTexture2D PVRImagesHavePremultipliedAlpha:YES];
    [[CCFileUtils sharedFileUtils] setEnableFallbackSuffixes:NO];

    [self.container addChildViewController:_director];
    [self.container.view addSubview:_director.view];
    [_director didMoveToParentViewController:self.container];
    self.window.rootViewController = self.container;
    [self.window makeKeyAndVisible];
    [self resizeGameSurface];

    NSString *music = [GameState gameState].levelsAchieved > NumLevels ? MusicFile2 : MusicFile1;
    [[SimpleAudioEngine sharedEngine] playBackgroundMusic:music loop:NO];
    [_director runWithScene:[MainMenu initWithLevelsAchieved:YES]];
}

- (void)resizeGameSurface {
    if (!_director || !self.container.isViewLoaded) return;
    UIView *view = self.container.view;
    CGRect bounds = view.bounds;
    CGRect available = UIEdgeInsetsInsetRect(bounds, view.safeAreaInsets);
    if (CGRectIsEmpty(available)) available = bounds;
    if (CGRectIsEmpty(available)) return;
    CGFloat scale = MIN(CGRectGetWidth(available) / 320.0,
                        CGRectGetHeight(available) / 568.0);
    if (scale <= 0 || !isfinite(scale)) return;

    // Transform rather than alter bounds: gameplay continues to see 320×568.
    UIView *renderView = _director.view;
    renderView.bounds = CGRectMake(0, 0, 320, 568);
    renderView.transform = CGAffineTransformMakeScale(scale, scale);
    renderView.center = CGPointMake(CGRectGetMidX(available), CGRectGetMidY(available));
}

- (void)windowScene:(UIWindowScene *)windowScene
 didUpdateCoordinateSpace:(id<UICoordinateSpace>)previousCoordinateSpace
 interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation
     traitCollection:(UITraitCollection *)previousTraitCollection {
    [self resizeGameSurface];
}

- (void)sceneWillResignActive:(UIScene *)scene { [_director pause]; }
- (void)sceneDidBecomeActive:(UIScene *)scene { [_director resume]; }
- (void)sceneDidEnterBackground:(UIScene *)scene {
    [GameState saveGameStateToFile];
    [_director stopAnimation];
}
- (void)sceneWillEnterForeground:(UIScene *)scene {
    [_director startAnimation];
    [self resizeGameSurface];
}
- (void)sceneDidDisconnect:(UIScene *)scene {
    [GameState saveGameStateToFile];
    [_director stopAnimation];
}
- (void)dealloc {
    _container.sceneDelegate = nil;
    [_director setDelegate:nil];
    [_window release];
    [_container release];
    [super dealloc];
}
@end
