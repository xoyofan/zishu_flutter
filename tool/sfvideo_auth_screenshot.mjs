// SFVideo 登录态截图：注入假 session 后截 follow 页 + 各断点
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const base = 'http://127.0.0.1:9000';
const outDir = path.resolve('tool/screenshots/sfvideo');
mkdirSync(outDir, { recursive: true });

const exe = 'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe';

// 注入假登录态（未来 7 天有效）
const FAKE_SESSION = {
  token: 'fake-token-for-screenshot',
  expiresAt: Date.now() + 7 * 24 * 60 * 60 * 1000,
  user: { username: 'screenshot_user', nickname: '截图专用' },
};

const hideAllOverlays = `
  document.querySelectorAll('.auth-dialog, .el-overlay, .mute-hint').forEach(el => el.style.display = 'none');
`;

async function waitForContent(page, selector, timeoutMs = 15000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const count = await page.evaluate((sel) => document.querySelectorAll(sel).length, selector);
    if (count > 0) return true;
    await page.waitForTimeout(500);
  }
  return false;
}

const viewports = [
  { name: '360x640_mobile',       width: 360,  height: 640 },
  { name: '640x800_compact',      width: 640,  height: 800 },
  { name: '768x1024_tablet',      width: 768,  height: 1024 },
  { name: '1024x768_tablet_land', width: 1024, height: 768 },
  { name: '1366x1024_ipad_pro',   width: 1366, height: 1024 },
  { name: '1920x1080_desktop',    width: 1920, height: 1080 },
];

const pages = [
  { name: 'follow',  path: '/follow',  desc: '关注页' },
  { name: 'home',    path: '/all',     desc: '首页(登录态)' },
  { name: 'play',    path: '/douyu/play/63136', desc: '播放页' },
];

async function main() {
  const browser = await chromium.launch({
    executablePath: exe,
    headless: true,
    args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio', '--no-sandbox'],
  });

  for (const vp of viewports) {
    console.log(`\n=== ${vp.name} (${vp.width}x${vp.height}) ===`);
    const context = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 1 });
    const page = await context.newPage();

    // 先注入登录态
    await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.evaluate((session) => {
      localStorage.setItem('lemon_live.auth', JSON.stringify(session));
    }, FAKE_SESSION);
    await page.waitForTimeout(500);

    for (const pg of pages) {
      const filename = `${vp.name}_${pg.name}.png`;
      console.log(`  ${pg.desc}: ${base}${pg.path}`);

      try {
        await page.goto(`${base}${pg.path}`, { waitUntil: 'domcontentloaded', timeout: 20000 });
        await page.waitForTimeout(10000); // 等数据加载
        await page.evaluate(() => window.scrollBy(0, 300));
        await page.waitForTimeout(2000);
        await page.evaluate(() => window.scrollTo(0, 0));
        await page.waitForTimeout(500);
        await page.evaluate(hideAllOverlays);
        await page.waitForTimeout(500);
        await page.screenshot({ path: path.join(outDir, filename), fullPage: false });
        console.log(`    -> ${filename}`);
      } catch (e) {
        console.log(`    失败: ${e.message.slice(0, 80)}`);
      }
    }

    await context.close();
  }

  await browser.close();
  console.log('\n完成!');
}

main().catch(console.error);
