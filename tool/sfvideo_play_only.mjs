// 单独截 SFVideo 播放页（隔离上下文，等待视频首帧渲染）
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const base = 'http://127.0.0.1:9000';
const outDir = path.resolve('tool/screenshots/sfvideo');
mkdirSync(outDir, { recursive: true });
const exe = 'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe';

const session = JSON.parse(readFileSync('tool/screenshots/sfvideo_session.json', 'utf8'));

async function waitForVideo(page, timeoutMs = 25000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const ready = await page.evaluate(() => {
      const v = document.querySelector('video');
      return v ? { rs: v.readyState, w: v.videoWidth, h: v.videoHeight } : null;
    });
    if (ready && ready.rs >= 3 && ready.w > 0) return ready;
    await page.waitForTimeout(500);
  }
  return null;
}

const viewports = [
  { name: '1920x1080_desktop', width: 1920, height: 1080 },
  { name: '360x640_mobile',    width: 360,  height: 640 },
];

async function main() {
  const browser = await chromium.launch({
    executablePath: exe,
    headless: true,
    args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio', '--no-sandbox'],
  });

  for (const vp of viewports) {
    console.log(`\n=== ${vp.name} ===`);
    const context = await browser.newContext({ viewport: { width: vp.width, height: vp.height } });
    const page = await context.newPage();

    // 先注入登录态
    await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.evaluate((s) => localStorage.setItem('lemon_live.auth', JSON.stringify(s)), session);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2000);

    // 导航到播放页
    await page.goto(`${base}/douyu/play/63136`, { waitUntil: 'domcontentloaded', timeout: 20000 });

    // 等待视频首帧
    const videoInfo = await waitForVideo(page, 30000);
    console.log(`  video: ${JSON.stringify(videoInfo)}`);
    await page.waitForTimeout(3000);

    // 隐藏弹窗
    await page.evaluate(() => {
      document.querySelectorAll('.el-overlay, .mute-hint').forEach(el => {
        if (el.querySelector('.auth-dialog')) el.style.display = 'none';
      });
    });
    await page.waitForTimeout(500);

    const filename = `${vp.name}_play.png`;
    await page.screenshot({ path: path.join(outDir, filename), fullPage: false });
    console.log(`  -> ${filename}`);

    await context.close();
  }

  await browser.close();
  console.log('\n完成!');
}

main().catch(console.error);
