"""Reference for CrowdCore; fixture values must match Swift bit for bit."""
import json
from argparse import Namespace
from pathlib import Path
from .math import (ONE, TURN, QUARTER, fx, fmul, fdiv, fsqrt, clamp, vadd, vsub, vdot, vscale, normalize_turn,
                         sin_turn, cos_turn, direction, Digest)

NONE, BEGAN, MOVED, ENDED, CANCELLED = 0, 1, 2, 3, 4
HEAD, TORSO = 0, 1
SPINNING, REQUESTING, OBSERVING = 0, 1, 2
SEATED, THINKING, WANTING_HOT_DOG, WATCHING, CATCHING, STRUCK = 0, 1, 2, 3, 4, 5


STANDS = dict(
    centre=[fx(0.0), fx(45.0)],
    rows=[[fx(70.0), fx(2.0)], [fx(74.0), fx(4.5)], [fx(78.0), fx(7.0)]],    # (Radius, seat height), front row first.
    seats=64,                                                     # Seats per row.
    start=2 * QUARTER,                                            # Start each row behind home plate.
    headHeight=fx(1.4), torsoHeight=fx(0.8), headR=fx(0.25), torsoR=fx(0.45),
)


def figures(st=STANDS):
    """Fans are ordered front row first, then counterclockwise from home plate."""
    step = TURN // st['seats']
    out = []
    for radius, base in st['rows']:
        for k in range(st['seats']):
            a = normalize_turn(st['start'] - k * step)
            out.append(dict(x=st['centre'][0] + fmul(radius, sin_turn(a)), base=base, z=st['centre'][1] + fmul(radius, cos_turn(a)),
                            headY=base + st['headHeight'], torsoY=base + st['torsoHeight'], headR=st['headR'], torsoR=st['torsoR']))
    return out


def head(f): return (f['x'], f['headY'], f['z'])
def torso(f): return (f['x'], f['torsoY'], f['z'])


def thought_phase(s, t):
    if s['start'] - s['spinTicks'] <= t < s['start']:
        return SPINNING
    if s['start'] <= t < s['end']:
        return REQUESTING if s['symbol'] == 0 else OBSERVING
    return None


def camera_basis(eye, target):
    """Return fixed-point (forward, right, up), looking from eye to target."""
    d = vsub(target, eye)
    length = fsqrt(vdot(d, d))
    f = (fdiv(d[0], length), fdiv(d[1], length), fdiv(d[2], length))
    rl = fsqrt(fmul(f[2], f[2]) + fmul(f[0], f[0]))
    r = (fdiv(f[2], rl), 0, fdiv(-f[0], rl))
    u = (fmul(f[1], r[2]) - fmul(f[2], r[1]), fmul(f[2], r[0]) - fmul(f[0], r[2]), fmul(f[0], r[1]) - fmul(f[1], r[0]))
    return f, r, u


def frames(camera, basis, point):
    f, r, u = basis
    v = vsub(point, camera['eye'])
    fc = vdot(v, f)
    if fc <= 0 or fc > camera['range']:
        return False
    return abs(vdot(v, r)) <= fmul(fc, camera['tanHalfH']) and abs(vdot(v, u)) <= fmul(fc, camera['tanHalfV'])


class Scope:
    """Drag uses relative displacement; only ending a held touch fires.
    Cancellation ends the hold without firing."""
    def __init__(self, yaw=0, pitch=0):
        self.yaw = yaw
        self.pitch = pitch
        self.holding = False
        self.mag = 0

    def step(self, aim, inp):
        phase, dx, dy, mag = inp
        self.mag = clamp(mag, 0, len(aim['magnifications']) - 1)
        fire = False
        if phase == BEGAN:
            self.holding = True
        elif phase == MOVED and self.holding:
            s = aim['sensitivity'][self.mag]
            self.yaw = normalize_turn(self.yaw + fmul(dx, s))
            self.pitch = clamp(self.pitch - fmul(dy, s), -aim['pitchLimit'], aim['pitchLimit'])
        elif phase == ENDED:
            if self.holding:
                fire = True
            self.holding = False
        elif phase == CANCELLED:
            self.holding = False
        return fire


def drag(k, sensitivity):
    """Invert fixed-point multiplication so fmul(drag(k, s), s) == k."""
    if k >= 0:
        return (k * ONE + sensitivity - 1) // sensitivity
    return -((-k) * ONE // sensitivity)


def move(k_yaw, k_pitch, sensitivity, mag=0):
    """Positive pitch needs negative screen y because screen y points down."""
    return (MOVED, drag(k_yaw, sensitivity), drag(-k_pitch, sensitivity), mag)


def ray_sphere(origin, d, centre, radius):
    """Requires a unit direction. Measure the miss vector directly: subtracting
    large squared distances loses precision in 16.16 arithmetic."""
    v = vsub(centre, origin)
    tca = vdot(v, d)
    if tca <= 0:
        return None
    m = vsub(v, vscale(d, tca))
    d2 = vdot(m, m)
    r2 = fmul(radius, radius)
    if d2 > r2:
        return None
    return tca - fsqrt(r2 - d2)


def first_hit(origin, d, figs, skip=()):
    """Return (figure, part, distance), or None. Ties favor the lower index, then the head."""
    best = None
    for i, f in enumerate(figs):
        if i in skip:
            continue
        for part, centre, radius in ((HEAD, head(f), f['headR']), (TORSO, torso(f), f['torsoR'])):
            dist = ray_sphere(origin, d, centre, radius)
            if dist is not None and (best is None or dist < best[2]):
                best = (i, part, dist)
    return best


CROWD = dict(catchTicks=90, strikeTicks=120)


class Crowd:
    def __init__(self, n, p=CROWD):
        self.p = p
        self.states = [SEATED] * n
        self.remaining = [0] * n

    def step(self, struck, caught, phase_of):
        """Current strikes win over catches; reactions override scheduled thoughts.
        phase_of(i) excludes interrupted thoughts and returns None when idle."""
        for i in range(len(self.states)):
            if i in struck:
                self.states[i] = STRUCK; self.remaining[i] = self.p['strikeTicks']; continue
            if i in caught:
                self.states[i] = CATCHING; self.remaining[i] = self.p['catchTicks']; continue
            if self.remaining[i] > 0:
                self.remaining[i] -= 1
                if self.remaining[i] > 0:
                    continue
                self.states[i] = SEATED
            ph = phase_of(i)
            self.states[i] = SEATED if ph is None else ph + 1
        return list(self.states)

    def mix(self, digest):
        digest.mix_all(self.states)


CAMERA = dict(eye=[fx(37.0), fx(1.7), fx(11.5)], tanHalfH=fx(0.35), tanHalfV=fx(0.197), range=fx(40.0))
CAMERA_TARGETS = [7, 8, 9, 72, 10, 140]
AIM = dict(magnifications=[4], sensitivity=[3], pitchLimit=fx(0.1))
SCOPE_TICKS = 400
RAYS = [(7, 0, 0), (7, 300, 0), (7, 0, 150), (8, -40, 20), (72, 0, -60), (140, 0, 0)]   # (Fan, yaw offset, pitch offset), in raw turn units.
MUZZLE = (fx(36.0), fx(1.6), fx(-6.0))
SCHEDULE = [dict(figure=3, start=60, end=120, spinTicks=40, symbol=0), dict(figure=5, start=100, end=150, spinTicks=50, symbol=3),
            dict(figure=9, start=200, end=260, spinTicks=60, symbol=0), dict(figure=3, start=300, end=330, spinTicks=30, symbol=0)]
STRIKES = {70: [9], 190: [9], 230: [5]}                  # Tick -> struck fans.
CATCHES = {40: [3], 150: [64], 250: [9]}
CROWD_TICKS = 400


def scope_script(t):
    s = AIM['sensitivity'][0]
    if t == 20: return (BEGAN, fx(300.0), fx(-200.0), 0)            # Touch-down coordinates must not count as movement.
    if 21 <= t < 60: return move(7, -3, s)
    if t == 60: return (ENDED, 0, 0, 0)
    if t == 100: return (ENDED, 0, 0, 0)                              # No held touch to release.
    if t == 150: return (BEGAN, 0, 0, 0)
    if 151 <= t < 200: return move(-11, 5, s)
    if t == 200: return (CANCELLED, 0, 0, 0)                          # Cancellation must not fire.
    if 250 <= t < 260: return move(40, 40, s)                         # Movement without a hold must be ignored.
    if t == 300: return (BEGAN, 0, 0, 0)
    if t == 301: return (ENDED, 0, 0, 0)
    if t == 330: return (BEGAN, 0, 0, 0)
    if 331 <= t < 380: return move(0, 70, s)
    if t == 380: return (ENDED, 0, 0, 0)
    return (NONE, 0, 0, 0)


def scope_run():
    scope = Scope(yaw=fx(0.25), pitch=0)
    rows = []
    for t in range(SCOPE_TICKS):
        fire = scope.step(AIM, scope_script(t))
        rows.append([scope.yaw, scope.pitch, 1 if scope.holding else 0, 1 if fire else 0])
    return rows


def aim_at(origin, point):
    from .math import bearing, elevation
    dx, dy, dz = point[0] - origin[0], point[1] - origin[1], point[2] - origin[2]
    return bearing(dx, dz), elevation(dy, fsqrt(fmul(dx, dx) + fmul(dz, dz)))


def crowd_run(figs):
    crowd = Crowd(len(figs))
    called = set()
    digest = Digest()
    samples = []
    for t in range(CROWD_TICKS):
        struck = set(STRIKES.get(t, [])); caught = set(CATCHES.get(t, []))
        for k, s in enumerate(SCHEDULE):          # Cancel thoughts overlapping a strike or catch reaction.
            for i, dur in [(i, CROWD['strikeTicks']) for i in struck] + [(i, CROWD['catchTicks']) for i in caught]:
                if s['figure'] == i and s['start'] - s['spinTicks'] < t + dur and t < s['end']:
                    called.add(k)

        def phase_of(i):
            for k, s in enumerate(SCHEDULE):
                if s['figure'] != i or k in called:
                    continue
                ph = thought_phase(s, t)
                if ph is not None:
                    return ph
            return None
        states = crowd.step(struck, caught, phase_of)
        crowd.mix(digest)
        if t % 10 == 0:
            samples.append([t] + [states[i] for i in (3, 5, 9, 64)])
    return dict(samples=samples, called=sorted(called), digest=digest.hex)


def fixture():
    figs = figures()
    cam = []
    for i in CAMERA_TARGETS:
        basis = camera_basis(CAMERA['eye'], head(figs[i]))
        cam.append(dict(target=i, basis=[list(v) for v in basis], framed=[j for j, f in enumerate(figs) if frames(CAMERA, basis, head(f))]))
    rays = []
    for i, dyaw, dpitch in RAYS:
        yaw, pitch = aim_at(MUZZLE, head(figs[i]))
        d = direction(normalize_turn(yaw + dyaw), pitch + dpitch)
        hit = first_hit(MUZZLE, d, figs)
        rays.append(dict(figure=i, dyaw=dyaw, dpitch=dpitch, yaw=yaw, pitch=pitch, hit=list(hit) if hit else None))
    return dict(stands=STANDS, figures=[[f['x'], f['base'], f['z'], f['headY'], f['torsoY']] for f in figs],
                camera=CAMERA, cameraViews=cam, aim=AIM, scope=scope_run(), muzzle=list(MUZZLE), rays=rays,
                crowd=CROWD, schedule=SCHEDULE, strikes={str(k): v for k, v in STRIKES.items()},
                catches={str(k): v for k, v in CATCHES.items()}, crowdRun=crowd_run(figs))


def run(args: Namespace, root: Path) -> int:
    if args.fixtures:
        out = args.fixtures
        out.mkdir(parents=True, exist_ok=True)
        fx_ = fixture()
        with (out / 'crowd.json').open('w', encoding='utf-8') as fh:
            json.dump(fx_, fh)
        print(f"{len(fx_['figures'])} fans; camera frames {[len(c['framed']) for c in fx_['cameraViews']]}; rays {[r['hit'][:2] if r['hit'] else None for r in fx_['rays']]}; "
              f"crowd digest {fx_['crowdRun']['digest']}, called off {fx_['crowdRun']['called']}")
    if args.report or not args.fixtures:
        a, b = fixture(), fixture()
        print('deterministic', a == b)
        for c in a['cameraViews']:
            print('camera on', c['target'], 'frames', c['framed'])
        for r in a['rays']:
            print('ray at', r['figure'], (r['dyaw'], r['dpitch']), '->', r['hit'])
        print('scope at the end', a['scope'][-1], 'fires at', [t for t, row in enumerate(a['scope']) if row[3]])
        print('crowd', a['crowdRun'])
    return 0
