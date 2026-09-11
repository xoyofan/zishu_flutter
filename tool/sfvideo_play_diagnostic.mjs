// 诊断 SFVideo 播放页：路由、解析请求、媒体请求、video 状态与页面截图。
import { createRequire } from 'node:module';
import path from 'node:path';
import { mkdirSync } from 'node:fs';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const base = process.argv[2] || 'http://127.0.0.1:9000';
const url = `${base}/douyu/play/63136`;
const outDir = path.resolve('tool/screenshots/sfvideo/diagnostic');
mkdirSync(outDir, { recursive: true });
const executablePath = 'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe';

const browser = await chromium.launch({
  executablePath,
  headless: true,
  args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio', '--no-sandbox'],
});
const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
const page = await context.newPage();

page.on('console', (message) => console.log(`[console:${message.type()}] ${message.text().slice(0, 500)}`));
page.on('pageerror', (error) => console.log(`[pageerror] ${error.message}`));
page.on('requestfailed', (request) => {
  const target = request.url();
  if (/api\/room|api\/live-stream|\.m3u8|\.flv|douyucdn/i.test(target)) {
    console.log(`[requestfailed] ${request.failure()?.errorText} ${target.slice(0, 300)}`);
  }
});
page.on('response', (response) => {
  const target = response.url();
  if (/api\/room|api\/live-stream|\.m3u8|\.flv|douyucdn/i.test(target)) {
    console.log(`[response] ${response.status()} ${target.slice(0, 300)}`);
  }
});

async function snapshot(seconds) {
  await page.evaluate(() => {
    document.querySelectorAll('.auth-dialog').forEach((el) => { el.style.display = 'none'; });
    document.querySelectorAll('.el-overlay').forEach((el) => {
      if (el.querySelector('.auth-dialog')) el.style.display = 'none';
    });
  });
  const state = await page.evaluate(() => {
    const video = document.querySelector('video');
    const frame = document.querySelector('#play-frame');
    const panel = document.querySelector('.player-panel');
    return {
      href: location.href,
      title: document.title,
      bodyText: document.body.innerText.slice(0, 500),
      hasPlayFrame: Boolean(frame),
      playFrameRect: frame ? frame.getBoundingClientRect().toJSON() : null,
      hasPlayerPanel: Boolean(panel),
      video: video ? {
        currentSrc: video.currentSrc,
        src: video.getAttribute('src'),
        readyState: video.readyState,
        networkState: video.networkState,
        paused: video.paused,
        muted: video.muted,
        currentTime: video.currentTime,
        videoWidth: video.videoWidth,
        videoHeight: video.videoHeight,
        error: video.error ? { code: video.error.code, message: video.error.message } : null,
        opacity: getComputedStyle(video).opacity,
      } : null,
    };
  });
  console.log(`[state:${seconds}s] ${JSON.stringify(state)}`);
  await page.screenshot({ path: path.join(outDir, `play_${seconds}s.png`), fullPage: false });
}

console.log(`[goto] ${url}`);
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
await page.waitForTimeout(2000);
await snapshot(2);
await page.waitForTimeout(6000);
await snapshot(8);
await page.waitForTimeout(12000);
await snapshot(20);

await browser.close();
