// 补截首页（等图片懒加载完成）+ 手机播放页
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

async function main() {
  const browser = await chromium.launch({
    executablePath: exe, headless: true,
    args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio', '--no-sandbox'],
  });

  // 1920x1080 首页（等更久）
  {
    const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
    const page = await ctx.newPage();
    await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.evaluate((s) => localStorage.setItem('lemon_live.auth', JSON.stringify(s)), session);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.goto(`${base}/all`, { waitUntil: 'domcontentloaded', timeout: 15000 });
    // 等够久让懒加载图片完成
    for (let i = 0; i < 12; i++) {
      await page.waitForTimeout(2000);
      const loaded = await page.evaluate(() => {
        const imgs = document.querySelectorAll('.room-card img, [class*="RoomCard"] img');
        if (imgs.length === 0) return 0;
        return [...imgs].filter(img => img.complete && img.naturalWidth > 0).length;
      });
      console.log(`  图片加载进度: ${loaded}/${await page.evaluate(() => document.querySelectorAll('.room-card img, [class*="RoomCard"] img').length)}`);
      if (loaded >= 10) break;
    }
    await page.evaluate(() => window.scrollBy(0, 400));
    await page.waitForTimeout(2000);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(500);
    await page.evaluate(() => document.querySelectorAll('.el-overlay').forEach(el => el.style.display = 'none'));
    await page.screenshot({ path: path.join(outDir, '1920x1080_logged_home.png'), fullPage: false });
    console.log('  -> 1920x1080_logged_home.png');
    await ctx.close();
  }

  // 360x640 手机播放页（单独，带更长等待）
  {
    const ctx = await browser.newContext({ viewport: { width: 360, height: 640 } });
    const page = await ctx.newPage();
    await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.evaluate((s) => localStorage.setItem('lemon_live.auth', JSON.stringify(s)), session);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.goto(`${base}/douyu/play/63136`, { waitUntil: 'domcontentloaded', timeout: 20000 });
    // 等视频
    for (let i = 0; i < 20; i++) {
      await page.waitForTimeout(1000);
      const info = await page.evaluate(() => {
        const v = document.querySelector('video');
        return v ? { rs: v.readyState, w: v.videoWidth } : null;
      });
      if (info && info.rs >= 3 && info.w > 0) { console.log(`  video ready: ${JSON.stringify(info)}`); break; }
    }
    await page.waitForTimeout(2000);
    await page.evaluate(() => document.querySelectorAll('.el-overlay').forEach(el => el.style.display = 'none'));
    await page.screenshot({ path: path.join(outDir, '360x640_mobile_play.png'), fullPage: false });
    console.log('  -> 360x640_mobile_play.png');
    await ctx.close();
  }

  await browser.close();
  console.log('\n完成!');
}

main().catch(console.error);
