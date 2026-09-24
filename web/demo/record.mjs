// Records the demo: the HTML prototype walked with pacing inside stage.html (16:9, 1920×1080),
// and a phone-only 9:16 pass through phone.html (780×1688). Writes WebM, then MP4/WebM/poster with ffmpeg.
//
//   cd web/demo && npm install && node record.mjs            # both formats into out/
//   node record.mjs --only 16x9 | --only 9x16 | --no-encode | --poster (retake the stills only)
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..');
const out = path.join(here, 'out');
const PROTOTYPE = '/docs/prototype/Supermortgage-Agent-Prototype.html';
const args = process.argv.slice(2);
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;
const encode = !args.includes('--no-encode');
const posterOnly = args.includes('--poster');
const FONT = process.env.DEMO_FONT ?? 'Inter';

// A tiny static server so the stage and the prototype share an origin.
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2', '.ttf': 'font/ttf' };
// The prototype reads env(safe-area-inset-top/bottom), which a browser reports as 0 and an iPhone 15
// as 59pt/34pt; the served copy carries the phone's values so the layout matches the device.
const SAFE = { top: '59px', bottom: '34px' };
const server = http.createServer((req, res) => {
  const file = path.join(repo, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!file.startsWith(repo) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' });
  if (file.endsWith(PROTOTYPE)) {
    const html = fs.readFileSync(file, 'utf8')
      .replaceAll('env(safe-area-inset-top)', SAFE.top)
      .replaceAll('env(safe-area-inset-bottom)', SAFE.bottom);
    res.end(html);
    return;
  }
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

// The walk, in the order of the app's own walk, with the pauses a viewer needs. `caption` only
// shows on the 16:9 stage; `chapter` advances the progress marks; `poster` grabs the still for the website.
const script = [
  { caption: ['Meet your home assistant', 'It sets itself up in a minute, then works while you’re away.'], chapter: 0 },
  { wait: 'auto-advance', pause: 2200 },
  { click: '[data-ag="signupOpen"]', pause: 1800, caption: ['Sign up with Apple, Google or e-mail', 'No password. A real account in seconds.'] },
  { click: '[data-ag="auth"][data-arg="Apple"]', caption: ['Meet your agent', 'It introduces itself and asks what to call it.'], chapter: 1 },
  { waitFor: '[data-ag="nameMe"][data-arg="Hazel"]', pause: 1600 },
  { click: '[data-ag="nameMe"][data-arg="Hazel"]', waitFor: '[data-ag="connMortgage"][data-arg="Upload a statement"]', pause: 1200, caption: ['Three connections', 'Your mortgage, your credit, your accounts.'], chapter: 2 },
  { click: '[data-ag="connMortgage"][data-arg="Upload a statement"]', waitFor: '[data-ag="connCredit"][data-arg="Yes, go ahead"]', pause: 900 },
  { click: '[data-ag="connCredit"][data-arg="Yes, go ahead"]', waitFor: '[data-ag="plaid"]', pause: 900 },
  { click: '[data-ag="plaid"]', waitFor: '[data-ag="plaidDone"]', pause: 1600 },
  { click: '[data-ag="plaidDone"]', waitFor: '.message .big', pause: 1300, poster: true, caption: ['Your number', 'What the house costs you today, and what comes off it.'], chapter: 3 },
  { waitFor: '.chat-choice[data-ag="reviewPMI"]' },
  { waitFor: '.chat-choice[data-ag="startRefi"]', pause: 2600 },
  { click: '.chat-choice[data-ag="reviewPMI"]', waitFor: '[data-ag="approvePMI"]', pause: 2200, caption: ['One tap to approve', 'It drafts the request. You say yes.'], chapter: 4 },
  { click: '[data-ag="approvePMI"]', pause: 1600 },
  { click: '[data-ag="tab"][data-arg="feed"]', pause: 2800, caption: ['Your feed', 'Only what moved your number, or needs a yes.'], chapter: 5 },
  { click: '[data-ag="tab"][data-arg="work"]', pause: 2400, caption: ['59 things it does for your home', 'Running, waiting, or needing you.'], chapter: 6 },
  { click: '[data-ag="workRow"][data-arg="w1"]', waitFor: '#ag-sheet[open]', pause: 2400 },
  { click: '#ag-sheet [data-ag="close"]', pause: 600 },
  { click: '[data-ag="tab"][data-arg="goals"]', pause: 2800, caption: ['Goals', 'Tell it what you’re after. The plan evolves with you.'], chapter: 7 },
  { click: '[data-ag="tab"][data-arg="art"]', pause: 2000, caption: ['Artifacts', 'Every letter, comparison and quote it produces.'], chapter: 8 },
  { click: '.ag-art[data-ag="art"][data-arg="refi"]', waitFor: '#ag-sheet[open]', pause: 2800, caption: ['Your loan today vs the offer', '$164 a month less, paid back in under a year.'] },
  { click: '#ag-sheet [data-ag="startRefi"]', waitFor: '#apply-shell:not([hidden])', pause: 3200, caption: ['Refinance, handed off', 'It fills in what it knows and takes it from there.'], chapter: 9 },
  { click: '[data-ag="closeApply"]', pause: 2600 },
  { click: '[data-ag="avatar"]', waitFor: '#ag-sheet[open]', pause: 1400, caption: ['You set the limits', 'On means it acts on its own. Off means it asks first.'], chapter: 10 },
  { click: '[data-ag="avatarSeg"][data-arg="Permissions"]', pause: 2400 },
  { click: '[data-ag="avatarSeg"][data-arg="Memory"]', pause: 2000, caption: ['It remembers your home', 'Edit anything that’s wrong.'] },
  { click: '#ag-sheet [data-ag="close"]', pause: 500 },
  { click: '[data-ag="menu"]', pause: 1400, caption: ['Light or dark', 'Pick a theme in Settings.'], chapter: 11 },
  { click: '[data-ag="settings"]', pause: 1200 },
  { click: '[data-ag="theme"][data-arg="dark"]', dark: true, pause: 1800 },
  { click: '#ag-sheet [data-ag="close"]', pause: 600 },
  { type: ['#ag-prompt', 'what is my number now?'], caption: ['Ask it anything', 'Your number, the refinance, PMI, insurance, taxes.'], chapter: 12 },
  { press: ['#ag-prompt', 'Enter'], pause: 3400 },
  { click: '[data-ag="avatar"]', waitFor: '#ag-sheet[open]', pause: 800, caption: ['Pause any time', 'It keeps watching, but stops acting.'], chapter: 13 },
  { clickForce: '[data-ag-switch="pause"]', pause: 900 },
  { click: '#ag-sheet [data-ag="close"]', pause: 2400 },
  { caption: ['Supermortgage', 'Your monthly housing cost, down to $0.'], pause: 3000 },
];
const chapterCount = 1 + Math.max(...script.filter((s) => s.chapter !== undefined).map((s) => s.chapter));

async function walk(page, frame, { captions, poster }) {
  const inject = async () => {
    // Demo-only rendering: the closest installed UI font, no scrollbars, and the phone's status chrome.
    await frame.addStyleTag({ content: `:root{--font-ui:"${FONT}",-apple-system,system-ui,sans-serif !important} ::-webkit-scrollbar{display:none}
      .demo-island{position:fixed;left:50%;top:11px;width:126px;height:37px;margin-left:-63px;border-radius:20px;background:#000;z-index:9999;pointer-events:none}
      .demo-status{position:fixed;left:0;right:0;top:0;height:59px;z-index:9998;pointer-events:none;color:#151516;font:600 17px/22px "${FONT}",-apple-system,system-ui,sans-serif;letter-spacing:-.02em}
      html[data-theme="dark"] .demo-status{color:#fcfcfc}
      .demo-status .t{position:absolute;left:39px;top:17px} .demo-status .i{position:absolute;right:27px;top:19px;display:flex;gap:6px;align-items:center}
      .demo-home{position:fixed;left:50%;bottom:8px;width:139px;height:5px;margin-left:-69.5px;border-radius:3px;background:#151516;z-index:9999;pointer-events:none}
      html[data-theme="dark"] .demo-home{background:#fcfcfc}` }).catch(() => {});
    // The status bar, dynamic island and home indicator, drawn in the page so they follow its theme.
    await frame.evaluate(() => {
      if (document.querySelector('.demo-island')) return;
      const wrap = document.createElement('div');
      wrap.innerHTML = `<div class="demo-island"></div>
        <div class="demo-status"><span class="t">9:41</span><span class="i">
          <svg width="19" height="12" viewBox="0 0 19 12"><rect x="0" y="7" width="3.4" height="5" rx="1" fill="currentColor"/><rect x="5.2" y="5" width="3.4" height="7" rx="1" fill="currentColor"/><rect x="10.4" y="2.5" width="3.4" height="9.5" rx="1" fill="currentColor"/><rect x="15.6" y="0" width="3.4" height="12" rx="1" fill="currentColor"/></svg>
          <svg width="17" height="12" viewBox="0 0 17 12"><path d="M8.5 11.6 5.7 8.7a3.9 3.9 0 0 1 5.6 0Zm4.7-4.6a6.7 6.7 0 0 0-9.4 0L1.9 5.1a9.4 9.4 0 0 1 13.2 0Z" fill="currentColor"/></svg>
          <svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="22" height="12" rx="3.5" stroke="currentColor" stroke-opacity=".38" fill="none"/><rect x="2.5" y="2.5" width="18" height="8" rx="2" fill="currentColor"/><path d="M24.3 4.3v4.4a2.3 2.3 0 0 0 0-4.4Z" fill="currentColor" fill-opacity=".38"/></svg>
        </span></div>
        <div class="demo-home"></div>`;
      document.body.append(...wrap.childNodes);
    }).catch(() => {});
  };
  await inject();
  for (const step of script) {
    if (step.caption && captions) await page.evaluate(([t, s]) => window.stage.caption(t, s), step.caption);
    if (step.chapter !== undefined && captions) await page.evaluate((i) => window.stage.chapter(i), step.chapter);
    if (step.wait === 'auto-advance') await frame.waitForSelector('[data-ag="signupOpen"]', { timeout: 15000 });
    if (step.click) { await frame.waitForSelector(step.click, { state: 'visible', timeout: 30000 }); await frame.click(step.click); }
    if (step.clickForce) await frame.click(step.clickForce, { force: true });
    if (step.type) await frame.type(step.type[0], step.type[1], { delay: 70 });
    if (step.press) await frame.press(step.press[0], step.press[1]);
    if (step.dark !== undefined && captions) await page.evaluate((on) => window.stage.dark(on), step.dark);
    if (step.waitFor) await frame.waitForSelector(step.waitFor, { state: 'visible', timeout: 30000 });
    if (step.pause) await page.waitForTimeout(step.pause);
    if (step.poster) { await page.screenshot({ path: poster }); if (posterOnly) return; }
  }
}

async function record(name, { viewport, scale, size, stagePage, captions }) {
  const dir = path.join(out, 'raw');
  fs.mkdirSync(dir, { recursive: true });
  const poster = path.join(out, `${name}-poster.png`);
  const browser = await chromium.launch({ args: ['--hide-scrollbars', '--force-color-profile=srgb', '--font-render-hinting=none'] });
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: scale, ...(posterOnly ? {} : { recordVideo: { dir, size } }) });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log(`[${name}] page error:`, e.message));
  await page.goto(`${base}/web/demo/${stagePage}`);
  await page.evaluate((n) => window.stage.chapters(n), chapterCount);
  await page.evaluate((src) => window.stage.load(src), `${base}${PROTOTYPE}`);
  const frame = page.frame({ name: 'phone' });
  await frame.waitForURL((u) => u.pathname.endsWith('.html') && u.pathname.includes('prototype'), { timeout: 15000 });
  await frame.waitForLoadState('load');
  await page.waitForTimeout(500);
  const started = Date.now();
  try {
    await walk(page, frame, { captions, poster });
  } catch (error) {
    // Where it stopped, for a look: the page and what the prototype had on screen.
    const shot = path.join(out, `debug-${name}.png`);
    await page.screenshot({ path: shot }).catch(() => {});
    const state = await frame.evaluate(() => ({
      main: document.querySelector('main')?.className ?? null,
      doors: document.querySelectorAll('.ag-door').length,
      sheetOpen: !!document.querySelector('#ag-sheet[open]'),
      scrollY: window.scrollY, height: document.documentElement.scrollHeight, inner: window.innerHeight,
    })).catch((e) => String(e));
    console.log(`[${name}] stopped:`, error.message.split('\n')[0], JSON.stringify(state), 'screenshot:', shot);
    await ctx.close().catch(() => {});
    await browser.close().catch(() => {});
    throw error;
  }
  console.log(`[${name}] walked in ${((Date.now() - started) / 1000).toFixed(1)}s`);
  const video = page.video();
  await ctx.close();
  await browser.close();
  if (!video) return { poster };
  const raw = await video.path();
  const target = path.join(dir, `${name}.webm`);
  fs.renameSync(raw, target);
  return { raw: target, poster };
}

function ffmpeg(argv) {
  const r = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...argv], { stdio: 'inherit' });
  if (r.status !== 0) throw new Error(`ffmpeg failed: ${argv.join(' ')}`);
}

function encodeAll(name, { raw, poster }) {
  const jpg = path.join(out, `${name}-poster.jpg`);
  ffmpeg(['-i', poster, '-q:v', '2', jpg]);
  if (!raw) return { poster: jpg };
  const mp4 = path.join(out, `${name}.mp4`);
  const webm = path.join(out, `${name}.webm`);
  // Skip the first half second (the stage settling before the walk begins); the recording is 25fps and stays so.
  ffmpeg(['-ss', '0.5', '-i', raw, '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', mp4]);
  ffmpeg(['-ss', '0.5', '-i', raw, '-c:v', 'libvpx-vp9', '-crf', '32', '-b:v', '0', '-row-mt', '1', '-an', webm]);
  return { mp4, webm, poster: jpg };
}

fs.mkdirSync(out, { recursive: true });
const results = {};
if (!only || only === '16x9') {
  const rec = await record('supermortgage-demo-16x9', { viewport: { width: 1920, height: 1080 }, scale: 1, size: { width: 1920, height: 1080 }, stagePage: 'stage.html', captions: true });
  results['16x9'] = encode ? encodeAll('supermortgage-demo-16x9', rec) : rec;
}
if (!only || only === '9x16') {
  const rec = await record('supermortgage-demo-9x16', { viewport: { width: 780, height: 1688 }, scale: 1, size: { width: 780, height: 1688 }, stagePage: 'phone.html', captions: false });
  results['9x16'] = encode ? encodeAll('supermortgage-demo-9x16', rec) : rec;
}
server.close();
console.log(JSON.stringify(results, null, 2));
