#!/usr/bin/env node
// Real gallery gestures and read-only draw observations; no game-state hook.
import assert from 'node:assert/strict';
import { openGame, readFrame, images, canvasPoint, clickLogical, scene, close,
  captureFrames, levelFixture } from './test_web.mjs';

const { browser, page, errors } = await openGame();
try {
  const level = await levelFixture(page, 1);
  const frame = async () => {
    const output = await readFrame(page);
    assert.ok(output.viewport);
    const scale = output.viewport.width / 320;
    // Gallery commands rotate around an absolute pivot. Recover the original
    // rectangle before rotation from the actual translation and source quad.
    output.images = output.images.map(image => {
      const [a, b, , , e, f] = image.matrix;
      const [x, y, width, height] = image.destination;
      const pivot = { x: (e - output.viewport.x) / scale, y: (f - output.viewport.y) / scale };
      return { ...image, pivot, logical: { x: pivot.x + x, y: pivot.y + y, width, height },
        rotation: Math.atan2(b, a) * 180 / Math.PI };
    });
    return output;
  };
  const move = async (x, y) => { const p = await canvasPoint(page, x, y); await page.mouse.move(p.x, p.y); };
  const click = (x, y) => clickLogical(page, x, y);
  const preview = output => images(output, 'level1-568h.png');
  const g = output => images(output, 'title_font.png').find(image => image.source[0] === 351 && image.source[1] === 110);
  const assertCleanStart = frames => {
    const first = frames.find(output => output.scene === 'game');
    assert.ok(first);
    assert.equal(images(first, 'bubble01.png').length, level.bubbles.length,
      'the gallery release must leave only the original seeded bubbles in the first game frame');
  };

  assert.equal(await scene(page), 'gallery');
  let output = await frame();
  assert.equal(images(output, 'frame.png').length, 6);
  assert.deepEqual(output.images.filter(image => /^level\d+\.png$/.test(image.asset)).map(image => image.asset),
    ['level1.png'], 'fresh progress paints only the first unlocked level');
  assert.equal(images(output, 'title_font.png').length, 9);
  assert.equal(output.systemText, 0);
  const titleG = g(output);
  assert.ok(titleG);
  close(titleG.logical.x, 32, 'G preserves fixed title origin x');
  close(titleG.logical.y, 44, 'G preserves fixed title origin y');
  close(titleG.logical.width, 50, 'G retains original glyph width');
  close(titleG.alpha, 1, 'title entrance completes');
  const firstFrame = images(output, 'frame.png')[0];
  close(firstFrame.logical.x, 36.8, 'first frame x');
  close(firstFrame.logical.y, 144, 'first frame top');
  close(firstFrame.logical.width, 68.8, 'frame width');
  close(firstFrame.logical.height, 102.8, 'frame height');
  close(firstFrame.pivot.y, 246.8, 'frame rotates about its bottom-left');
  const painting = images(output, 'level1.png')[0];
  close(painting.logical.width, 40, 'painting aperture width');
  close(painting.logical.height, 60, 'painting aperture height');
  assert.ok(painting.order < firstFrame.order, 'frame is drawn over the painting');
  const rewards = images(output, 'bubble01.png');
  assert.equal(rewards.length, 1, 'the interpunct is one actual puzzle reward');
  assert.equal(rewards[0].tinted, true);
  assert.equal(rewards[0].tint, '#d31895', 'reward uses the original magenta');
  close(rewards[0].logical.x, 133, 'interpunct left');
  close(rewards[0].logical.y, 56, 'interpunct top');
  close(rewards[0].alpha, 150 / 255, 'original reward alpha');

  const rotations = images(output, 'frame.png').map(image => image.rotation);
  await click(141, 64);
  await page.clock.runFor(50);
  output = await frame();
  assert.equal(images(output, 'bubble01.png').length, 0);
  assert.deepEqual(images(output, 'frame.png').map(image => image.rotation), rotations,
    'popping the reward cannot also knock the frames');
  await click(50, 90);
  await page.clock.runFor(50);
  assert.ok(images(await frame(), 'dust.png').some(image => image.blend === 'lighter'));
  await page.clock.runFor(200);
  close(g(await frame()).alpha, 100 / 255, 'touched letter retains its chalk alpha');
  assertCleanStart(await captureFrames(page, () => click(71, 195)));
  assert.equal(await scene(page), 'game');
  await page.keyboard.press('m');
  await page.clock.runFor(200);
  assert.equal(await scene(page), 'gallery');
  close(g(await frame()).alpha, 100 / 255, 'chalk persists on returning from gameplay');

  await move(71, 195);
  await page.mouse.down();
  await page.clock.runFor(900);
  assert.equal(preview(await frame()).length, 0, 'preview cannot appear before one second');
  await page.clock.runFor(250);
  assert.equal(preview(await frame()).length, 1);
  await page.mouse.up();
  await page.clock.runFor(50);
  assert.equal(preview(await frame()).length, 1, 'release preserves an open preview');
  await click(71, 195);
  await page.clock.runFor(150);
  assert.equal(preview(await frame()).length, 0);
  assert.equal(await scene(page), 'gallery', 'the dismiss tap cannot launch the painting');

  await move(71, 195);
  await page.mouse.down();
  await page.clock.runFor(700);
  await move(-8, 195);
  await page.clock.runFor(700);
  assert.equal(preview(await frame()).length, 0, 'leaving the fitted surface clears the hold deadline');
  await move(71, 195);
  await page.clock.runFor(700);
  assert.equal(preview(await frame()).length, 0, 're-entry starts a full new hold');
  await page.clock.runFor(400);
  assert.equal(preview(await frame()).length, 1, 'captured movement can re-enter and preview');
  await page.mouse.up();
  await click(71, 195);
  await page.clock.runFor(150);

  await move(71, 195);
  await page.mouse.down();
  await page.clock.runFor(800);
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  await page.clock.runFor(1400);
  assert.equal(preview(await frame()).length, 0, 'focus loss cancels the pending hold');
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await page.mouse.up();
  await page.clock.runFor(50);
  assert.equal(await scene(page), 'gallery', 'release after cancellation cannot start a level');
  assertCleanStart(await captureFrames(page, () => page.keyboard.press('Enter')));
  assert.equal(await scene(page), 'game', 'the accessible keyboard action starts the unlocked level');
  assert.deepEqual(errors, []);
  console.log('PASS: original gallery geometry, fixed title origin, single tinted reward, persistent chalk, previews, captured re-entry, focus cancellation and clean pointer/keyboard level starts.');
} finally { await browser.close(); }

// Restore ordinary unlocked progress through the real saved-record format.
// No game-state hook is needed to inspect the three replacement paintings.
const unlocked = await openGame({ seed: 'whaley-progress|1\n6|false|false' });
try {
  for (const [number, x, y] of [
    [2, 160, 195], [3, 249, 195], [5, 160, 313]
  ]) {
    const name = `level${number}.png`;
    const previewName = `level${number}-568h.png`;
    const card = images(await readFrame(unlocked.page), name);
    assert.equal(card.length, 1);
    assert.deepEqual(card[0].source, [0, 0, 320, 480]);
    assert.deepEqual(card[0].destination.slice(2), [40, 60]);
    const point = await canvasPoint(unlocked.page, x, y);
    await unlocked.page.mouse.move(point.x, point.y);
    await unlocked.page.mouse.down();
    await unlocked.page.clock.runFor(1150);
    const painting = images(await readFrame(unlocked.page), previewName);
    assert.equal(painting.length, 1, 'the preview uses its tall painting variant');
    assert.deepEqual(painting[0].source, [0, 0, 320, 568]);
    assert.deepEqual(painting[0].destination.slice(2), [320, 568]);
    await unlocked.page.mouse.up();
    await clickLogical(unlocked.page, x, y);
    await unlocked.page.clock.runFor(150);
    assert.equal(await scene(unlocked.page), 'gallery');
    assert.ok(unlocked.resources.has(name));
    assert.ok(unlocked.resources.has(previewName));
    assert.ok(!unlocked.resources.has(`level${number}.jpg`));
  }
  assert.deepEqual(unlocked.errors, []);
  console.log('PASS: standard painting cards and tall previews for levels 2, 3 and 5.');
} finally { await unlocked.browser.close(); }
