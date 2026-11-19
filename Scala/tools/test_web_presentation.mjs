#!/usr/bin/env node
// Observe the real shared assets/text through Play, including draw ordering.
import assert from 'node:assert/strict';
import { openGame, readFrame, images, logicalImage, close, captureFrames,
  bitmapCharacters, drawnText, clickLogical, scene } from './test_web.mjs';

const { browser, page, errors } = await openGame();
try {
  const characters = await bitmapCharacters();
  const names = ['DRYDOCK AT LIVERPOOL', 'THE CREATION', 'IN THE OMNIBUS',
    'LAS MENINAS', 'THE SCAPEGOAT', 'PEARL EARRING'];
  for (let number = 1; number <= 6; number += 1) {
    const frames = await captureFrames(page, () => page.keyboard.press(String(number)));
    const first = frames.find(frame => frame.scene === 'game');
    assert.ok(first, `level ${number} must render`);
    assert.equal(drawnText(first, characters), names[number - 1].replaceAll(' ', ''),
      'the current painting title is the only initial HUD text');
    await page.clock.runFor(600);
    const frame = await readFrame(page);
    assert.equal(frame.systemText, 0, 'game text must use original bitmap glyphs');
    const paintingPage = `level${number}-568h.png`;
    const paintings = images(frame, paintingPage);
    assert.equal(paintings.length, 1, 'exactly one gameplay painting fills the screen');
    const painting = paintings[0];
    assert.deepEqual(painting.source, [0, 0, 320, 568],
      'gameplay uses the complete tall painting variant');
    const bounds = logicalImage(painting, frame);
    close(bounds.x, 160, 'painting center x');
    close(bounds.y, 284, 'painting center y');
    close(bounds.width, 320, 'painting width');
    close(bounds.height, 568, 'painting height');
    close(painting.alpha, 190 / 255, 'original gameplay painting opacity');
    const tiles = frame.images.filter(image => /^tileset.*\.png$/.test(image.asset));
    assert.ok(tiles.length > 0, 'TMX Background tiles remain visible over the painting');
    assert.ok(tiles.every(tile => tile.order > painting.order), 'the painting must be behind every tile');
    assert.ok(images(frame, 'game_font.png').every(glyph => glyph.alpha === 1), 'HUD glyphs do not fade');

    const scanlines = images(frame, 'scanlines-568h.png');
    assert.equal(scanlines.length, number <= 2 ? 1 : 0, 'scanlines only cover the two original dry levels');
    if (scanlines.length) assert.ok(scanlines[0].order > images(frame, 'game_font.png').at(-1).order);
    const water = frame.fills.filter(fill => fill.color === '#6666ff');
    assert.equal(water.length, number >= 4 ? 1 : 0, 'only original water levels have the blue overlay');
    if (water.length) {
      close(water[0].alpha, 128 / 255, 'original water alpha');
      assert.ok(water[0].order > images(frame, 'game_font.png').at(-1).order);
    }
    if (number === 2 || number === 5) {
      const strip = frame.fills.find(fill => {
        const rect = logicalImage(fill, frame);
        return fill.color === '#000000' && Math.abs(rect.y - 556) < 1e-5 && Math.abs(rect.height - 24) < 1e-5;
      });
      assert.ok(strip, 'the short horizontal map retains its original black bottom strip');
      close(frame.viewport.width / frame.viewport.height, 320 / 568, 'short maps do not shrink the full-height painting');
    }
    if (number === 2) {
      assert.ok(tiles.every(tile => tile.asset === 'tileset.png' && tile.source[1] === 2 &&
        tile.source[2] === 32 && tile.source[3] === 32 && [2, 36].includes(tile.source[0])),
      'level two must use original margin/spacing crop rectangles');
    }
  }

  await page.keyboard.press('1');
  await page.clock.runFor(600);
  await clickLogical(page, 160, 16);
  await page.clock.runFor(40);
  const paused = await readFrame(page);
  assert.equal(await page.locator('#game').getAttribute('data-paused'), 'true');
  assert.equal(drawnText(paused, characters), 'QUITCONTINUE', 'pause adds only the two original top-bar labels');
  const icons = images(paused, 'player.png').filter(image => logicalImage(image, paused).width < 20);
  assert.equal(icons.length, 2);
  close(logicalImage(icons[0], paused).x, 12, 'QUIT icon original position');
  assert.equal(icons[0].tint, '#ff0000');
  assert.ok(icons[0].matrix[3] < 0, 'QUIT whale is vertically flipped');
  close(logicalImage(icons[1], paused).x, 180, 'CONTINUE icon follows measured text width');
  await clickLogical(page, 40, 16);
  assert.equal(await scene(page), 'gallery', 'QUIT is actionable in the original top bar');
  assert.deepEqual(errors, []);
  console.log('PASS: current painting titles and original pause text, six tall painting variants behind TMX tiles, source opacities, scanlines/water/bottom masks and original QUIT controls.');
} finally { await browser.close(); }
