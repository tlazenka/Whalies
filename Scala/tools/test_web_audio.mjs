#!/usr/bin/env node
// Exercise the real browser decoder, AudioContext and streaming media elements.
// Observation helpers forward every native call; no audio API is mocked.
import assert from 'node:assert/strict';
import { openGame, clickLogical, scene, waitForActual } from './test_web.mjs';

const effects = ['bg01.mp3', 'bounce01.wav', 'coin01.wav', 'flame01.wav',
  'goal01.wav', 'jump01.wav', 'knock.mp3', 'pause01.wav'];
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const audio = page => page.evaluate(() => {
  const observed = window.__whaleyObserved.audio;
  return {
    starts: observed.starts, stops: observed.stops, plays: observed.plays,
    decoded: observed.decoded,
    contexts: observed.contexts.map(context => context.state),
    music: observed.media.map(element => ({
      asset: new URL(element.src, location.href).pathname.split('/').pop(),
      paused: element.paused, time: element.currentTime, ended: element.ended,
      duration: element.duration, loop: element.loop
    }))
  };
});
const track = (state, name = 'A.mp3') => state.music.find(item => item.asset === name);
const starts = (state, name) => state.starts.filter(item => item.asset === name);

async function activationAndLifecycle() {
  const { browser, page, errors } = await openGame();
  try {
    assert.equal(await scene(page), 'gallery');
    let state = await audio(page);
    assert.equal(state.plays.length, 0, 'menu music must await a real user gesture');
    assert.equal(state.starts.length, 0, 'effects must await a real user gesture');
    assert.equal(state.contexts.length, 0, 'loading the page must not create decoding contexts');

    await clickLogical(page, 50, 90);
    await waitForActual(async () => {
      state = await audio(page);
      return state.contexts.length === 1 && state.contexts[0] === 'running' &&
        starts(state, 'knock.mp3').length === 1 && !track(state)?.paused && track(state)?.time > 0.04;
    }, 'a real gallery press must activate effects and the original A soundtrack');
    await waitForActual(async () => (await audio(page)).decoded.length === effects.length,
      'all eight original effects must pass the browser decoder');
    state = await audio(page);
    assert.deepEqual([...state.decoded].sort(), effects);
    assert.equal(state.music.length, 1, 'one streaming element owns the long menu track');
    assert.equal(track(state).loop, false, 'original menu music plays once');
    assert.ok(starts(state, 'knock.mp3').every(item => item.duration > 0 && item.state === 'running'));

    const invincibility = page.getByRole('switch', { name: 'Invincibility', exact: true });
    const musicBeforeToggle = track(state).time;
    const stoppedBeforeToggle = state.stops.length;
    await invincibility.click();
    await waitForActual(async () => {
      state = await audio(page);
      return state.contexts[0] === 'running' && !track(state).paused &&
        track(state).time > musicBeforeToggle + 0.04;
    }, 'toggling invincibility must leave the audio context and menu music running');
    assert.equal(state.stops.length, stoppedBeforeToggle, 'the star must not stop active effects');
    await invincibility.click();

    // The same media element must retain its current position during gameplay.
    const knockCount = starts(state, 'knock.mp3').length;
    await clickLogical(page, 50, 90);
    await waitForActual(async () => starts(await audio(page), 'knock.mp3').length > knockCount,
      'a fresh gallery touch must start its cached original effect');
    await page.keyboard.press('1');
    await page.clock.runFor(32);
    assert.equal(await scene(page), 'game');
    state = await audio(page);
    const pausedPosition = track(state).time;
    assert.ok(track(state).paused && pausedPosition > 0);
    assert.ok(state.stops.some(item => item.asset === 'knock.mp3'),
      'leaving the gallery stops its still-playing effect voices');
    await delay(150);
    assert.ok(Math.abs(track(await audio(page)).time - pausedPosition) < 0.03,
      'gameplay pauses music without rewinding it');

    const pauseCount = starts(state, 'pause01.wav').length;
    await page.keyboard.press('Space');
    await waitForActual(async () => starts(await audio(page), 'pause01.wav').length > pauseCount,
      'the living player pause action must play the original pause effect');
    await page.keyboard.press('m');
    await page.clock.runFor(32);
    await waitForActual(async () => {
      state = await audio(page);
      return !track(state).paused && track(state).time > pausedPosition + 0.04;
    }, 'returning to the gallery must resume the retained menu position');
    assert.equal(await scene(page), 'gallery');
    assert.equal(state.music.length, 1);
    assert.deepEqual(state.contexts, ['running']);

    await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    await waitForActual(async () => {
      state = await audio(page);
      return state.contexts[0] === 'suspended' && track(state).paused;
    }, 'focus loss must suspend the actual audio context and menu track');
    const backgroundPosition = track(state).time;
    await delay(150);
    assert.ok(Math.abs(track(await audio(page)).time - backgroundPosition) < 0.03);
    await page.evaluate(() => window.dispatchEvent(new Event('focus')));
    await waitForActual(async () => {
      state = await audio(page);
      return state.contexts[0] === 'running' && !track(state).paused;
    }, 'focus return must resume playback');

    // Both resume() and play() are asynchronous. Rapid lifecycle transitions
    // must leave the final requested state active, without a second owner.
    await page.evaluate(() => {
      for (let index = 0; index < 3; index += 1) {
        window.dispatchEvent(new Event('blur'));
        window.dispatchEvent(new Event('focus'));
      }
    });
    await waitForActual(async () => {
      state = await audio(page);
      return state.contexts.length === 1 && state.contexts[0] === 'running' &&
        state.music.length === 1 && !track(state).paused;
    }, 'a pending suspension or aborted play must not defeat a later focus return');

    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true })));
    await waitForActual(async () => {
      state = await audio(page);
      return state.contexts[0] === 'suspended' && track(state).paused;
    }, 'a cached page must remain silent');
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
    await waitForActual(async () => {
      state = await audio(page);
      return state.contexts.length === 1 && state.contexts[0] === 'running' && !track(state).paused;
    }, 'a restored cached page must reuse its audio owner');
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
}

async function cancelledDecode() {
  const { browser, page, errors } = await openGame();
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let requested = false;
  try {
    // Delay delivery of the real server response. The original bytes still
    // pass through the browser's decoder after the scene has changed.
    await page.route('**/knock.mp3', async route => {
      const response = await route.fetch();
      requested = true;
      await gate;
      await route.fulfill({ response });
    });
    await clickLogical(page, 50, 90);
    await waitForActual(async () => requested, 'the first gallery touch must request the original knock');
    await page.keyboard.press('1');
    await page.clock.runFor(32);
    assert.equal(await scene(page), 'game');
    release();
    await waitForActual(async () => (await audio(page)).decoded.includes('knock.mp3'),
      'the delayed original response must still decode successfully');
    await delay(150);
    assert.equal(starts(await audio(page), 'knock.mp3').length, 0,
      'a completed decode must not play a cue from the departed gallery');
    await page.keyboard.press('m');
    await page.clock.runFor(32);
    await clickLogical(page, 50, 90);
    await waitForActual(async () => starts(await audio(page), 'knock.mp3').length === 1,
      'the retained decoded buffer must play for a fresh gallery touch');
    assert.deepEqual(errors, []);
  } finally {
    release();
    await browser.close();
  }
}

async function completedSoundtrack() {
  // This is the same validated persisted record the application writes after
  // completing all six levels. It enters the ordinary completed gallery.
  const { browser, page, errors } = await openGame({ seed: 'whaley-progress|1\n7|false|false' });
  try {
    assert.equal(await page.title(), 'Glad Whale');
    await clickLogical(page, 50, 90);
    await waitForActual(async () => {
      const music = track(await audio(page), 'B.mp3');
      return music && !music.paused && music.time > 0.04 && Number.isFinite(music.duration);
    }, 'completed progress must play the original B soundtrack');
    await page.evaluate(() => {
      const element = window.__whaleyObserved.audio.media.find(item => item.src.endsWith('/B.mp3'));
      element.currentTime = element.duration - 0.2;
    });
    await waitForActual(async () => track(await audio(page), 'B.mp3').ended,
      'the original B track must finish without looping');
    const before = await audio(page);
    await page.keyboard.press('1');
    await page.keyboard.press('m');
    await page.clock.runFor(32);
    await delay(150);
    const after = await audio(page);
    assert.ok(track(after, 'B.mp3').ended && track(after, 'B.mp3').paused,
      'returning to the gallery must not restart a naturally finished soundtrack');
    assert.equal(after.plays.length, before.plays.length);
    assert.deepEqual(errors, []);
  } finally {
    await browser.close();
  }
}

await activationAndLifecycle();
await cancelledDecode();
await completedSoundtrack();
console.log('PASS: real audio activation/decoding, original A/B tracks, retained music position, pause cue, scene cancellation, focus/page lifecycle and natural completion.');
