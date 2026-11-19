#!/usr/bin/env node
/** Real linked Scala.js application served by Play; no replacement game model.
 * Run after starting Play/PostgreSQL: npm ci; npx playwright install chromium;
 * npm test. WHALEY_BROWSER_URL and WHALEY_BROWSER_EXECUTABLE are optional.
 * The exported helpers observe native drawing/audio calls and are also used by
 * the focused regressions. Importing this file does not launch its smoke test.
 */
import assert from 'node:assert/strict';
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { chromium } from 'playwright';

export const portRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const progressKey = 'whaley.progress.v1';
export const gameURL = process.env.WHALEY_BROWSER_URL ?? 'http://127.0.0.1:9000/';

export async function openGame({ seed, hasTouch = false } = {}) {
  const browser = await chromium.launch({
    headless: true, executablePath: process.env.WHALEY_BROWSER_EXECUTABLE || undefined
  });
  try {
    const context = await browser.newContext({
      viewport: { width: 1100, height: 900 }, deviceScaleFactor: 2, hasTouch
    });
    const page = await context.newPage();
    const errors = [];
    const resources = new Set();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {
      if (message.type() === 'error' || message.text().startsWith('Whaley audio:')) errors.push(message.text());
    });
    page.on('requestfailed', request => {
      const failure = request.failure()?.errorText;
      // Navigation and pausing a streaming track may deliberately cancel it.
      if (failure !== 'net::ERR_ABORTED') errors.push(`${request.url()}: ${failure}`);
    });
    page.on('response', response => {
      if (response.status() >= 400) errors.push(`${response.status()} ${response.url()}`);
      else resources.add(new URL(response.url()).pathname.split('/').pop());
    });
    await page.addInitScript(() => {
      const observed = window.__whaleyObserved = {
        current: null, capture: false, frames: [],
        audio: { starts: [], stops: [], plays: [], pauses: [], decoded: [], contexts: [], media: [] }
      };
      const colors = new WeakMap();
      const bufferFiles = new WeakMap();
      const decodedFiles = new WeakMap();
      const assetName = value => { try { return new URL(value, location.href).pathname.split('/').pop(); } catch { return ''; } };
      const proto = CanvasRenderingContext2D.prototype;
      const setTransform = proto.setTransform;
      const rect = proto.rect;
      const drawImage = proto.drawImage;
      const fillRect = proto.fillRect;
      const fillText = proto.fillText;
      const strokeText = proto.strokeText;
      const matrix = context => {
        const m = context.getTransform();
        const ratio = Math.max(1, Math.min(3, window.devicePixelRatio));
        return [m.a, m.b, m.c, m.d, m.e, m.f].map(value => value / ratio);
      };
      proto.setTransform = function (...args) {
        if (this.canvas.id === 'game') {
          if (observed.current?.captured) observed.frames.push(observed.current);
          observed.frames = observed.frames.slice(-8);
          observed.current = { images: [], fills: [], viewport: null, systemText: 0, sequence: 0,
            captured: observed.capture, scene: this.canvas.getAttribute('data-scene') };
        }
        return setTransform.apply(this, args);
      };
      proto.rect = function (x, y, width, height) {
        if (this.canvas.id === 'game') observed.current.viewport = { x, y, width, height };
        return rect.call(this, x, y, width, height);
      };
      proto.drawImage = function (image, ...args) {
        if (this.canvas.id === 'game' && args.length === 8) {
          const tinted = image instanceof HTMLCanvasElement;
          const asset = image instanceof HTMLImageElement ? assetName(image.src)
            : tinted ? image.getAttribute('data-whaley-asset') : null;
          if (asset) observed.current.images.push({
            asset, tinted, tint: colors.get(image) ?? null, order: observed.current.sequence++,
            source: args.slice(0, 4), destination: args.slice(4),
            alpha: this.globalAlpha, blend: this.globalCompositeOperation, matrix: matrix(this)
          });
        }
        return drawImage.call(this, image, ...args);
      };
      proto.fillRect = function (x, y, width, height) {
        if (this.canvas.id === 'game') observed.current.fills.push({
          destination: [x, y, width, height], matrix: matrix(this), color: this.fillStyle,
          alpha: this.globalAlpha, order: observed.current.sequence++
        });
        else if (this.canvas.getAttribute('data-whaley-asset') && this.globalCompositeOperation === 'multiply')
          colors.set(this.canvas, this.fillStyle);
        return fillRect.call(this, x, y, width, height);
      };
      proto.fillText = function (...args) {
        if (this.canvas.id === 'game') observed.current.systemText += 1;
        return fillText.apply(this, args);
      };
      proto.strokeText = function (...args) {
        if (this.canvas.id === 'game') observed.current.systemText += 1;
        return strokeText.apply(this, args);
      };

      // All audio calls still reach the browser's real decoder and playback
      // implementation. The wrappers preserve their return values/rejections.
      const arrayBuffer = Response.prototype.arrayBuffer;
      Response.prototype.arrayBuffer = function (...args) {
        const result = arrayBuffer.apply(this, args);
        result.then(buffer => bufferFiles.set(buffer, assetName(this.url))).catch(() => {});
        return result;
      };
      const decode = BaseAudioContext.prototype.decodeAudioData;
      BaseAudioContext.prototype.decodeAudioData = function (data, ...args) {
        if (!observed.audio.contexts.includes(this)) observed.audio.contexts.push(this);
        const result = decode.call(this, data, ...args);
        result?.then(buffer => {
          const asset = bufferFiles.get(data);
          decodedFiles.set(buffer, asset);
          observed.audio.decoded.push(asset);
        }).catch(() => {});
        return result;
      };
      const start = AudioBufferSourceNode.prototype.start;
      AudioBufferSourceNode.prototype.start = function (...args) {
        const result = start.apply(this, args);
        observed.audio.starts.push({ asset: decodedFiles.get(this.buffer),
          duration: this.buffer?.duration, state: this.context.state });
        return result;
      };
      const stop = AudioBufferSourceNode.prototype.stop;
      AudioBufferSourceNode.prototype.stop = function (...args) {
        const result = stop.apply(this, args);
        observed.audio.stops.push({ asset: decodedFiles.get(this.buffer), state: this.context.state });
        return result;
      };
      const play = HTMLMediaElement.prototype.play;
      const pause = HTMLMediaElement.prototype.pause;
      HTMLMediaElement.prototype.play = function (...args) {
        if (!observed.audio.media.includes(this)) observed.audio.media.push(this);
        const asset = assetName(this.src);
        const result = play.apply(this, args);
        result?.then(() => observed.audio.plays.push({ asset, paused: this.paused,
          readyState: this.readyState, outcome: 'fulfilled' }), error =>
          observed.audio.plays.push({ asset, outcome: 'rejected', error: error.name }));
        return result;
      };
      HTMLMediaElement.prototype.pause = function (...args) {
        if (!observed.audio.media.includes(this)) observed.audio.media.push(this);
        const result = pause.apply(this, args);
        observed.audio.pauses.push({ asset: assetName(this.src), paused: this.paused });
        return result;
      };
    });
    if (seed !== undefined) await page.addInitScript(({ key, raw, origin }) => {
      // Seed one valid on-disk-style record, then allow subsequent reloads to
      // exercise the application's own writes rather than reseeding it.
      if (location.origin === origin && !sessionStorage.getItem('whaley.test.seeded')) {
        localStorage.setItem(key, raw);
        sessionStorage.setItem('whaley.test.seeded', 'true');
      }
    }, { key: progressKey, raw: seed, origin: new URL(gameURL).origin });
    await page.clock.install({ time: new Date('2026-01-01T00:00:00Z') });
    await page.goto(gameURL, { waitUntil: 'networkidle' });
    await ready(page);
    await page.clock.pauseAt(await page.evaluate(() => Date.now() + 50));
    await page.clock.runFor(250);
    return { browser, context, page, errors, resources };
  } catch (error) {
    await browser.close();
    throw error;
  }
}

export async function ready(page) {
  await page.locator('#loading').waitFor({ state: 'hidden' });
  await page.bringToFront();
  assert.equal(await page.locator('#error').isHidden(), true, 'application must load its real resources');
}
export const readFrame = page => page.evaluate(() => window.__whaleyObserved.current);
export const images = (frame, asset) => frame.images.filter(image => image.asset === asset);
export const scene = page => page.locator('#game').getAttribute('data-scene');
export const close = (actual, expected, message, tolerance = 1e-5) =>
  assert.ok(Math.abs(actual - expected) < tolerance, `${message}: ${actual} != ${expected}`);

export function logicalImage(image, frame) {
  const [a, b, c, d, e, f] = image.matrix;
  const [x, y, width, height] = image.destination;
  const scale = frame.viewport.width / 320;
  return {
    x: (a * (x + width / 2) + c * (y + height / 2) + e - frame.viewport.x) / scale,
    y: (b * (x + width / 2) + d * (y + height / 2) + f - frame.viewport.y) / scale,
    width: Math.hypot(a, b) * width / scale, height: Math.hypot(c, d) * height / scale
  };
}
export async function canvasPoint(page, x, y) {
  const frame = await readFrame(page);
  const bounds = await page.locator('#game').boundingBox();
  assert.ok(bounds && frame?.viewport, 'application must establish a fitted Canvas viewport');
  const scale = frame.viewport.width / 320;
  return { x: bounds.x + frame.viewport.x + x * scale, y: bounds.y + frame.viewport.y + y * scale };
}
export async function clickLogical(page, x, y) {
  const p = await canvasPoint(page, x, y);
  await page.mouse.click(p.x, p.y);
}
export async function captureFrames(page, action, milliseconds = 40) {
  await page.evaluate(() => {
    const output = window.__whaleyObserved;
    output.capture = true;
    output.frames = [];
    if (output.current) output.current.captured = false;
  });
  await action();
  await page.clock.runFor(milliseconds);
  return page.evaluate(() => {
    const output = window.__whaleyObserved;
    output.capture = false;
    return [...output.frames, ...(output.current?.captured ? [output.current] : [])];
  });
}
export async function waitForActual(check, message, timeout = 10000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await check()) return;
    // Native decoding/media events continue while the simulation clock is
    // paused. Poll from Node, not a page timer controlled by page.clock.
    await new Promise(resolve => setTimeout(resolve, 40));
  }
  assert.fail(message);
}
export async function readOriginal(name) {
  for (const root of ['Sources/WhaleySpriteKit/Resources', 'Apps/Whaley2010/Resources']) {
    try { return await readFile(path.join(portRoot, '..', root, name), 'utf8'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  throw new Error(`Missing original test fixture: ${name}`);
}
export async function bitmapCharacters() {
  const text = await readOriginal('game_font.fnt');
  return new Map(text.split(/\r?\n/).filter(line => line.startsWith('char ')).map(line => {
    const fields = Object.fromEntries([...line.matchAll(/(\w+)=(-?\d+)/g)].map(m => [m[1], Number(m[2])]));
    return [[fields.x, fields.y, fields.width, fields.height].join(','), String.fromCharCode(fields.id)];
  }));
}
export async function levelFixture(page, number) {
  const source = await readOriginal(`level${number}-568h.tmx`);
  return page.evaluate(xml => {
    const document = new DOMParser().parseFromString(xml, 'application/xml');
    if (document.querySelector('parsererror')) throw new Error('Invalid original TMX fixture');
    const map = document.documentElement;
    const tile = Number(map.getAttribute('tilewidth'));
    const width = Number(map.getAttribute('width')) * tile;
    const height = Number(map.getAttribute('height')) * tile;
    const objects = [...document.querySelectorAll('objectgroup[name="Objects"] > object')];
    const property = (object, key) => object.querySelector(`properties > property[name="${key}"]`)?.getAttribute('value');
    const point = (object, half = 0) => ({
      x: Number(object.getAttribute('x')) + half,
      y: height - Number(object.getAttribute('y')) - Number(object.getAttribute('height') ?? 0) + half
    });
    return { width, height, spawn: point(objects.find(object => object.getAttribute('name') === 'PlayerOrigin')),
      coins: objects.filter(object => property(object, 'IsCoin') === '1').map(object => point(object, 16)),
      bubbles: objects.filter(object => property(object, 'IsBubble') === '1').map(object => point(object, 22)) };
  }, source);
}
export function drawnText(frame, characters) {
  return images(frame, 'game_font.png').map(image => {
    const value = characters.get(image.source.join(','));
    assert.ok(value, `bitmap glyph must exist in original font: ${image.source}`);
    return value;
  }).join('');
}
export async function storedProgress(page) {
  return page.evaluate(key => localStorage.getItem(key), progressKey);
}

async function smoke() {
  const { browser, page, errors } = await openGame({ hasTouch: true });
  try {
    assert.equal(await scene(page), 'gallery');
    assert.equal(await page.title(), 'Gray Whale');
    assert.equal(await page.locator('#level,#play,#menu,#pause,#restart,#time,#bubbles').count(), 0,
      'the original scene must not be surrounded by extra labels or controls');
    const invincibility = page.getByRole('switch', { name: 'Invincibility', exact: true });
    assert.equal(await page.locator('button:visible').count(), 1);
    assert.equal(await invincibility.getAttribute('aria-checked'), 'false');
    assert.equal((await invincibility.textContent()).trim(), '', 'the toggle uses only a star icon');
    const target = await invincibility.boundingBox();
    assert.ok(target.width >= 44 && target.height >= 44, 'the star retains a comfortable touch target');
    assert.ok(await invincibility.locator('polygon').getAttribute('points'), 'the shared star must be drawn');
    assert.equal(await page.locator('#status').evaluate(element => getComputedStyle(element).clipPath), 'inset(50%)');
    await page.keyboard.press('1');
    await page.clock.runFor(600);
    assert.equal(await scene(page), 'game');
    const frame = await readFrame(page);
    const pixels = await page.locator('#game').evaluate(canvas => {
      const bounds = canvas.getBoundingClientRect();
      const data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
      const colors = new Set();
      for (let i = 0; i < data.length; i += 16) colors.add(`${data[i]},${data[i + 1]},${data[i + 2]},${data[i + 3]}`);
      return { width: canvas.width, height: canvas.height, cssWidth: bounds.width, cssHeight: bounds.height, colors: colors.size };
    });
    assert.ok(Math.abs(pixels.width - pixels.cssWidth * 2) <= 1 && Math.abs(pixels.height - pixels.cssHeight * 2) <= 1);
    assert.ok(pixels.colors > 30, 'Canvas must display original textured artwork');
    close(frame.viewport.width / frame.viewport.height, 320 / 568, 'original portrait surface');

    const bubbles = output => images(output, 'bubble01.png').length;
    const world = output => output.images.filter(image =>
      /^(player|player-win|bubble01|infinite_bubble|coin|flame01|flame02|goal01)\.png$/.test(image.asset) &&
      logicalImage(image, output).width > 20).map(image => ({
        asset: image.asset, source: image.source, ...logicalImage(image, output)
      }));
    const shoot = async touch => {
      const before = await readFrame(page);
      const player = images(before, 'player.png').find(image => logicalImage(image, before).width > 20);
      assert.ok(player, 'the actual player must be drawn');
      const center = logicalImage(player, before);
      const point = await canvasPoint(page, center.x + 60, center.y + 55);
      assert.ok(center.x + 60 < 320 && center.y + 55 < 568);
      if (touch) await page.touchscreen.tap(point.x, point.y);
      else await page.mouse.click(point.x, point.y);
      await page.clock.runFor(40);
      assert.equal(bubbles(await readFrame(page)), bubbles(before) + 1, 'one real press creates one visible bubble');
    };
    await page.keyboard.press('r');
    await page.clock.runFor(40);
    await shoot(false);
    await clickLogical(page, 160, 16);
    assert.equal(await page.locator('#game').getAttribute('data-paused'), 'true');
    await page.clock.runFor(40);
    const pausedWorld = world(await readFrame(page));
    await page.clock.runFor(1200);
    assert.deepEqual(world(await readFrame(page)), pausedWorld, 'pause freezes actual world drawing and animation');
    await clickLogical(page, 160, 350);
    await page.clock.runFor(40);
    assert.deepEqual(world(await readFrame(page)), pausedWorld, 'paused gameplay input is consumed');
    await clickLogical(page, 260, 16);
    assert.equal(await page.locator('#game').getAttribute('data-paused'), 'false');
    await page.clock.runFor(250);
    assert.notDeepEqual(world(await readFrame(page)), pausedWorld, 'CONTINUE resumes animation');

    await page.keyboard.press('2');
    await page.clock.runFor(600);
    const horizontal = await readFrame(page);
    close(horizontal.viewport.width / horizontal.viewport.height, 320 / 568, 'horizontal maps retain the full screen');
    close(logicalImage(images(horizontal, 'player.png')[0], horizontal).width, 32, 'horizontal world is not fitted to its whole map width');
    await shoot(true);
    await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    await page.clock.runFor(40);
    const unfocused = world(await readFrame(page));
    await page.clock.runFor(2000);
    assert.deepEqual(world(await readFrame(page)), unfocused, 'focus loss pauses simulation');
    await page.evaluate(() => window.dispatchEvent(new Event('focus')));
    await clickLogical(page, 260, 16);
    await page.clock.runFor(40);
    assert.equal(await page.locator('#game').getAttribute('data-paused'), 'false');
    const afterFocus = world(await readFrame(page));
    const beforePlayer = unfocused.find(image => image.asset === 'player.png');
    const afterPlayer = afterFocus.find(image => image.asset === 'player.png');
    assert.ok(Math.abs(beforePlayer.y - afterPlayer.y) < 20, 'resume must not replay the unfocused interval');
    assert.deepEqual(errors, [], 'no application, resource or real audio errors');
    await mkdir(path.join(portRoot, 'target'), { recursive: true });
    await page.screenshot({ path: path.join(portRoot, 'target', 'web-smoke.png'), fullPage: true });
    console.log('PASS: original page chrome, textured Canvas/DPR, mouse/touch shots, HUD pause/continue, horizontal fit and focus recovery.');
  } finally { await browser.close(); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await smoke();
