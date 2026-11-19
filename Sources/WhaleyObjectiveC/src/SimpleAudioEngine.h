#if __has_include(<UIKit/UIKit.h>)
#import <Foundation/Foundation.h>

// Use the real CocosDenshion declarations when building the historical engine.
// The SpriteKit compatibility target supplies its own minimal implementation.
#if __has_include("CocosDenshion.h")
#import "CocosDenshion.h"
#else
@interface CDSoundSource : NSObject
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;
@property (nonatomic, readwrite) float gain;
- (void)play;
- (void)stop;
@end
#endif

@interface SimpleAudioEngine : NSObject
+ (instancetype)sharedEngine;
#if !__has_include("CocosDenshion.h")
// The native host owns an effects session. Sources from a finished session stay
// disabled even if a retained scene tries to play after another host takes over.
// Temporarily gates the current session's sources without rebuilding the game.
@property (nonatomic, readwrite) BOOL soundEffectsEnabled;
- (void)beginSoundEffectsSessionEnabled:(BOOL)enabled;
- (void)endSoundEffectsSession;
#endif
- (CDSoundSource *)soundSourceForFile:(NSString *)file;
- (void)playBackgroundMusic:(NSString *)file loop:(BOOL)loop;
- (void)resumeBackgroundMusic;
- (void)pauseBackgroundMusic;
@end
#endif
