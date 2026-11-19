"""Reference for WhaleKartCore; integer operations and fixtures must match Swift exactly."""
import json
from argparse import Namespace
from pathlib import Path
from .math import (ONE, TURN, QUARTER, fx, fmul, fdiv, fsqrt, clamp, vadd, vsub, vscale, vlen, vscaled_to, vhalf,
                         normalize_turn, sin_turn, cos_turn, forward, right, bearing, Digest)

TICKS = 3600


def ring_points(centre, radius, count, start):
    """Counterclockwise from the starting bearing, using fixed-point arithmetic."""
    step = TURN // count
    pts = []
    for k in range(count):
        a = normalize_turn(start - k * step)
        pts.append((centre[0] + fmul(radius, sin_turn(a)), centre[1] + fmul(radius, cos_turn(a))))
    return pts


def loop_points(centre, toward, near, far, span, arc=17, turn=10):
    """Join concentric arcs with semicircular ends, starting at the near arc's middle.
    arc is odd; turn counts segments per semicircle. All divisions use positive operands
    to keep Python and Swift rounding identical."""
    mid, r = (near + far) // 2, (far - near) // 2
    half = TURN // 2

    def at(c, radius, b):
        return (c[0] + fmul(radius, sin_turn(b)), c[1] + fmul(radius, cos_turn(b)))

    near_arc = [at(centre, near, normalize_turn(toward - span + (2 * span * k) // (arc - 1))) for k in range(arc)]
    far_arc = [at(centre, far, normalize_turn(toward + span - (2 * span * k) // (arc - 1))) for k in range(arc)]
    hi, lo = at(centre, mid, normalize_turn(toward + span)), at(centre, mid, normalize_turn(toward - span))
    turn_hi = [at(hi, r, normalize_turn(toward + span + half - (half * k) // turn)) for k in range(1, turn)]
    turn_lo = [at(lo, r, normalize_turn(toward - span - (half * k) // turn)) for k in range(1, turn)]
    m = arc // 2
    return near_arc[m:] + turn_hi + far_arc + turn_lo + near_arc[:m]


class Track:
    """Progress is arc length from the first point on the closed polyline."""
    def __init__(self, points, road_half):
        self.points = points
        self.road_half = road_half
        n = len(points)
        self.seg = []
        self.seglen = []
        self.cum = [0]
        for i in range(n):
            ax, az = points[i]; bx, bz = points[(i + 1) % n]
            ex, ez = bx - ax, bz - az
            self.seg.append((ex, ez))
            length = fsqrt(fmul(ex, ex) + fmul(ez, ez))
            self.seglen.append(length)
            self.cum.append(self.cum[-1] + length)
        self.total = self.cum[n]

    def locate(self, x, z):
        """Return (progress, distance, signed side, segment); positive side is right of travel."""
        best = None
        n = len(self.points)
        for i in range(n):
            ax, az = self.points[i]
            ex, ez = self.seg[i]
            px, pz = x - ax, z - az
            len2 = fmul(ex, ex) + fmul(ez, ez)
            dot = fmul(px, ex) + fmul(pz, ez)
            t = clamp(fdiv(dot, len2), 0, ONE)
            cx, cz = ax + fmul(ex, t), az + fmul(ez, t)
            dx, dz = x - cx, z - cz
            d2 = fmul(dx, dx) + fmul(dz, dz)
            if best is None or d2 < best[0]:
                best = (d2, i, t)
        d2, i, t = best
        ax, az = self.points[i]; ex, ez = self.seg[i]
        cx, cz = ax + fmul(ex, t), az + fmul(ez, t)
        side = fdiv(fmul(x - cx, ez) - fmul(z - cz, ex), self.seglen[i])
        return self.cum[i] + fmul(self.seglen[i], t), fsqrt(d2), side, i

    def point_at(self, s):
        """Progress wraps around the closed track."""
        d = s % self.total
        i = 0
        while i < len(self.points) - 1 and self.cum[i + 1] <= d:
            i += 1
        length = self.seglen[i]
        t = clamp(fdiv(d - self.cum[i], length), 0, ONE) if length > 0 else 0
        ax, az = self.points[i]; ex, ez = self.seg[i]
        return (ax + fmul(ex, t), az + fmul(ez, t))

    def direction_at(self, s):
        d = s % self.total
        i = 0
        while i < len(self.points) - 1 and self.cum[i + 1] <= d:
            i += 1
        length = self.seglen[i]
        ex, ez = self.seg[i]
        return (fdiv(ex, length), fdiv(ez, length)) if length > 0 else (0, ONE)


FIELD_CENTRE = (fx(0.0), fx(45.0))       # Home plate is the origin; +z points to center field and +x to the right.

PARAMS = dict(
    hitches=[fx(-0.5), fx(0.5)],          # Rear hitch offsets, left then right.
    cans=3,                               # Cans per string.
    segment=fx(1.2), canRadius=fx(0.15), hitchOffset=fx(1.5),
    dt=fx(1 / 60), gravity=fx(9.8), damping=fx(0.98), groundFriction=fx(0.90), tautEps=fx(0.02), iterations=4,
    tossUp=fx(3.0), airborneTicks=24,
    cruiseSpeed=fx(6.0), accel=fx(3.0), decel=fx(6.0),
    lookahead=fx(8.0), steerGain=fx(0.3183), yawMax=fx(0.12),
    roadHalf=fx(5.0),
    trackPoints=ring_points(FIELD_CENTRE, fx(62.0), 64, 2 * QUARTER),
)


def can_count(p):
    return len(p['hitches']) * p['cans']


class Car:
    def __init__(self, p, track):
        self.x, self.z = track.points[0]
        ex, ez = track.seg[0]
        self.heading = bearing(ex, ez)
        self.yaw_rate = 0                       # Turns per second.
        self.speed = 0
        self.progress, self.offset, self.side, self.segment = track.locate(self.x, self.z)
        self.off_track = False

    def hitch(self, p, s):
        f = forward(self.heading); r = right(self.heading); h = p['hitches'][s]
        return (self.x - fmul(f[0], p['hitchOffset']) + fmul(r[0], h), p['canRadius'],
                self.z - fmul(f[2], p['hitchOffset']) + fmul(r[2], h))

    def local_to_world(self, p, dx, dz):
        """Car-relative coordinates: dx points right; dz points forward from the rear."""
        f = forward(self.heading); r = right(self.heading)
        along = dz - p['hitchOffset']
        return (self.x + fmul(r[0], dx) + fmul(f[0], along), p['canRadius'], self.z + fmul(r[2], dx) + fmul(f[2], along))

    def local_velocity_to_world(self, vx, vz):
        f = forward(self.heading); r = right(self.heading)
        return (fmul(r[0], vx) + fmul(f[0], vz), 0, fmul(r[2], vx) + fmul(f[2], vz))

    def step(self, p, track):
        """Pure pursuit of the lookahead point; rope forces do not affect the kart."""
        r = right(self.heading)
        ax, az = track.point_at(self.progress + p['lookahead'])
        dx, dz = ax - self.x, az - self.z
        side = fmul(dx, r[0]) + fmul(dz, r[2])
        d2 = fmul(dx, dx) + fmul(dz, dz)
        self.yaw_rate = clamp(fdiv(fmul(fmul(p['steerGain'], self.speed), side), d2), -p['yawMax'], p['yawMax']) if d2 > 0 else 0
        self.heading = normalize_turn(self.heading + fmul(self.yaw_rate, p['dt']))
        self.speed += clamp(p['cruiseSpeed'] - self.speed, -fmul(p['decel'], p['dt']), fmul(p['accel'], p['dt']))
        f = forward(self.heading)
        self.x += fmul(fmul(f[0], self.speed), p['dt'])
        self.z += fmul(fmul(f[2], self.speed), p['dt'])
        self.progress, self.offset, self.side, self.segment = track.locate(self.x, self.z)
        self.off_track = self.offset > p['roadHalf']

    def step_steered(self, p, track, steer, rail_half):
        """Clamp to the rails and limit heading correction to full steering speed.
        This keeps the following camera continuous, including reverse travel."""
        turn = fmul(fmul(clamp(steer, -ONE, ONE), p['yawMax']), p['dt'])
        self.heading = normalize_turn(self.heading + turn)
        self.speed += clamp(p['cruiseSpeed'] - self.speed, -fmul(p['decel'], p['dt']), fmul(p['accel'], p['dt']))
        f = forward(self.heading)
        self.x += fmul(fmul(f[0], self.speed), p['dt'])
        self.z += fmul(fmul(f[2], self.speed), p['dt'])
        progress, offset, side, segment = track.locate(self.x, self.z)
        railed = False
        if offset > rail_half:
            cx, cz = track.point_at(progress)
            nx, nz = fdiv(self.x - cx, offset), fdiv(self.z - cz, offset)
            self.x = cx + fmul(nx, rail_half)
            self.z = cz + fmul(nz, rail_half)
            ex, ez = track.direction_at(progress)
            d = normalize_turn(bearing(ex, ez) - self.heading)
            if d > TURN // 2:
                d -= TURN
            if d > QUARTER:
                d -= TURN // 2
            elif d < -QUARTER:
                d += TURN // 2
            most = fmul(p['yawMax'], p['dt'])
            d = clamp(d, -most, most)
            self.heading = normalize_turn(self.heading + d)
            turn += d
            progress, offset, side, segment = track.locate(self.x, self.z)
            railed = True
        self.yaw_rate = fdiv(turn, p['dt'])
        self.progress, self.offset, self.side, self.segment = progress, offset, side, segment
        self.off_track = self.offset > p['roadHalf']
        return railed


def reach(p, s, k, dx, dz):
    """Clamp the hand's car-relative position to the selected can's string length."""
    hx = p['hitches'][s]
    ex, ez = dx - hx, dz
    length = fsqrt(fmul(ex, ex) + fmul(ez, ez))
    limit = p['segment'] * (k + 1)
    if length > limit:
        ex, ez = fdiv(fmul(ex, limit), length), fdiv(fmul(ez, limit), length)
    return hx + ex, ez


def initial_cans(p, car):
    f = forward(car.heading)
    out = []
    for s in range(len(p['hitches'])):
        h = car.hitch(p, s)
        for k in range(p['cans']):
            out.append((h[0] - fmul(f[0], p['segment'] * (k + 1)), p['canRadius'], h[2] - fmul(f[2], p['segment'] * (k + 1))))
    return out


class RulesChainRope:
    """Model A uses distance limits and timed triangular tosses, without a physics solver."""
    name = 'a'

    def __init__(self, p, car):
        n = can_count(p)
        self.pos = initial_cans(p, car); self.air = [0] * n; self.airvel = [(0, 0, 0)] * n; self.taut = [False] * n
        self.held = -1

    def forward_pass(self, p, s, hitch):
        per = p['cans']
        for k in range(per):
            i = s * per + k
            anchor = hitch if k == 0 else self.pos[i - 1]
            d = vsub(self.pos[i], anchor); length = vlen(d)
            self.taut[i] = length >= p['segment'] - p['tautEps']
            if length > p['segment'] and i != self.held:
                self.pos[i] = vadd(anchor, vscaled_to(d, length, p['segment']))

    def backward_pass(self, p, s, top):
        per = p['cans']
        for k in range(top - 1, -1, -1):
            i = s * per + k
            nxt = self.pos[i + 1]; d = vsub(self.pos[i], nxt); length = vlen(d)
            if length > p['segment']:
                self.pos[i] = vadd(nxt, vscaled_to(d, length, p['segment']))

    def step(self, p, car, inp):
        n = can_count(p); per = p['cans']; events = []
        hitches = [car.hitch(p, s) for s in range(len(p['hitches']))]
        held, dx, dz, toss, tvx, tvz = inp
        self.held = held if 0 <= held < n else -1
        if self.held >= 0:
            i = self.held
            dx, dz = reach(p, i // per, i % per, dx, dz)
            self.pos[i] = car.local_to_world(p, dx, dz)
            self.air[i] = 0
            if toss:
                self.air[i] = p['airborneTicks']; self.airvel[i] = car.local_velocity_to_world(tvx, tvz); self.held = -1
        for i in range(n):
            if self.air[i] == 0:
                continue
            v = self.airvel[i]; half = p['airborneTicks'] >> 1
            steps = self.air[i] if self.air[i] <= half else p['airborneTicks'] - self.air[i]
            arc = fmul(p['tossUp'], p['dt']) * steps
            self.pos[i] = (self.pos[i][0] + fmul(v[0], p['dt']), p['canRadius'] + arc, self.pos[i][2] + fmul(v[2], p['dt']))
            self.air[i] -= 1
            if self.air[i] == 0:
                self.pos[i] = (self.pos[i][0], p['canRadius'], self.pos[i][2]); events.append(('clink', i))
        # Relax from the held can back to the hitch, then forward again.
        for s in range(len(p['hitches'])):
            hitch = hitches[s]
            self.forward_pass(p, s, hitch)
            if self.held >= 0 and self.held // per == s:
                top = self.held % per
                if top > 0:
                    self.backward_pass(p, s, top); self.forward_pass(p, s, hitch)
                d = vsub(self.pos[self.held], hitch); dist = vlen(d); total = p['segment'] * (top + 1)
                if dist > total:
                    for k in range(top):
                        self.pos[s * per + k] = vadd(hitch, vscaled_to(d, ONE * (top + 1), ONE * (k + 1)))
        strain = [0] * n
        for i in range(n):
            if self.air[i] == 0:
                self.pos[i] = (self.pos[i][0], p['canRadius'], self.pos[i][2])
            anchor = hitches[i // per] if i % per == 0 else self.pos[i - 1]
            length = vlen(vsub(self.pos[i], anchor))
            strain[i] = fdiv(length - p['segment'], p['segment']) if length > p['segment'] else 0
        return strain, events

    def report(self, p):
        return [dict(pos=list(self.pos[i]), grounded=self.air[i] == 0, held=(i == self.held), taut=self.taut[i]) for i in range(len(self.pos))]


class PBDRope:
    """Model B uses Verlet integration and iterative distance constraints."""
    name = 'b'

    def __init__(self, p, car):
        n = can_count(p)
        self.pos = initial_cans(p, car); self.prev = list(self.pos)
        self.taut = [False] * n; self.tension = [0] * n; self.grounded = [True] * n; self.held = -1

    def step(self, p, car, inp):
        n = can_count(p); per = p['cans']; events = []; dt = p['dt']; dt2 = fmul(dt, dt)
        hitches = [car.hitch(p, s) for s in range(len(p['hitches']))]
        held, dx, dz, toss, tvx, tvz = inp
        self.held = held if 0 <= held < n else -1
        if self.held >= 0:
            i = self.held
            dx, dz = reach(p, i // per, i % per, dx, dz)
            self.pos[i] = car.local_to_world(p, dx, dz)
            if toss:
                tv = car.local_velocity_to_world(tvx, tvz)
                self.prev[i] = vsub(self.pos[i], (fmul(tv[0], dt), fmul(p['tossUp'], dt), fmul(tv[2], dt))); self.held = -1
            else:
                self.prev[i] = self.pos[i]
        gdt2 = fmul(p['gravity'], dt2)
        for i in range(n):
            if i == self.held:
                continue
            vel = vsub(self.pos[i], self.prev[i])
            if self.grounded[i]:
                vel = (fmul(vel[0], p['groundFriction']), vel[1], fmul(vel[2], p['groundFriction']))
            vel = vscale(vel, p['damping'])
            self.prev[i] = self.pos[i]
            self.pos[i] = (self.pos[i][0] + vel[0], self.pos[i][1] + vel[1] - gdt2, self.pos[i][2] + vel[2])
        for it in range(p['iterations']):
            last = it == p['iterations'] - 1
            for i in range(n):
                k = i % per
                anchor = hitches[i // per] if k == 0 else self.pos[i - 1]
                d = vsub(self.pos[i], anchor); length = vlen(d)
                if last:
                    self.taut[i] = length >= p['segment'] - p['tautEps']
                    self.tension[i] = length - p['segment'] if length > p['segment'] else 0
                if length <= p['segment']:
                    continue
                corr = vscaled_to(d, length, length - p['segment'])
                if k == 0:
                    if self.held != i:
                        self.pos[i] = vsub(self.pos[i], corr)
                elif self.held == i:
                    self.pos[i - 1] = vadd(self.pos[i - 1], corr)
                elif self.held == i - 1:
                    self.pos[i] = vsub(self.pos[i], corr)
                else:
                    h = vhalf(corr)
                    self.pos[i - 1] = vadd(self.pos[i - 1], h); self.pos[i] = vsub(self.pos[i], h)
            for i in range(n):
                if self.pos[i][1] < p['canRadius']:
                    self.pos[i] = (self.pos[i][0], p['canRadius'], self.pos[i][2])
        for i in range(n):
            was = self.grounded[i]
            self.grounded[i] = self.pos[i][1] <= p['canRadius'] + p['tautEps']
            if self.grounded[i] and not was:
                events.append(('clink', i))
        strain = [fdiv(self.tension[i], p['segment']) if self.tension[i] > 0 else 0 for i in range(n)]
        return strain, events

    def report(self, p):
        return [dict(pos=list(self.pos[i]), grounded=self.grounded[i], held=(i == self.held), taut=self.taut[i]) for i in range(len(self.pos))]


MODELS = {'a': RulesChainRope, 'b': PBDRope}
NONE = (-1, 0, 0, False, 0, 0)
E_CLINK = 1


class World:
    """Step the rope before driving the kart; rope state cannot affect kart motion."""
    def __init__(self, p, model):
        self.p = p
        self.track = Track(p['trackPoints'], p['roadHalf'])
        self.car = Car(p, self.track)
        self.rope = MODELS[model](p, self.car)
        self.tick = 0
        self.off_track_ticks = 0

    def step(self, inp):
        strain, events = self.rope.step(self.p, self.car, inp)
        self.car.step(self.p, self.track)
        if self.car.off_track:
            self.off_track_ticks += 1
        t = self.tick
        self.tick += 1
        return t, strain, events


def car_values(car):
    return [car.x, car.z, car.heading, car.yaw_rate, car.speed, car.progress, car.offset, car.side, 1 if car.off_track else 0]


def mix(digest, t, car, report, events):
    """Keep field order aligned with KartDigest.mix."""
    digest.mix_all([t] + car_values(car))
    for r in report:
        digest.mix_all(r['pos'])
        digest.mix((1 if r['grounded'] else 0) | (2 if r['held'] else 0) | (4 if r['taut'] else 0))
    for e in events:
        if e[0] == 'clink':
            digest.mix_all([E_CLINK, e[1]])


def script(t):
    """Inputs are (held, dx, dz, toss, tvx, tvz), in the kart's frame.
    Can indices run from the hitch outward, left string before right."""
    def ramp(a, b, t0, t1): return a + ((b - a) * (t - t0)) // (t1 - t0)
    if 300 <= t < 330: return (4, ramp(fx(0.5), fx(2.5), 300, 330), fx(-2.0), False, 0, 0)
    if 330 <= t < 600: return (4, fx(2.5), fx(-2.0), False, 0, 0)
    if 600 <= t < 630: return (4, ramp(fx(2.5), fx(0.5), 600, 630), fx(-2.0), False, 0, 0)
    if 900 <= t < 1080: return (2, fx(-6.0), fx(-4.0), False, 0, 0)
    if 1300 <= t < 1330: return (1, fx(-1.5), fx(-1.5), False, 0, 0)
    if t == 1330: return (1, fx(-1.5), fx(-1.5), True, fx(-2.0), fx(1.0))
    if 2000 <= t < 2020: return (3, fx(1.0), fx(-1.0), False, 0, 0)
    if t == 2020: return (3, fx(1.0), fx(-1.0), True, fx(1.5), fx(-2.0))
    return NONE


def simulate(model_name, inputs, every=10, p=PARAMS):
    world = World(p, model_name)
    samples = []; log = []; digest = Digest()
    for inp in inputs:
        t, strain, events = world.step(inp)
        for e in events:
            log.append((t,) + e)
        report = world.rope.report(p)
        mix(digest, t, world.car, report, events)
        if t % every == 0:
            samples.append(dict(t=t, car=car_values(world.car), cans=[r['pos'] for r in report], strain=strain))
    c = world.car
    return dict(samples=samples, events=[list(e) for e in log], car=car_values(c), offTrackTicks=world.off_track_ticks,
                digest=digest.hex)


def line_held(model_name, inputs, p=PARAMS, settle=180):
    world = World(p, model_name)
    worst = 0; backwards = 0; last = world.car.progress; travelled = 0
    for inp in inputs:
        t, _, _ = world.step(inp)
        c = world.car
        if t >= settle:
            worst = max(worst, c.offset)
        step = (c.progress - last) % world.track.total
        if step > world.track.total // 2:
            backwards += 1
        else:
            travelled += step
        last = c.progress
    return dict(worst=worst / ONE, offTrack=world.off_track_ticks, backwards=backwards, laps=travelled / world.track.total)


def ascii_frame(p, track, car, rope, cols=61, rows=25, metres_per_cell=2.0):
    grid = [[' '] * cols for _ in range(rows)]
    cx, cz = car.x / ONE, car.z / ONE

    def cell(x, z):
        c = int(round((x / ONE - cx) / metres_per_cell)) + cols // 2
        r = rows // 2 - int(round((z / ONE - cz) / metres_per_cell))
        return (r, c) if 0 <= r < rows and 0 <= c < cols else None
    n = len(track.points)
    for i in range(n):
        ax, az = track.points[i]; bx, bz = track.points[(i + 1) % n]
        steps = max(1, int(track.seglen[i] / ONE / metres_per_cell))
        for k in range(steps + 1):
            rc = cell(ax + (bx - ax) * k // steps, az + (bz - az) * k // steps)
            if rc:
                grid[rc[0]][rc[1]] = '.'
    for rep in rope.report(p):
        rc = cell(rep['pos'][0], rep['pos'][2])
        if rc:
            grid[rc[0]][rc[1]] = 'O' if rep['held'] else ('o' if rep['grounded'] else '*')
    rc = cell(car.x, car.z)
    if rc:
        grid[rc[0]][rc[1]] = 'W'
    return '\n'.join(''.join(r) for r in grid)


def status(t, car, rope):
    return (f"t={t} x={car.x/ONE:+.1f} z={car.z/ONE:+.1f} heading={car.heading/ONE*360:.0f}deg yaw={car.yaw_rate/ONE:+.4f} "
            f"speed={car.speed/ONE:.1f} s={car.progress/ONE:.0f} side={car.side/ONE:+.2f}{'!' if car.off_track else ''} "
            f"held={rope.held} taut={[int(v) for v in rope.taut]}")


def run(args: Namespace, root: Path) -> int:
    inputs = [script(t) for t in range(TICKS)]
    if args.fixtures:
        out = args.fixtures
        fixture = dict(parameters=PARAMS,
                       inputs=[dict(t=t, held=i[0], dx=i[1], dz=i[2], toss=i[3], tvx=i[4], tvz=i[5]) for t, i in enumerate(inputs)],
                       models={m: simulate(m, inputs) for m in MODELS})
        out.mkdir(parents=True, exist_ok=True)
        with (out / 'ring-3600.json').open('w', encoding='utf-8') as stream:
            json.dump(fixture, stream)
        for m in MODELS:
            r = fixture['models'][m]
            print(f"model {m}: events {len(r['events'])}, off track {r['offTrackTicks']} ticks, digest {r['digest']}, line {line_held(m, inputs)}")
    if args.report or not (args.fixtures or args.ascii):
        for m in MODELS:
            r = simulate(m, inputs); r2 = simulate(m, inputs)
            alone = simulate(m, [NONE] * TICKS)
            same_car = all(a['car'] == b['car'] for a, b in zip(r['samples'], alone['samples']))
            print(f"model {m}: digest {r['digest']}, deterministic {r == r2}, the cans never move the kart {same_car}, "
                  f"line {line_held(m, inputs)}, four laps {line_held(m, [NONE] * (4 * 3900))}")
            for e in r['events']:
                print('   ', e)
    if args.ascii:
        world = World(PARAMS, args.model)
        for inp in inputs:
            t, _, _ = world.step(inp)
            if t % args.every == 0:
                print(status(t, world.car, world.rope))
                print(ascii_frame(PARAMS, world.track, world.car, world.rope))
    return 0
