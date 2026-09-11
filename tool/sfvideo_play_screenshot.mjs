// SFVideo 播放页截图（修正路由 + 等待首帧渲染）
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const base = 'http://127.0.0.1:9000';
const outDir = path.resolve('tool/screenshots/sfvideo');
mkdirSync(outDir, { recursive: true });

const exe = 'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe';

const hideAllOverlays = `
  document.querySelectorAll('.auth-dialog, .el-overlay, .mute-hint').forEach(el => el.style.display = 'none');
`;

async function waitForVideo(page, timeoutMs = 25000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const ready = await page.evaluate(() => {
      const v = document.querySelector('video');
      return v ? { rs: v.readyState, w: v.videoWidth, h: v.videoHeight, op: parseFloat(getComputedStyle(v).opacity) } : null;
    });
    if (ready && ready.rs >= 3 && ready.w > 0) return ready;
    await page.waitForTimeout(500);
  }
  return null;
}

const viewports = [
  { name: '360x640_mobile',       width: 360,  height: 640 },
  { name: '640x800_compact',      width: 640,  height: 800 },
  { name: '768x1024_tablet',      width: 768,  height: 1024 },
  { name: '1024x768_tablet_land', width: 1024, height: 768 },
  { name: '1366x1024_ipad_pro',   width: 1366, height: 1024 },
  { name: '1920x1080_desktop',    width: 1920, height: 1080 },
  { name: '2560x1440_2k',         width: 2560, height: 1440 },
];

async function main() {
  const browser = await chromium.launch({
    executablePath: exe,
    headless: true,
    args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio', '--no-sandbox'],
  });

  for (const vp of viewports) {
    console.log(`\n=== ${vp.width}x${vp.height} ===`);
    const context = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 1 });
    const page = await context.newPage();

    // 正确路由: /:site/play/:id
    await page.goto(`${base}/douyu/play/63136`, { waitUntil: 'domcontentloaded', timeout: 15000 });
    const videoInfo = await waitForVideo(page);
    console.log(`  video: ${JSON.stringify(videoInfo)}`);

    // 等 2s 让画面稳定
    await page.waitForTimeout(2000);

    // 隐藏弹窗
    await page.evaluate(hideAllOverlays);
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
