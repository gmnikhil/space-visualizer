// Browser QA for the HTML review artifact only. This does NOT test native Apple Music capture.
// Requires Node and Playwright with Chromium installed outside this artifact directory.
// Run: PLAYWRIGHT_MODULE=/absolute/path/to/playwright node validate-proposal.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const htmlPath = path.join(__dirname, 'design-and-architecture.html');
const url = pathToFileURL(htmlPath).href;
const results = [];
const pass = name => { results.push(name); console.log('PASS:', name); };
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

function toneFixture() {
  const sampleRate = 48000;
  const seconds = 12;
  const frames = sampleRate * seconds;
  const bytes = Buffer.alloc(44 + frames * 2);
  bytes.write('RIFF', 0); bytes.writeUInt32LE(36 + frames * 2, 4);
  bytes.write('WAVEfmt ', 8); bytes.writeUInt32LE(16, 16);
  bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(sampleRate, 24); bytes.writeUInt32LE(sampleRate * 2, 28);
  bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34);
  bytes.write('data', 36); bytes.writeUInt32LE(frames * 2, 40);
  for (let i = 0; i < frames; i++) {
    const t = i / sampleRate;
    const hz = t < 3 ? 80 : t < 6 ? 1000 : t < 9 ? 8000 : 0;
    bytes.writeInt16LE(hz ? Math.round(Math.sin(2 * Math.PI * hz * t) * 0.16 * 32767) : 0, 44 + i * 2);
  }
  return bytes;
}

(async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'resonant-qa-'));
  const audioFile = path.join(temp, '80Hz-1kHz-8kHz-silence.wav');
  fs.writeFileSync(audioFile, toneFixture());
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const errors = [], remoteRequests = [];
  const context = await browser.newContext({ viewport: { width: 1440, height: 1080 }, acceptDownloads: true });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(String(error)));
  context.on('request', request => {
    if (/^https?:/.test(request.url())) remoteRequests.push(request.url());
  });
  const visiblePanel = async id => {
    await page.waitForFunction(expected => {
      const panels = [...document.querySelectorAll('.tab-panel')].filter(el => !el.hidden);
      return panels.length === 1 && panels[0].id === expected;
    }, id);
    assert.equal(await page.locator(`#tab-${id}`).getAttribute('aria-selected'), 'true');
  };
  const go = async id => { await page.locator(`#tab-${id}`).click(); await visiblePanel(id); await delay(360); };
  const canvasImage = () => page.locator('#visualizer').evaluate(el => el.toDataURL());
  try {
    await page.goto(url);
    await visiblePanel('overview');
    await delay(400);
    await page.screenshot({ path: path.join(__dirname, 'overview-preview.png'), fullPage: true });
    pass('Standalone file:// load, no server required');

    await go('screens');
    assert.equal(new URL(page.url()).hash, '#screens');
    await go('architecture');
    await page.goBack(); await visiblePanel('screens');
    await page.goForward(); await visiblePanel('architecture');
    await page.reload(); await visiblePanel('architecture');
    await page.goto(url + '#feasibility'); await visiblePanel('feasibility');
    await page.goto(url + '#unknown'); await visiblePanel('overview');
    pass('Tab URL fragments, direct links, refresh, back/forward, unknown-fragment fallback');

    await page.locator('#tab-overview').focus();
    await page.keyboard.press('ArrowRight'); await visiblePanel('experience');
    assert.equal(await page.locator('#tab-experience').evaluate(el => el === document.activeElement), true);
    await page.keyboard.press('End'); await visiblePanel('review');
    await page.keyboard.press('Home'); await visiblePanel('overview');
    pass('Keyboard tab navigation and selected-tab ARIA state');

    await go('experience');
    assert.match(await page.locator('#signal-status').textContent(), /SYNTHETIC/);
    assert.equal(await page.locator('#local-audio').evaluate(el => el.paused), true);
    const a = await canvasImage(); await delay(250); const b = await canvasImage();
    assert.notEqual(a, b, 'Synthetic scene should animate');
    await page.locator('#toggle-motion').click(); await delay(120);
    const frozen = await canvasImage(); await delay(220);
    assert.equal(await canvasImage(), frozen, 'Pause animation should freeze the canvas');
    const scenes = new Set();
    for (const scene of ['orbital', 'terrain', 'prism']) {
      await page.locator(`[data-scene=${scene}]`).click(); await delay(90);
      assert.equal(await page.locator(`[data-scene=${scene}]`).getAttribute('aria-pressed'), 'true');
      scenes.add(await canvasImage());
    }
    assert.equal(scenes.size, 3);
    await page.selectOption('#palette', 'ember'); await delay(90);
    assert.notEqual(await canvasImage(), [...scenes][2]);
    await page.locator('#intensity').fill('1.5');
    assert.equal(await page.locator('#intensity-output').textContent(), '1.50×');
    pass('Three distinct rendered scenes, palette/response controls, real pause, silent synthetic labeling');

    await page.locator('#toggle-motion').click();
    await page.locator('#audio-file').setInputFiles(audioFile);
    await page.waitForFunction(() => {
      const audio = document.getElementById('local-audio');
      return !audio.paused && audio.readyState >= 3;
    });
    const bandReadings = [];
    for (const [second, expected] of [[0.7, 'bass'], [3.7, 'mid'], [6.7, 'high']]) {
      await page.locator('#local-audio').evaluate((el, t) => { el.currentTime = t; }, second);
      await delay(650);
      const readings = await page.evaluate(() => Object.fromEntries(['bass', 'mid', 'high'].map(k => [k, Number(document.getElementById('value-' + k).value)])));
      bandReadings.push({ expected, ...readings });
      assert.ok(readings[expected] > 30, JSON.stringify(readings));
      for (const other of ['bass', 'mid', 'high'].filter(k => k !== expected)) {
        assert.ok(readings[expected] > readings[other] + 20, JSON.stringify(readings));
      }
    }
    assert.match(await page.locator('#signal-status').textContent(), /WEB AUDIO FFT/);
    assert.match(await page.locator('#track-title').textContent(), /80Hz/);
    await page.locator('#local-audio').evaluate(el => { el.currentTime = 9.2; });
    await delay(900);
    const silent = await page.evaluate(() => ['bass', 'mid', 'high'].map(k => Number(document.getElementById('value-' + k).value)));
    assert.ok(silent.every(value => value < 3), JSON.stringify(silent));
    console.log('Tone readings:', JSON.stringify(bandReadings), 'Silence:', silent);
    await go('screens');
    assert.equal(await page.locator('#local-audio').evaluate(el => el.paused), true);
    pass('Local WAV FFT: 80 Hz bass, 1 kHz mids, 8 kHz highs; silence settles; leaving section pauses audio');

    for (const value of ['waiting', 'permission', 'unavailable', 'metadata', 'paused', 'live', 'route']) {
      await page.selectOption('#state-preview', value);
      assert.ok((await page.locator('#state-description').textContent()).length > 60);
    }
    pass('All seven simulated connection/signal states render explanatory recovery copy');

    await go('experience');
    await page.locator('#use-demo').click();
    assert.equal(await page.locator('#audio-wrap').isVisible(), false);
    assert.match(await page.locator('#signal-status').textContent(), /SYNTHETIC/);
    await page.locator('#audio-file').setInputFiles({ name: 'unsupported.txt', mimeType: 'text/plain', buffer: Buffer.from('Not an audio stream') });
    await page.waitForFunction(() => document.getElementById('local-audio').error !== null);
    assert.match(await page.locator('#signal-status').textContent(), /UNAVAILABLE/);
    await page.locator('#use-demo').click();
    pass('Synthetic reset releases local player; invalid audio has an honest unavailable state');

    await page.locator('#fullscreen').click();
    await page.waitForFunction(() => Boolean(document.fullscreenElement));
    assert.equal(await page.locator('.tuning').isVisible(), false);
    await page.locator('#fullscreen').click();
    await page.waitForFunction(() => !document.fullscreenElement);
    pass('Immersive mode enters/exits fullscreen and hides tuning controls');

    await go('review');
    assert.match(await page.locator('#review-output').inputValue(), /no approval given/);
    await page.locator('[name=companion]').check();
    await page.locator('[name=truth]').check();
    await page.selectOption('#favorite-scene', 'Orbital Bloom (recommended)');
    await page.locator('#mac-info').fill('Test-only Mac placeholder');
    await page.locator('#review-notes').fill('<script>This must stay plain text</script>');
    await page.locator('[name=decision]').first().check();
    const review = await page.locator('#review-output').inputValue();
    assert.match(review, /feasibility spike only/);
    assert.match(review, /Full-app implementation is NOT approved/);
    assert.match(review, /<script>This must stay plain text<\/script>/);
    await page.reload(); await visiblePanel('review');
    assert.equal(await page.locator('#mac-info').inputValue(), 'Test-only Mac placeholder');
    const downloadPromise = page.waitForEvent('download');
    await page.locator('#download-review').click();
    const download = await downloadPromise;
    assert.equal(download.suggestedFilename(), 'resonant-design-review.txt');
    const exportText = fs.readFileSync(await download.path(), 'utf8');
    assert.match(exportText, /feasibility spike only/);
    await page.locator('#copy-review').click();
    await page.waitForFunction(() => /Copied|selected below/.test(document.getElementById('review-message').textContent));
    pass('Unapproved default, safe review text, local persistence, download, clipboard or selection fallback');

    for (const width of [390, 760, 1024, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      for (const id of ['overview', 'experience', 'screens', 'architecture', 'feasibility', 'review']) {
        await go(id);
        const dimensions = await page.evaluate(() => ({ body: document.documentElement.scrollWidth, viewport: innerWidth }));
        assert.ok(dimensions.body <= dimensions.viewport + 1, `${id} overflows at ${width}: ${JSON.stringify(dimensions)}`);
      }
    }
    pass('All six sections have no document-level horizontal overflow at 390, 760, 1024, and 1440 px');

    await page.setViewportSize({ width: 1440, height: 1080 });
    await go('experience');
    await page.locator('[data-scene=orbital]').click();
    await page.selectOption('#palette', 'dusk');
    await page.locator('#intensity').fill('1');
    await delay(400);
    await page.screenshot({ path: path.join(__dirname, 'motion-studio-preview.png'), fullPage: true });
    await go('architecture');
    await page.screenshot({ path: path.join(__dirname, 'architecture-preview.png'), fullPage: true });
    pass('Desktop screenshots captured for visual review');

    const reduced = await browser.newContext({ viewport: { width: 1100, height: 850 }, reducedMotion: 'reduce' });
    const reducedPage = await reduced.newPage();
    await reducedPage.goto(url + '#experience'); await delay(500);
    assert.equal(await reducedPage.locator('#gentle').isChecked(), true);
    assert.match(await reducedPage.locator('#toggle-motion').textContent(), /Resume/);
    const still = await reducedPage.locator('#visualizer').evaluate(el => el.toDataURL());
    await delay(250);
    assert.equal(await reducedPage.locator('#visualizer').evaluate(el => el.toDataURL()), still);
    await reduced.close();
    pass('OS Reduce Motion defaults to gentle controls and a stationary canvas');

    const noJS = await browser.newContext({ javaScriptEnabled: false });
    const staticPage = await noJS.newPage(); await staticPage.goto(url);
    for (const id of ['overview', 'experience', 'screens', 'architecture', 'feasibility', 'review']) assert.equal(await staticPage.locator('#' + id).isVisible(), true);
    await noJS.close();
    pass('No-JavaScript fallback exposes every review section');

    assert.deepEqual(errors, []);
    assert.deepEqual(remoteRequests, []);
    pass('No page JavaScript errors; zero external HTTP(S) requests during artifact usage');
    console.log(`\n${results.length} validation groups passed. Native Apple Music integration remains UNTESTED.`);
  } finally {
    await browser.close();
    fs.rmSync(temp, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
