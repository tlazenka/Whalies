"""Keep the relocated reference tools aligned with the native golden files."""
from argparse import Namespace
from contextlib import redirect_stdout
import csv
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from whaley_tools.stadium import ballgame, crowd, feed, kart, math


ROOT = Path(__file__).resolve().parents[2]
STADIUM = ROOT / 'Apps' / 'Stadium'


class StadiumToolsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)

    def invoke(self, module, root=ROOT, **options):
        with redirect_stdout(io.StringIO()):
            return module.run(Namespace(**options), root)

    def test_original_arithmetic_self_checks(self):
        self.assertEqual(self.invoke(math, check=True, table=False), 0)

    def test_season_source_and_ballgame_fixtures_match_native_goldens(self):
        table = self.output / 'Season2026.swift'
        self.assertEqual(self.invoke(ballgame, table=table, fixtures=self.output, report=False), 0)
        self.assertEqual(table.read_bytes(), (STADIUM / 'Sources/BallgameCore/Season2026.swift').read_bytes())
        for filename in ('season-2026.json', 'ballgame-823884.json'):
            with self.subTest(filename=filename):
                self.assertEqual((self.output / filename).read_bytes(),
                                 (STADIUM / 'Tests/BallgameCoreTests/Fixtures' / filename).read_bytes())

    def test_crowd_fixture_matches_native_golden(self):
        self.assertEqual(self.invoke(crowd, fixtures=self.output, report=False), 0)
        self.assertEqual((self.output / 'crowd.json').read_bytes(),
                         (STADIUM / 'Tests/CrowdCoreTests/Fixtures/crowd.json').read_bytes())

    def test_both_kart_models_match_native_golden(self):
        self.assertEqual(self.invoke(kart, fixtures=self.output, report=False,
                                     ascii=False, model='b', every=60), 0)
        self.assertEqual((self.output / 'ring-3600.json').read_bytes(),
                         (STADIUM / 'Tests/WhaleKartCoreTests/Fixtures/ring-3600.json').read_bytes())

    def test_feed_writes_and_checks_only_the_selected_repository(self):
        data = self.output / 'Apps/Stadium/Data/marlins-2026'
        (data / 'games').mkdir(parents=True)
        original = STADIUM / 'Data/marlins-2026'
        for name in ('games.csv', 'innings.csv', 'errors.csv'):
            with (original / name).open(newline='', encoding='utf-8') as source:
                records = csv.DictReader(source)
                with (data / name).open('w', newline='', encoding='utf-8') as target:
                    writer = csv.DictWriter(target, fieldnames=records.fieldnames)
                    writer.writeheader()
                    writer.writerows(row for row in records if row['gamePk'] == '823884')
        shutil.copyfile(original / 'games/823884.json', data / 'games/823884.json')

        self.assertEqual(self.invoke(feed, root=self.output, write=True, check=False, summary=False), 0)
        target = data / 'ExplorerFeed.json'
        document = json.loads(target.read_text(encoding='utf-8'))
        self.assertEqual(document['metadata']['count'], 1)
        self.assertEqual(document['metadata']['generator'], 'python3 python/whaley.py stadium feed')
        self.assertEqual(document['features'][0]['properties']['gamePk'], 823884)
        self.assertEqual(self.invoke(feed, root=self.output, write=False, check=True, summary=False), 0)

        target.write_text('{}', encoding='utf-8')
        self.assertEqual(self.invoke(feed, root=self.output, write=False, check=True, summary=False), 1)
