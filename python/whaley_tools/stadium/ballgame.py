"""Reference for BallgameCore using the checked-in season CSVs.

Half-innings share a compressed duration; runs accrue at each half's end and
errors are evenly spaced within their recorded half. Integer results must match Swift."""
import csv
import json
from argparse import Namespace
from pathlib import Path
from .math import Digest

TOP, BOTTOM = 0, 1
MARLINS = 'Miami Marlins'
KINDS = ['throwing', 'fielding', 'pickoff', 'missed catch', 'catcher interference', 'dropped foul', 'interference']
POSITIONS = ['P', 'C', '1B', '2B', '3B', 'SS', 'LF', 'CF', 'RF']


def load_season(root: Path):
    """Load games by date, with errors ordered by inning and half."""
    data = root / 'Apps' / 'Stadium' / 'Data' / 'marlins-2026'

    def rows(name):
        with (data / name).open(newline='', encoding='utf-8') as stream:
            return list(csv.DictReader(stream))

    games = {}
    for r in rows('games.csv'):
        games[r['gamePk']] = dict(gamePk=int(r['gamePk']), date=r['date'], away=r['away'], home=r['home'],
                                  awayScore=int(r['awayScore']), homeScore=int(r['homeScore']), innings=[], errors=[])
    for r in rows('innings.csv'):
        g = games[r['gamePk']]
        g['innings'].append([int(r['awayRuns']), -1 if r['homeRuns'] == '' else int(r['homeRuns'])])
    for r in rows('errors.csv'):
        g = games[r['gamePk']]
        g['errors'].append(dict(inning=int(r['inning']), half=TOP if r['half'] == 'top' else BOTTOM,
                                chargedToHome=r['chargedTeam'] == r['home'],
                                fielder=r['fielder'], position=POSITIONS.index(r['position']) if r['position'] in POSITIONS else -1,
                                kind=KINDS.index(r['kind']), runScored=r['runScored'] == 'True'))
    for g in games.values():
        g['errors'].sort(key=lambda e: (e['inning'], e['half']))
    return [games[k] for k in sorted(games, key=lambda k: games[k]['date'])]


def halves(record):
    """Return played halves as (inning, half, runs); negative home runs mean unplayed."""
    out = []
    for i, (a, h) in enumerate(record['innings'], start=1):
        out.append((i, TOP, a))
        if h >= 0:
            out.append((i, BOTTOM, h))
    return out


def score_before(record, index):
    """Return (away, home) before the indexed half."""
    away = home = 0
    for inning, half, runs in halves(record)[:max(0, index)]:
        if half == TOP:
            away += runs
        else:
            home += runs
    return away, home


def half_index(record, inning, half):
    """Return -1 when the half was not played."""
    for i, (inn, h, _) in enumerate(halves(record)):
        if inn == inning and h == half:
            return i
    return -1


PARAMS = dict(halfInningTicks=140, breakTicks=20)

H_START, H_ERROR, H_RUNS, H_FINAL, H_END = 0, 1, 2, 3, 5   # Codes 4 and 6 are reserved for retired events.


class Ballgame:
    def __init__(self, record, p=PARAMS):
        self.record = record
        self.p = p
        self.halves = halves(record)
        self.tick = 0
        self.halfIndex = 0
        self.ticksIntoHalf = 0
        self.awayScore = 0
        self.homeScore = 0
        self.over = False
        self.firedErrors = 0
        self.errorsThisHalf = 0
        self.fast_forward(p.get('startHalf', 0), p.get('startTick', 0))

    def fast_forward(self, half_index, k):
        """Credit runs and errors exactly as a replay from the first pitch would."""
        if half_index == 0 and k == 0:
            return
        for i in range(half_index + 1):
            inning, half, runs = self.halves[i]
            played = i < half_index or k > self.p['halfInningTicks'] - 1
            if played:
                if half == TOP:
                    self.awayScore += runs
                else:
                    self.homeScore += runs
            errs = self.errors_of(inning, half)
            n = len(errs)
            for j in range(n):
                if i < half_index or (j + 1) * self.p['halfInningTicks'] // (n + 1) < k:
                    self.firedErrors += 1
                    if i == half_index:
                        self.errorsThisHalf += 1
        self.halfIndex = half_index
        self.ticksIntoHalf = k

    def errors_of(self, inning, half):
        return [e for e in self.record['errors'] if e['inning'] == inning and e['half'] == half]

    def in_play(self):
        return not self.over and self.ticksIntoHalf < self.p['halfInningTicks']

    def step(self):
        """Event payloads: start(inning, half), error(index, inning, half, home, runScored),
        runs(team, count, inning, half), final(away, home), end(inning, half, errors).
        Teams use 0 = away, 1 = home."""
        t = self.tick
        events = []
        if not self.over:
            inning, half, runs = self.halves[self.halfIndex]
            length = self.p['halfInningTicks'] + self.p['breakTicks']
            k = self.ticksIntoHalf
            if k == 0:
                events.append(('start', inning, half))
                self.errorsThisHalf = 0
            errs = self.errors_of(inning, half)
            n = len(errs)
            for j, e in enumerate(errs):
                if k == (j + 1) * self.p['halfInningTicks'] // (n + 1):
                    index = self.record['errors'].index(e)
                    events.append(('error', index, inning, half, 1 if e['chargedToHome'] else 0, 1 if e['runScored'] else 0))
                    self.firedErrors += 1
                    self.errorsThisHalf += 1
            if k == self.p['halfInningTicks'] - 1:
                if half == TOP:
                    self.awayScore += runs
                else:
                    self.homeScore += runs
                if runs > 0:
                    events.append(('runs', 1 if half == BOTTOM else 0, runs, inning, half))
            if k == length - 1:
                events.append(('end', inning, half, self.errorsThisHalf))
                self.halfIndex += 1
                self.ticksIntoHalf = 0
                if self.halfIndex == len(self.halves):
                    self.over = True
                    events.append(('final', self.awayScore, self.homeScore))
            else:
                self.ticksIntoHalf += 1
        self.tick += 1
        return events

    def inning(self):
        if self.over:
            return self.halves[-1][0], self.halves[-1][1]
        return self.halves[self.halfIndex][0], self.halves[self.halfIndex][1]

    def digest_tick(self, digest, t, events):
        inning, half = self.inning()
        digest.mix_all([t, self.halfIndex, self.ticksIntoHalf, inning, half, self.awayScore, self.homeScore, 1 if self.over else 0, len(events)])
        for e in events:
            if e[0] == 'start': digest.mix_all([H_START, e[1], e[2]])
            elif e[0] == 'error': digest.mix_all([H_ERROR, e[1], e[2], e[3], e[4], e[5]])
            elif e[0] == 'runs': digest.mix_all([H_RUNS, e[1], e[2], e[3], e[4]])
            elif e[0] == 'final': digest.mix_all([H_FINAL, e[1], e[2]])
            elif e[0] == 'end': digest.mix_all([H_END, e[1], e[2], e[3]])


def swift_table(season):
    lines = ['// Generated by python3 python/whaley.py stadium ballgame --table; do not edit by hand.', '',
             'public enum Season2026 {',
             '    public static let games: [BallgameRecord] = [']
    for g in season:
        innings = ', '.join(f'[{a}, {h}]' for a, h in g['innings'])
        errors = ', '.join(f'ErrorRecord(inning: {e["inning"]}, half: {e["half"]}, chargedToHome: {"true" if e["chargedToHome"] else "false"}, '
                           f'fielder: {json.dumps(e["fielder"], ensure_ascii=False)}, position: {e["position"]}, kind: {e["kind"]}, '
                           f'runScored: {"true" if e["runScored"] else "false"})' for e in g['errors'])
        lines.append(f'        BallgameRecord(gamePk: {g["gamePk"]}, date: "{g["date"]}", away: {json.dumps(g["away"])}, home: {json.dumps(g["home"])}, '
                     f'awayScore: {g["awayScore"]}, homeScore: {g["homeScore"]}, innings: [{innings}], errors: [{errors}]),')
    lines += ['    ]', '}', '']
    return '\n'.join(lines)


def simulate(record, ticks, p=PARAMS):
    game = Ballgame(record, p)
    digest = Digest()
    log = []
    samples = []
    for t in range(ticks):
        events = game.step()
        for e in events:
            log.append((t,) + e)
        game.digest_tick(digest, t, events)
        if t % 10 == 0:
            inning, half = game.inning()
            samples.append([t, game.halfIndex, game.ticksIntoHalf, inning, half, game.awayScore, game.homeScore, 1 if game.over else 0])
    return dict(samples=samples, events=[list(e) for e in log], awayScore=game.awayScore, homeScore=game.homeScore,
                over=game.over, firedErrors=game.firedErrors, digest=digest.hex)


def run(args: Namespace, root: Path) -> int:
    season = load_season(root)
    if args.table:
        args.table.write_text(swift_table(season), encoding='utf-8')
        print(f'{len(season)} games, {sum(len(g["errors"]) for g in season)} errors, {sum(len(halves(g)) for g in season)} half-innings -> {args.table}')
    if args.fixtures:
        out = args.fixtures
        out.mkdir(parents=True, exist_ok=True)
        with (out / 'season-2026.json').open('w', encoding='utf-8') as fh:
            json.dump(dict(games=season), fh, ensure_ascii=False)
        chosen = next(g for g in season if g['gamePk'] == 823884)
        fixture = dict(parameters=PARAMS, gamePk=chosen['gamePk'], ticks=3000, run=simulate(chosen, 3000))
        with (out / 'ballgame-823884.json').open('w', encoding='utf-8') as fh:
            json.dump(fixture, fh)
        r = fixture['run']
        print(f"season: {len(season)} games; game 823884: final {r['awayScore']}-{r['homeScore']} over {r['over']}, {r['firedErrors']} errors fired, digest {r['digest']}")
    if args.report or not (args.table or args.fixtures):
        chosen = next(g for g in season if g['gamePk'] == 823884)
        r = simulate(chosen, 3000)
        print(f"{chosen['date']} {chosen['away']} at {chosen['home']}: {len(halves(chosen))} halves, final {r['awayScore']}-{r['homeScore']}, digest {r['digest']}")
        for e in r['events']:
            print('   ', e)
        assert r == simulate(chosen, 3000)
        print('the score before the bottom of the 7th:', score_before(chosen, half_index(chosen, 7, BOTTOM)))
        totals = [sum(1 for g in season if len(halves(g)) == n) for n in range(17, 25)]
        print('halves played, 17 to 24:', totals, '; games with an unplayed bottom:', sum(1 for g in season if g['innings'][-1][1] < 0))
    return 0
