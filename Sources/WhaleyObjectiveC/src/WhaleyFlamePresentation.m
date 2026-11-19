#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyFlamePresentation.h"
#if defined(WHALEY_SPRITEKIT_COMPAT)
#import "WhaleyFlameMotion.h"
#import "WhaleyBootstrap.h"

@implementation WhaleyFlamePresentation {
    NSArray<Hazard *> *_sources;
    NSArray<NSNumber *> *_hidden;
    NSMutableArray<SKSpriteNode *> *_nodes;
    SKNode *_layer;
    double _elapsed;
}

- (void)restore {
    for (NSUInteger i = 0; i < _sources.count; i++)
        _sources[i].spriteKitNode.hidden = _hidden[i].boolValue;
    [_sources release]; _sources = nil;
    [_hidden release]; _hidden = nil;
    [_nodes release]; _nodes = nil;
    [_layer removeFromParent];
    [_layer release]; _layer = nil;
}

- (void)advance:(Whaley *)game seconds:(ccTime)seconds {
    if (WhaleyScene3DModeEnabled || !WhaleySrcUsesWhalelandArt()) {
        [self restore];
        _elapsed = 0;
        return;
    }
    if (_layer.parent != game || ![_sources isEqualToArray:game.hazards]) {
        [self restore];
        _sources = [game.hazards copy];
        NSMutableArray *hidden = [NSMutableArray arrayWithCapacity:_sources.count];
        _nodes = [NSMutableArray new];
        _layer = [SKNode new];
        _layer.name = @"WhaleyFlamePresentation";
        [game addChild:(CCNode *)(id)_layer];
        for (Hazard *hazard in _sources) {
            [hidden addObject:@(hazard.spriteKitNode.hidden)];
            SKSpriteNode *node = [SKSpriteNode spriteNodeWithTexture:hazard.spriteKitNode.texture];
            [_layer addChild:node];
            [_nodes addObject:node];
            // Hide only the drawable; the original node still owns collision and phase actions.
            hazard.spriteKitNode.hidden = YES;
        }
        _hidden = [hidden copy];
    }
    _elapsed = WhaleyFlameAdvance(_elapsed, seconds,
        game.isPaused || game.player.isDead || game.player.hasWon);
    BOOL reducedMotion = UIAccessibilityIsReduceMotionEnabled();
    for (NSUInteger i = 0; i < _sources.count; i++) {
        Hazard *hazard = _sources[i];
        SKSpriteNode *source = hazard.spriteKitNode;
        SKSpriteNode *node = _nodes[i];
        node.hidden = !hazard.visible || !hazard.parent || _hidden[i].boolValue;
        if (node.hidden) continue;
        WhaleyFlamePose pose = WhaleyFlamePoseAt(i, _elapsed, reducedMotion);
        // Bypass the wrapper's historical rotation, not its size, tint or position.
        CGPoint center = CGPointMake(hazard.position.x + source.position.x * hazard.xScale,
                                     hazard.position.y + source.position.y * hazard.yScale);
        center = [game convertPoint:center fromNode:hazard.parent];
        node.position = CGPointMake(center.x + pose.offsetX, center.y);
        node.zRotation = -pose.clockwiseDegrees * M_PI / 180.0;
        node.texture = source.texture;
        node.size = source.size;
        node.xScale = hazard.xScale * source.xScale;
        node.yScale = hazard.yScale * source.yScale;
        node.color = source.color;
        node.colorBlendFactor = source.colorBlendFactor;
        node.alpha = hazard.alpha * source.alpha;
        node.zPosition = hazard.zPosition + source.zPosition;
    }
}

- (void)dealloc {
    [self restore];
    [super dealloc];
}
@end
#endif
#endif
