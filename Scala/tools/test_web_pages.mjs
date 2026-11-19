#!/usr/bin/env node
// Exercise the actual static export at a GitHub Pages project URL. The shared
// browser helpers observe the real Canvas, storage and audio implementations.
// Run after make whaley-pages: cd Scala && npm run test:pages
// An optional argument selects another already built bundle directory.
import assert from 'node:assert/strict';
import { createReadStream } from 'node:fs';
import { realpath, stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scalaRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
assert.ok(process.argv.length <= 3, 'Usage: node tools/test_web_pages.mjs [bundle-directory]');
const requestedBundle = path.resolve(process.argv[2] ?? path.join(scalaRoot, 'target/pages'));
let bundle;
try {
  bundle = await realpath(requestedBundle);
  for (const name of ['index.html', '.nojekyll', 'assets/main.js', 'assets/styles.css']) {
    assert.ok((await stat(path.join(bundle, name))).isFile(), `Missing Pages file: ${name}`);
  }
} catch (error) {
  throw new Error(`Build the real Pages bundle first with make whaley-pages (${requestedBundle}).`, { cause: error });
}

const mount = '/chatgpt-WhaleKart/';
const mimeTypes = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json',
  '.map': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.mp3': 'audio/mpeg', '.wav': 'audio/wav',
  '.ogg': 'audio/ogg'
};
const serverErrors = [];
const server = createServer(async (request, response) => {
  try {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.writeHead(405, { Allow: 'GET, HEAD' }).end();
      return;
    }
    const pathname = new URL(request.url, 'http://127.0.0.1').pathname;
    // Chromium may request an implicit origin favicon; this is not a game asset.
    if (pathname === '/favicon.ico' || pathname === `${mount}favicon.ico`) {
      response.writeHead(204).end();
      return;
    }
    if (!pathname.startsWith(mount)) {
      response.writeHead(404).end();
      return;
    }
    const relative = decodeURIComponent(pathname.slice(mount.length)) || 'index.html';
    const candidate = path.resolve(bundle, relative);
    if (!candidate.startsWith(`${bundle}${path.sep}`)) {
      response.writeHead(403).end();
      return;
    }
    const filename = await realpath(candidate);
    if (!filename.startsWith(`${bundle}${path.sep}`)) {
      response.writeHead(403).end();
      return;
    }
    const info = await stat(filename);
    if (!info.isFile()) {
      response.writeHead(404).end();
      return;
    }
    let start = 0;
    let end = info.size - 1;
    let status = 200;
    if (request.headers.range) {
      const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.range);
      if (range && (range[1] || range[2])) {
        start = range[1] ? Number(range[1]) : Math.max(0, info.size - Number(range[2]));
        end = range[1] && range[2] ? Math.min(Number(range[2]), end) : end;
      }
      if (!range || (!range[1] && !range[2]) || start > end || start >= info.size) {
        response.writeHead(416, { 'Content-Range': `bytes */${info.size}` }).end();
        return;
      }
      status = 206;
      response.setHeader('Content-Range', `bytes ${start}-${end}/${info.size}`);
    }
    response.writeHead(status, {
      'Content-Type': mimeTypes[path.extname(filename).toLowerCase()] ?? 'application/octet-stream',
      'Content-Length': info.size ? end - start + 1 : 0,
      'Accept-Ranges': 'bytes', 'Cache-Control': 'no-store'
    });
    if (request.method === 'HEAD' || info.size === 0) {
      response.end();
      return;
    }
    const stream = createReadStream(filename, { start, end });
    stream.on('error', error => {
      serverErrors.push(`${filename}: ${error.message}`);
      response.destroy(error);
    });
    response.on('close', () => stream.destroy());
    stream.pipe(response);
  } catch (error) {
    if (error.code === 'ENOENT' || error.code === 'ENOTDIR') response.writeHead(404).end();
    else if (error instanceof URIError) response.writeHead(400).end();
    else {
      serverErrors.push(error.message);
      if (!response.headersSent) response.writeHead(500);
      response.end();
    }
  }
});
await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', resolve);
});

const origin = `http://127.0.0.1:${server.address().port}`;
const previousURL = process.env.WHALEY_BROWSER_URL;
process.env.WHALEY_BROWSER_URL = `${origin}${mount}`;
let game;
try {
  // A root-relative URL must fail here, even if it works in the Play root.
  assert.equal((await fetch(`${origin}/assets/main.js`)).status, 404);
  const { openGame, ready, scene, readFrame, images, clickLogical, storedProgress } =
    await import('./test_web.mjs');
  game = await openGame();
  const { page, resources, errors } = game;
  assert.equal(await page.title(), 'Gray Whale');
  assert.equal(await scene(page), 'gallery');
  assert.equal(images(await readFrame(page), 'frame.png').length, 6,
    'the shared game must draw the gallery, not just load an HTML shell');
  for (const name of ['main.js', 'styles.css', 'level2.png', 'level2-568h.png',
    'level3.png', 'level3-568h.png', 'level5.png', 'level5-568h.png']) {
    assert.ok(resources.has(name), `The real game must load ${name} beneath ${mount}`);
  }

  // Pop the gallery reward through normal pointer input, then verify the game's
  // own saved progress and rendered reward state survive a document reload.
  await clickLogical(page, 141, 64);
  await page.clock.runFor(50);
  const saved = await storedProgress(page);
  assert.ok(saved?.startsWith('whaley-progress|1\n1|false|false'),
    'the real gallery interaction must persist its reward state');
  await page.reload({ waitUntil: 'networkidle' });
  await ready(page);
  await page.clock.runFor(250);
  assert.equal(await scene(page), 'gallery');
  assert.equal(await storedProgress(page), saved);
  assert.equal(images(await readFrame(page), 'bubble01.png').length, 0,
    'reloading must restore the popped reward');

  for (const number of [2, 3, 5]) {
    await page.keyboard.press(String(number));
    await page.clock.runFor(50);
    assert.equal(await scene(page), 'game');
    const paintings = images(await readFrame(page), `level${number}-568h.png`);
    assert.equal(paintings.length, 1, `level ${number} must render its replacement painting`);
    assert.deepEqual(paintings[0].source, [0, 0, 320, 568]);
    assert.ok(!resources.has(`level${number}.jpg`));
  }
  await page.keyboard.press('Space');
  assert.equal(await page.locator('#game').getAttribute('data-paused'), 'true');
  await page.keyboard.press('Space');
  assert.equal(await page.locator('#game').getAttribute('data-paused'), 'false');
  await page.keyboard.press('m');
  assert.equal(await scene(page), 'gallery');
  assert.deepEqual(errors, [], 'no application, asset, JavaScript or audio errors under the project URL');
  assert.deepEqual(serverErrors, []);
  console.log(`PASS: static Pages export at ${mount}; gallery, tall PNG backgrounds, gameplay, pause and saved progress reload.`);
} finally {
  if (previousURL === undefined) delete process.env.WHALEY_BROWSER_URL;
  else process.env.WHALEY_BROWSER_URL = previousURL;
  try { await game?.browser.close(); }
  finally {
    await new Promise(resolve => {
      server.close(resolve);
      server.closeAllConnections();
    });
  }
}
