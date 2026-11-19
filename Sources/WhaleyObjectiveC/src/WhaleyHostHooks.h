#ifndef WHALEY_HOST_HOOKS_H
#define WHALEY_HOST_HOOKS_H
#import "WhaleyScene.h"

#if defined(WHALEY_SPRITEKIT_COMPAT)
FOUNDATION_EXPORT BOOL WhaleyHostOwnsProjectile(Projectile *projectile);
FOUNDATION_EXPORT BOOL WhaleyHostProjectileIsFixed(Projectile *projectile);
FOUNDATION_EXPORT void WhaleyObserveProjectileContact(Whaley *game, Projectile *projectile, BOOL bounced);
FOUNDATION_EXPORT void WhaleyObserveProjectileRemoval(Whaley *game, Projectile *projectile);
FOUNDATION_EXPORT void WhaleyObserveCoin(Whaley *game, Collectible *coin);
FOUNDATION_EXPORT void WhaleyObserveDeath(Whaley *game);
FOUNDATION_EXPORT void WhaleyObserveGoal(Whaley *game);
#else
// The original cocos2d target compiles the same gameplay sources without the
// SpriteKit host. These observation hooks never change its gameplay behavior.
static inline BOOL WhaleyHostOwnsProjectile(Projectile *p) { return NO; }
static inline BOOL WhaleyHostProjectileIsFixed(Projectile *p) { return NO; }
static inline void WhaleyObserveProjectileContact(Whaley *g, Projectile *p, BOOL bounced) {}
static inline void WhaleyObserveProjectileRemoval(Whaley *g, Projectile *p) {}
static inline void WhaleyObserveCoin(Whaley *g, Collectible *c) {}
static inline void WhaleyObserveDeath(Whaley *g) {}
static inline void WhaleyObserveGoal(Whaley *g) {}
#endif
#endif
