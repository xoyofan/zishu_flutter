// E7 douyu E2E 无头验证运行器。
// 用法: node tool/e7_run.mjs [--url http://127.0.0.1:8090] [--site douyu] [--room 63136] [--timeout 45000]
// 复用本机已有的 playwright-core（mcp-gateways 自带）与 ms-playwright chromium，无需 npm install。
import { createRequire } from 'node:module';
import path from 'node:path';
import os from 'node:os';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => {
  if (v.startsWith('--')) acc.push([v.slice(2), arr[i + 1]]);
  return acc;
}, []));
const base = args.url ?? 'http://127.0.0.1:8090';
const site = args.site ?? 'douyu';
const room = args.room ?? '63136';
const timeoutMs = Number(args.timeout ?? 45000);

const exeCandidates = [
  'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe',
  'C:/Users/XXF/AppData/Local/ms-playwright/chromium_headless_shell-1228/chrome-headless-shell-win64/chrome-headless-shell.exe',
];
const executablePath = exeCandidates.find((p) => require('node:fs').existsSync(p));
if (!executablePath) throw new Error('chromium executable not found');

const browser = await chromium.launch({
  executablePath,
  headless: true,
  args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio', '--no-sandbox'],
});
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
page.on('console', (m) => {
  const t = m.text();
  if (t.includes('zishuSmoke') || t.includes('smoke')) console.log('[console]', t.slice(0, 300));
});

// GetX web 默认 hash 路由；history 路由则直接 path。两者都试。
const candidates = [`${base}/${site}/play/${room}`, `${base}/#/${site}/play/${room}`];
let used = null;
for (const url of candidates) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(2500);
  const state = await page.evaluate(() => window.zishuSmoke ?? null).catch(() => null);
  if (state) { used = url; break; }
}
if (!used) {
  console.log(JSON.stringify({ ok: false, reason: 'zishuSmoke 未出现（路由未命中或页面未加载）', candidates }, null, 2));
  await browser.close();
  process.exit(1);
}
console.log('[e7] route hit:', used);

const deadline = Date.now() + timeoutMs;
let last = null;
let videoSample = null;
while (Date.now() < deadline) {
  last = await page.evaluate(() => {
    const s = window.zishuSmoke ?? {};
    const v = document.querySelector('video');
    return {
      phase: s.phase ?? null,
      error: s.error ?? null,
      danmaku: s.danmaku ?? 0,
      site: s.site ?? null,
      roomId: s.roomId ?? null,
      title: s.info?.title ?? s.title ?? null,
      video: v ? { readyState: v.readyState, w: v.videoWidth, h: v.videoHeight, t: v.currentTime, paused: v.paused } : null,
    };
  }).catch(() => null);
  if (last?.video && last.video.readyState >= 2 && last.video.w > 0) {
    if (!videoSample) videoSample = { t0: last.video.t, at: Date.now() };
    else if (Date.now() - videoSample.at >= 4000) {
      videoSample.t1 = last.video.t;
      videoSample.elapsed = (Date.now() - videoSample.at) / 1000;
      break;
    }
  }
  await page.waitForTimeout(1000);
}

const video = last?.video ?? null;
const checks = {
  routeHit: !!used,
  noError: last?.phase !== 'error' && !last?.error,
  videoReady: !!video && video.readyState >= 2 && video.w > 0,
  timeAdvancing: !!videoSample && Math.abs((videoSample.t1 ?? 0) - videoSample.t0) > 0.5,
  danmakuReceived: (last?.danmaku ?? 0) >= 1,
};
const ok = checks.routeHit && checks.noError && checks.videoReady && checks.timeAdvancing;
console.log(JSON.stringify({
  ok,
  checks,
  smoke: { phase: last?.phase, error: last?.error, danmaku: last?.danmaku, site: last?.site, roomId: last?.roomId, title: last?.title },
  video,
  timeSample: videoSample ? { t0: videoSample.t0, t1: videoSample.t1, seconds: videoSample.elapsed } : null,
}, null, 2));

await browser.close();
process.exit(ok ? 0 : 1);
