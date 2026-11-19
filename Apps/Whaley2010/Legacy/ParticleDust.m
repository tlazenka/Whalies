//
//  8/20/10.
//

#import "ParticleDust.h"

@implementation ParticleDust

- (id)init {
	if ((self=[super initWithTotalParticles:250])) {
		self.texture = [[CCTextureCache sharedTextureCache] addImage: @"dust.png"];
		_life = 0.1;
		_lifeVar = 0.1f;
		_duration = 0.1f;
		_startSize = 5.0f;
		_startSizeVar = 1.0f;
		_endSize = 7.0f;
		
		_startColor.r = 1.0f;
		_startColor.g = 1.0f;
		_startColor.b = 1.0f;
		_startColor.a = 1.0f;
		_startColorVar.r = 0.0f;
		_startColorVar.g = 0.0f;
		_startColorVar.b = 0.0f;
		_startColorVar.a = 0.0f;
		_endColor.r = 1.0f;
		_endColor.g = 1.0f;
		_endColor.b = 1.0f;
		_endColor.a = 0.0f;
		_endColorVar.r = 0.0f;
		_endColorVar.g = 0.0f;
		_endColorVar.b = 0.0f;
		_endColorVar.a = 0.0f;
		
		self.blendAdditive = YES;
	}
	return self;
}

@end
