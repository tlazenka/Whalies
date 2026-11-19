#if __has_include(<UIKit/UIKit.h>)
#import "SimpleAudioEngine.h"
#import "WhaleyBootstrap.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

// The original cocos2d target links CocosDenshion. SpriteKit supplies a small
// AVFoundation-backed adapter, retaining the same soundSourceForFile interface.
#if !__has_include("CocosDenshion.h")
@interface CDSoundSource ()
- (instancetype)initWithURL:(NSURL *)url enabled:(BOOL)enabled;
- (void)setPlaybackEnabled:(BOOL)enabled;
- (void)invalidatePlayback;
@end

@implementation CDSoundSource {
    AVAudioPlayer *_player;
    NSURL *_resourceURL;
    float _gain;
    BOOL _playbackEnabled;
    BOOL _invalidated;
}
- (instancetype)initWithURL:(NSURL *)url enabled:(BOOL)enabled {
    if ((self = [super init])) {
        _gain = 1.0f;
        _resourceURL = [url retain];
        [self setPlaybackEnabled:enabled];
    }
    return self;
}
- (void)setPlaybackEnabled:(BOOL)enabled {
    if (_invalidated) return;
    _playbackEnabled = enabled;
    if (!enabled) {
        [self stop];
        return;
    }
    // A host may start muted. Retaining the resource lets its original sources
    // become audible later without replacing the scene or replaying old cues.
    if (!_player && _resourceURL) {
        NSError *error = nil;
        _player = [[AVAudioPlayer alloc] initWithContentsOfURL:_resourceURL error:&error];
        if (!_player) {
            NSLog(@"Whaley sound load failed: %@ (%@)", _resourceURL.lastPathComponent, error);
        } else {
            _player.volume = _gain;
            [_player prepareToPlay];
        }
    }
}
- (BOOL)isPlaying { return _player.isPlaying; }
- (float)gain { return _gain; }
- (void)setGain:(float)gain {
    _gain = fmaxf(0, fminf(gain, 1));
    _player.volume = _gain;
}
- (void)play {
    if (!_playbackEnabled || !_player) return;
    if (_player.isPlaying) [_player stop];
    _player.currentTime = 0;
    [_player play];
}
- (void)stop { [_player stop]; }
- (void)invalidatePlayback {
    _invalidated = YES;
    _playbackEnabled = NO;
    [self stop];
    [_player release];
    _player = nil;
    [_resourceURL release];
    _resourceURL = nil;
}
- (void)dealloc {
    [_player stop];
    [_player release];
    [_resourceURL release];
    [super dealloc];
}
@end

@implementation SimpleAudioEngine {
    AVAudioPlayer *_backgroundPlayer;
    NSString *_backgroundFile;
    BOOL _backgroundPaused;
    BOOL _soundEffectsEnabled;
    NSHashTable<CDSoundSource *> *_soundSources;
}
- (instancetype)init {
    if ((self = [super init])) {
        _soundEffectsEnabled = YES;
        _soundSources = [[NSHashTable weakObjectsHashTable] retain];
    }
    return self;
}
+ (instancetype)sharedEngine {
    static SimpleAudioEngine *e;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [self new]; });
    return e;
}
- (CDSoundSource *)soundSourceForFile:(NSString *)file {
    CDSoundSource *source = [[[CDSoundSource alloc] initWithURL:WhaleySrcResourceURL(file)
                                                     enabled:_soundEffectsEnabled] autorelease];
    [_soundSources addObject:source];
    return source;
}
- (BOOL)soundEffectsEnabled { return _soundEffectsEnabled; }
- (void)setSoundEffectsEnabled:(BOOL)enabled {
    if (_soundEffectsEnabled == enabled) return;
    _soundEffectsEnabled = enabled;
    for (CDSoundSource *source in _soundSources.allObjects) { [source setPlaybackEnabled:enabled]; }
}
- (void)beginSoundEffectsSessionEnabled:(BOOL)enabled {
    [self endSoundEffectsSession];
    _soundEffectsEnabled = enabled;
    [self pauseBackgroundMusic];
}
- (void)endSoundEffectsSession {
    for (CDSoundSource *source in _soundSources.allObjects) { [source invalidatePlayback]; }
    [_soundSources removeAllObjects];
    _soundEffectsEnabled = YES;
}
- (void)playBackgroundMusic:(NSString *)file loop:(BOOL)loop {
    if (!file.length) return;
    if (_backgroundPlayer && [_backgroundFile isEqualToString:file]) {
        _backgroundPlayer.numberOfLoops = loop ? -1 : 0;
        [self resumeBackgroundMusic];
        return; // Returning to the menu must not restart the track.
    }

    NSURL *url = WhaleySrcResourceURL(file);
    if (!url) {
        NSLog(@"Whaley background music resource missing: %@", file);
        return;
    }
    NSError *error = nil;
    AVAudioPlayer *next = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (!next) {
        NSLog(@"Whaley background music load failed: %@ (%@)", file, error);
        return;
    }
    // Playback overrides the ring/silent switch without interrupting other audio.
    NSError *sessionError = nil;
    if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
        withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&sessionError]) {
        NSLog(@"Whaley audio session configuration failed: %@", sessionError);
    }
    next.numberOfLoops = loop ? -1 : 0;
    [next prepareToPlay];
    [_backgroundPlayer stop];
    [_backgroundPlayer release];
    _backgroundPlayer = next;
    [_backgroundFile release];
    _backgroundFile = [file copy];
    _backgroundPaused = NO;
    [_backgroundPlayer play];
}
- (void)pauseBackgroundMusic {
    if (_backgroundPlayer.isPlaying) {
        [_backgroundPlayer pause];
        _backgroundPaused = YES;
    }
}
- (void)resumeBackgroundMusic {
    if (_backgroundPaused) {
        [_backgroundPlayer play];
        _backgroundPaused = NO;
    }
}
- (void)dealloc {
    [self endSoundEffectsSession];
    [_soundSources release];
    [_backgroundPlayer stop];
    [_backgroundPlayer release];
    [_backgroundFile release];
    [super dealloc];
}
@end
#endif // !__has_include("CocosDenshion.h")
#endif // UIKit
