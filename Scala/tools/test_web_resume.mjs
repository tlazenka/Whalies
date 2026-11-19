#!/usr/bin/env node
// Exercise actual localStorage loading/writes and real checkpoint restoration.
// Only the public, validated persistence format is seeded; no live app state
// is injected. Positions and expected remaining coins come from original TMX.
import assert from 'node:assert/strict';
import { openGame, ready, readFrame, images, logicalImage, close, captureFrames,
  levelFixture, bitmapCharacters, drawnText, clickLogical, scene, storedProgress } from './test_web.mjs';

const seed = [
  'whaley-progress|1', '1|false|false',
  'whaley-checkpoint|1|1|ExtraBounce|28|480|9|0,1,28',
  'whaley-checkpoint|1|4|Normal|1|300|5|0,1'
].join('\n');

function decode(raw) {
  assert.ok(raw, 'application must retain its versioned progress record');
  const [prefix, settings, ...records] = raw.split('\n');
  assert.equal(prefix, 'whaley-progress|1');
  const [achieved, reward, invincible] = settings.split('|');
  return { achieved: Number(achieved), reward: reward === 'true', invincible: invincible === 'true',
    checkpoints: new Map(records.map(record => {
      const [kind, version, number, mode, last, ticks, used, ids] = record.split('|');
      assert.equal(kind, 'whaley-checkpoint');
      assert.equal(version, '1');
      return [Number(number), { mode, last: Number(last), ticks: Number(ticks), used: Number(used),
        ids: ids.split(',').map(Number) }];
    })) };
}

function verifyPlacement(frame, fixture, checkpoint, characters, title) {
  assert.ok(frame?.viewport, 'the first restored scene must draw');
  const center = checkpoint ? fixture.coins[checkpoint.last]
    : { x: fixture.spawn.x + 16, y: fixture.spawn.y + 16 };
  assert.ok(center, 'checkpoint must reference a real original coin');
  const collected = new Set(checkpoint?.ids ?? []);
  const left = Math.min(Math.max(center.x - 160, 0), fixture.width - 320);
  const bottom = Math.min(Math.max(center.y - 284, 0), fixture.height - 568);
  const expectedPoint = point => ({ x: point.x - left, y: 568 - point.y + bottom });
  const player = images(frame, 'player.png').find(image => logicalImage(image, frame).width > 20);
  assert.ok(player, 'restored player must be drawn from the original atlas');
  const observed = logicalImage(player, frame);
  const expected = expectedPoint(center);
  close(observed.x, expected.x, 'restored player x from checkpoint coin');
  close(observed.y, expected.y, 'restored player y with the original camera');
  close(observed.width, 32, 'restored player size');

  const key = point => `${point.x.toFixed(5)},${point.y.toFixed(5)}`;
  const expectedCoins = fixture.coins.filter((point, id) => !collected.has(id) &&
    point.x + 16 >= left && point.x - 16 <= left + 320 &&
    point.y + 16 >= bottom && point.y - 16 <= bottom + 568).map(point => key(expectedPoint(point))).sort();
  const actualCoins = images(frame, 'coin.png').map(image => logicalImage(image, frame))
    .filter(image => image.width > 20).map(key).sort();
  assert.deepEqual(actualCoins, expectedCoins,
    'restoration must remove collected coins while preserving every other visible original coin');
  assert.equal(drawnText(frame, characters), checkpoint ? `x${collected.size}` : title.replaceAll(' ', ''),
    'the original HUD reflects the restored collectible count');
}

const { browser, page, errors } = await openGame({ seed });
try {
  const characters = await bitmapCharacters();
  const firstLevel = await levelFixture(page, 1);
  const fourthLevel = await levelFixture(page, 4);
  assert.ok(firstLevel.coins.length > 31, 'the original nearby-coin checkpoint fixture must exist');
  const initial = decode(seed);
  const reload = async () => {
    await page.reload({ waitUntil: 'networkidle' });
    await ready(page);
    await page.clock.runFor(250);
    assert.equal(await scene(page), 'gallery');
  };
  const start = async number => {
    const frames = await captureFrames(page, () => page.keyboard.press(String(number)));
    const first = frames.find(frame => frame.scene === 'game');
    assert.ok(first);
    return first;
  };

  // The two persisted practice checkpoints make their levels reachable,
  // without falsely claiming the final game-completion title/reward.
  assert.equal(await page.title(), 'Gray Whale');
  assert.equal(images(await readFrame(page), 'level4.png').length, 1);
  const invincibility = page.getByRole('switch', { name: 'Invincibility', exact: true });
  const checked = () => invincibility.getAttribute('aria-checked');
  assert.equal(await checked(), 'false');
  await invincibility.click();
  assert.equal(await checked(), 'true');
  assert.equal(decode(await storedProgress(page)).invincible, true);
  assert.equal(await page.locator('#game').getAttribute('data-invincible'), 'true');
  assert.equal(await scene(page), 'gallery', 'toggling the star must not open a submenu');
  await page.keyboard.press('Space');
  assert.equal(await checked(), 'false', 'Space activates the focused switch exactly once');
  await page.keyboard.press('Enter');
  assert.equal(await checked(), 'true', 'Enter activates the focused switch exactly once');
  assert.equal(await scene(page), 'gallery', 'Enter on the switch must not also start a level');
  await page.keyboard.down('i');
  await page.keyboard.down('i');
  await page.keyboard.up('i');
  assert.equal(await checked(), 'false', 'holding I must not repeatedly toggle invincibility');
  await page.keyboard.press('Control+i');
  assert.equal(await checked(), 'false', 'modified shortcuts are left to the browser');
  await page.keyboard.press('F1');
  assert.equal(await checked(), 'true', 'F1 toggles directly without a submenu');
  await reload();
  assert.equal(await checked(), 'true', 'invincibility must survive a full document reload');

  // Key 1 normally requests Normal mode; a real saved checkpoint retains its
  // ExtraBounce mode. Inspect the first frame before simulation advances.
  verifyPlacement(await start(1), firstLevel, initial.checkpoints.get(1), characters, 'DRYDOCK AT LIVERPOOL');
  await invincibility.click();
  assert.equal(await checked(), 'false');
  await page.keyboard.press('Space');
  assert.equal(await checked(), 'true');
  assert.equal(await page.locator('#game').getAttribute('data-paused'), 'false',
    'clicking the star or pressing Space on it must not pause gameplay');
  await page.clock.runFor(100);
  const earned = decode(await storedProgress(page)).checkpoints.get(1);
  assert.ok(earned.ids.length > initial.checkpoints.get(1).ids.length,
    'the simulation must keep advancing after a star toggle, collect a neighboring coin and save');
  assert.ok([0, 1, 28].every(id => earned.ids.includes(id)));
  assert.ok(earned.ticks > 480 && earned.ticks < 510, 'new coin save continues restored elapsed ticks');
  assert.equal(earned.used, 9, 'new coin save retains the restored bubble counter');
  assert.equal(earned.mode, 'ExtraBounce', 'new save reflects the restored gameplay mode');
  assert.equal(drawnText(await readFrame(page), characters), `x${earned.ids.length}`);

  const current = await readFrame(page);
  const center = logicalImage(images(current, 'player.png')[0], current);
  await clickLogical(page, center.x + 55, center.y + 55);
  await page.clock.runFor(40);
  assert.ok(images(await readFrame(page), 'bubble01.png').some(image => image.tint === '#d31895'),
    'a real shot uses the saved ExtraBounce mode after the normal-mode hotkey');
  const persisted = decode(await storedProgress(page));
  await reload();
  verifyPlacement(await start(1), firstLevel, persisted.checkpoints.get(1), characters, 'DRYDOCK AT LIVERPOOL');
  assert.equal(decode(await storedProgress(page)).invincible, true);

  const restarted = (await captureFrames(page, () => page.keyboard.press('r')))[0];
  verifyPlacement(restarted, firstLevel, undefined, characters, 'DRYDOCK AT LIVERPOOL');
  const cleared = decode(await storedProgress(page));
  assert.equal(cleared.checkpoints.has(1), false, 'explicit restart removes this level checkpoint');
  assert.deepEqual(cleared.checkpoints.get(4), initial.checkpoints.get(4), 'restart preserves another level save');
  await reload();
  verifyPlacement(await start(1), firstLevel, undefined, characters, 'DRYDOCK AT LIVERPOOL');
  verifyPlacement(await start(4), fourthLevel, initial.checkpoints.get(4), characters, 'LAS MENINAS');
  await clickLogical(page, 160, 16);
  await page.clock.runFor(40);
  await clickLogical(page, 40, 16);
  assert.equal(await scene(page), 'gallery');
  assert.equal(decode(await storedProgress(page)).checkpoints.has(4), false, 'original QUIT removes the current checkpoint');
  await reload();
  const final = decode(await storedProgress(page));
  assert.equal(final.checkpoints.size, 0);
  assert.equal(final.invincible, true);
  assert.equal(final.achieved, 4, 'clearing attempts retains unlocked gallery progress');
  assert.equal(images(await readFrame(page), 'level4.png').length, 1);
  assert.deepEqual(errors, []);
  console.log('PASS: real TMX checkpoint restoration, collected-coin removal/player placement, retained counters and mode through a new coin save, persistent star toggle without pausing, keyboard switch activation, restart/QUIT clearing and independent level progress.');
} finally { await browser.close(); }
