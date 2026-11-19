"""Integer reference for StadiumCore; fixtures require bit-for-bit Swift parity."""
import math
from argparse import Namespace
from pathlib import Path

FRAC = 16
ONE = 1 << FRAC
HALF = ONE >> 1
TURN = ONE
QUARTER = TURN >> 2
TABLE_BITS = 10
TABLE_SIZE = 1 << TABLE_BITS


def fx(v):
    """Round to 16.16 fixed point, with ties to even."""
    return int(round(v * ONE))


def fmul(a, b):
    """Arithmetic right shift floors negative products, matching Swift."""
    return (a * b) >> FRAC


def fdiv(a, b):
    """Divide magnitudes, then restore the sign to truncate toward zero."""
    q = (abs(a) << FRAC) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def isqrt(n):
    """Floor square root without floating-point rounding."""
    if n <= 0:
        return 0
    bit = 1
    while bit <= n >> 2:
        bit <<= 2
    r = 0
    while bit:
        if n >= r + bit:
            n -= r + bit
            r = (r >> 1) + bit
        else:
            r >>= 1
        bit >>= 2
    return r


def fsqrt(a):
    return isqrt(a << FRAC)


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def floordiv(a, b):
    """Match Swift's floorDiv for signed operands."""
    return a // b


# Coordinates are (x, y, z), with y up.

def vadd(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def vsub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def vscale(a, s): return (fmul(a[0], s), fmul(a[1], s), fmul(a[2], s))
def vdot(a, b): return fmul(a[0], b[0]) + fmul(a[1], b[1]) + fmul(a[2], b[2])
def vlen(a): return fsqrt(vdot(a, a))
def vscaled_to(d, length, target):
    """Multiply before dividing to preserve fixed-point rounding."""
    return (fdiv(fmul(d[0], target), length), fdiv(fmul(d[1], target), length), fdiv(fmul(d[2], target), length))
def vhalf(a): return (fmul(a[0], HALF), fmul(a[1], HALF), fmul(a[2], HALF))


# Angles use 16.16 turns: zero faces +z; positive turns rotate toward +x.

SIN_Q = [int(round(math.sin(2 * math.pi * k / TABLE_SIZE) * ONE)) for k in range(TABLE_SIZE // 4 + 1)]
assert SIN_Q[0] == 0 and SIN_Q[-1] == ONE


def normalize_turn(raw):
    """Python's positive-modulus remainder matches Swift's normalized turn."""
    return raw % TURN


def sin_at(i):
    q, k = i >> (TABLE_BITS - 2), i & (TABLE_SIZE // 4 - 1)
    if q == 0: return SIN_Q[k]
    if q == 1: return SIN_Q[TABLE_SIZE // 4 - k]
    if q == 2: return -SIN_Q[k]
    return -SIN_Q[TABLE_SIZE // 4 - k]


def sin_turn(raw):
    """Interpolate so a one-unit raw turn still changes direction."""
    n = normalize_turn(raw)
    i = n >> (FRAC - TABLE_BITS)
    f = n & ((1 << (FRAC - TABLE_BITS)) - 1)
    a = sin_at(i)
    b = sin_at((i + 1) & (TABLE_SIZE - 1))
    return a + (((b - a) * f) >> (FRAC - TABLE_BITS))


def cos_turn(raw):
    return sin_turn(raw + QUARTER)


def forward(heading):
    return (sin_turn(heading), 0, cos_turn(heading))


def right(heading):
    return (cos_turn(heading), 0, -sin_turn(heading))


def direction(yaw, pitch):
    """Yaw rotates from +z toward +x; positive pitch looks up."""
    cp = cos_turn(pitch)
    return (fmul(cp, sin_turn(yaw)), sin_turn(pitch), fmul(cp, cos_turn(yaw)))


def up_of(yaw, pitch):
    sp, cp = sin_turn(pitch), cos_turn(pitch)
    return (-fmul(sp, sin_turn(yaw)), cp, -fmul(sp, cos_turn(yaw)))


def first_quadrant_angle(ax, az):
    """For nonnegative ax and az, bisect the sine table to the first nonnegative cross product."""
    lo, hi = 0, QUARTER
    while lo < hi:
        mid = (lo + hi) >> 1
        if fmul(sin_turn(mid), az) - fmul(cos_turn(mid), ax) < 0:
            lo = mid + 1
        else:
            hi = mid
    return lo


def bearing(dx, dz):
    if dx == 0 and dz == 0:
        return 0
    a = first_quadrant_angle(abs(dx), abs(dz))
    if dx >= 0 and dz >= 0:
        return a
    if dz < 0:
        return 2 * QUARTER - a if dx >= 0 else 2 * QUARTER + a
    return normalize_turn(TURN - a)


def elevation(dy, horizontal):
    """Signed pitch in raw turn units."""
    a = first_quadrant_angle(abs(dy), horizontal)
    return a if dy >= 0 else -a


FNV_OFFSET = 0xcbf29ce484222325
FNV_PRIME = 0x100000001b3
MASK64 = (1 << 64) - 1


class Digest:
    """FNV-1a over 64-bit integers, low byte first; matches ReplayDigest."""
    def __init__(self):
        self.h = FNV_OFFSET

    def mix(self, v):
        x = v & MASK64
        for _ in range(8):
            self.h ^= x & 0xff
            self.h = (self.h * FNV_PRIME) & MASK64
            x >>= 8

    def mix_all(self, values):
        for v in values:
            self.mix(v)

    @property
    def hex(self):
        return format(self.h, 'x')


class Rng:
    """SplitMix64 with wrapping 64-bit arithmetic; matches StadiumCore.Rng."""
    def __init__(self, seed):
        self.state = seed & MASK64

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return z ^ (z >> 31)

    def below(self, n):
        """Requires n > 0."""
        return self.next() % n

    def between(self, lo, hi):
        """Both endpoints are inclusive."""
        return lo + self.below(hi - lo + 1)


def swift_table_literal():
    lines = []
    for i in range(0, len(SIN_Q), 8):
        lines.append('        ' + ', '.join(str(v) for v in SIN_Q[i:i + 8]) + ',')
    return '\n'.join(lines)


def run(args: Namespace, root: Path) -> int:
    if args.table:
        print(swift_table_literal())
    if args.check or not args.table:
        assert sin_turn(0) == 0 and sin_turn(QUARTER) == ONE and sin_turn(2 * QUARTER) == 0 and sin_turn(3 * QUARTER) == -ONE
        assert cos_turn(0) == ONE and cos_turn(QUARTER) == 0 and cos_turn(2 * QUARTER) == -ONE
        assert sin_turn(TURN // 8) == 46341 and sin_turn(-TURN // 8) == -46341
        f, r = forward(0), right(0)
        assert f == (0, 0, ONE) and r == (ONE, 0, 0)
        assert forward(QUARTER) == (ONE, 0, 0) and right(QUARTER) == (0, 0, -ONE)
        assert bearing(0, ONE) == 0 and bearing(ONE, 0) == QUARTER and bearing(0, -ONE) == 2 * QUARTER and bearing(-ONE, 0) == 3 * QUARTER
        assert bearing(ONE, ONE) == TURN // 8 and elevation(-ONE, ONE) == -(TURN // 8)
        worst = 0
        for k in range(0, TURN, 97):
            f = forward(k)
            b = bearing(fmul(f[0], fx(40.0)), fmul(f[2], fx(40.0)))
            worst = max(worst, min(abs(b - k), TURN - abs(b - k)))
        assert worst <= 2, worst
        d = Digest(); d.mix_all([1, -2, 3])
        d2 = Digest(); d2.mix_all([1, -2, 3])
        assert d.hex == d2.hex
        r = Rng(20261022); draws = [r.below(100) for _ in range(5)]
        r2 = Rng(20261022); assert draws == [r2.below(100) for _ in range(5)]
        print('rng first draws', draws)
        print('sin table', len(SIN_Q), 'entries; sin(1/8 turn) =', sin_turn(TURN // 8), '; digest of [1,-2,3] =', d.hex)
    return 0
