"""Build ExplorerFeed.json from the checked-in baseball CSVs."""
import csv
import datetime
import json
from argparse import Namespace
from pathlib import Path

MARLINS = 'Miami Marlins'
HALVES = {'top': 0, 'bottom': 1}


def rows(data: Path, name):
    with (data / name).open(newline='', encoding='utf-8') as fh:
        return list(csv.DictReader(fh))


def boolean(text):
    if text not in ('True', 'False'):
        raise ValueError(f'not a boolean: {text!r}')
    return text == 'True'


def title(date, away, home, away_score, home_score):
    d = datetime.date.fromisoformat(date)
    return f'{d.strftime("%b")} {d.day} · {away} at {home}, {away_score}-{home_score}'


def build(root: Path):
    data = root / 'Apps' / 'Stadium' / 'Data' / 'marlins-2026'
    innings = {}
    for r in rows(data, 'innings.csv'):
        innings.setdefault(r['gamePk'], []).append(
            {'num': int(r['inning']), 'away': int(r['awayRuns']),
             'home': None if r['homeRuns'] == '' else int(r['homeRuns'])})
    errors = {}
    for r in rows(data, 'errors.csv'):
        side = 'home' if r['chargedTeam'] == r['home'] else 'away'
        errors.setdefault(r['gamePk'], []).append({
            'inning': int(r['inning']),
            'half': r['half'],
            'chargedTo': side,
            'team': r['chargedTeam'],
            'fielder': r['fielder'],
            'position': r['position'],
            'kind': r['kind'],
            'batter': r['batter'] or None,
            'consequence': r['consequence'],
            'runScored': boolean(r['runScored']),
            'seasonTotalAfter': int(r['seasonTotalAfter']) if r['seasonTotalAfter'] else None,
            'source': r['source'],
        })
    features = []
    for g in rows(data, 'games.csv'):
        pk = g['gamePk']
        away, home = g['away'], g['home']
        away_score, home_score = int(g['awayScore']), int(g['homeScore'])
        marlins_home = home == MARLINS
        if not marlins_home and away != MARLINS:
            raise ValueError(f'{pk}: the Marlins did not play')
        marlins_runs = home_score if marlins_home else away_score
        opponent_runs = away_score if marlins_home else home_score
        won = boolean(g['marlinsWon'])
        if won != (marlins_runs > opponent_runs):
            raise ValueError(f'{pk}: marlinsWon disagrees with the score')
        line = innings.get(pk, [])
        if [i['num'] for i in line] != list(range(1, len(line) + 1)):
            raise ValueError(f'{pk}: innings out of order')
        if sum(i['away'] for i in line) != away_score or sum(i['home'] or 0 for i in line) != home_score:
            raise ValueError(f'{pk}: the innings do not sum to the score')
        game_errors = sorted(errors.get(pk, []), key=lambda e: (e['inning'], HALVES[e['half']]))
        path = data / 'games' / f'{pk}.json'
        detail = None
        if path.exists():
            with open(path, encoding='utf-8') as fh:
                detail = json.load(fh)
        elif game_errors:
            raise ValueError(f'{pk}: errors without a game file')
        date = g['date']
        d = datetime.date.fromisoformat(date)
        features.append({
            'type': 'Feature',
            'id': pk,
            'geometry': None,
            'properties': {
                'title': title(date, away, home, away_score, home_score),
                'gamePk': int(pk),
                'date': date,
                'month': d.strftime('%B'),
                'dayOfWeek': d.strftime('%A'),
                'away': away,
                'home': home,
                'opponent': away if marlins_home else home,
                'marlinsHome': marlins_home,
                'site': 'home' if marlins_home else 'road',
                'awayScore': away_score,
                'homeScore': home_score,
                'marlinsRuns': marlins_runs,
                'opponentRuns': opponent_runs,
                'runDifferential': marlins_runs - opponent_runs,
                'result': 'W' if won else 'L',
                'marlinsWon': won,
                'awayErrors': int(g['awayErrors']),
                'homeErrors': int(g['homeErrors']),
                'marlinsErrors': int(g['marlinsErrors']),
                'opponentErrors': int(g['opponentErrors']),
                'inningsPlayed': len(line),
                'extraInnings': len(line) > 9,
                'innings': line,
                'boxscore': detail['boxscore'] if detail else None,
                'allPlaysCount': detail['allPlaysCount'] if detail else None,
                'playByPlayComplete': detail['playByPlayComplete'] if detail else None,
                'errors': game_errors,
                'dataNotes': (detail['notes'] if detail else '') or None,
            },
        })
    return {
        'type': 'FeatureCollection',
        'metadata': {
            'title': 'Miami Marlins, 2026 regular season',
            'source': 'MLB Stats API (statsapi.mlb.com), gathered Oct 22 and 23, 2026; Apps/Stadium/Data/marlins-2026',
            'generator': 'python3 python/whaley.py stadium feed',
            'asOf': '2026-10-23',
            'count': len(features),
        },
        'features': features,
    }


def render(document):
    return json.dumps(document, ensure_ascii=False, indent=1, sort_keys=True) + '\n'


def run(args: Namespace, root: Path) -> int:
    text = render(build(root))
    target = root / 'Apps' / 'Stadium' / 'Data' / 'marlins-2026' / 'ExplorerFeed.json'
    if args.write:
        target.write_text(text, encoding='utf-8')
        print(f'{len(text.encode("utf-8"))} bytes -> {target.relative_to(root / "Apps")}')
    if args.check:
        if target.read_text(encoding='utf-8') != text:
            print(f'stale: {target.relative_to(root / "Apps")}')
            return 1
        print('saved feed equals a fresh build')
    if args.summary or not (args.write or args.check):
        doc = json.loads(text)
        fs = doc['features']
        print(f"{len(fs)} games, {sum(len(f['properties']['errors']) for f in fs)} errors, "
              f"{sum(1 for f in fs if f['properties']['boxscore'])} with a box score, "
              f"{sum(1 for f in fs if f['properties']['extraInnings'])} extra-inning games")
        print(json.dumps(fs[0], ensure_ascii=False, indent=1, sort_keys=True))
    return 0
