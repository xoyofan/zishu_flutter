// 补充剩余截图
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const base = 'http://127.0.0.1:9000';
const outDir = path.resolve('tool/screenshots/sfvideo');
mkdirSync(outDir, { recursive: true });

const exe = 'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe';

const hideAuthDialog = `
  document.querySelectorAll('.auth-dialog, .el-overlay').forEach(el => {
    if (el.querySelector('.auth-dialog') || el.classList.contains('auth-dialog')) {
      el.style.display = 'none';
    }
  });
`;

async function screenshot(page, url, filename) {
  console.log(`  ${url} -> ${filename}`);
  try {
    await page.goto(`${base}${url}`, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForTimeout(12000);
    await page.evaluate(() => window.scrollBy(0, 400));
    await page.waitForTimeout(2000);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(500);
    await page.evaluate(hideAuthDialog);
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(outDir, filename) });
  } catch(e) {
    console.log(`    失败: ${e.message.slice(0, 80)}`);
  }
}

async function main() {
  const browser = await chromium.launch({ executablePath: exe, headless: true, args: ['--no-sandbox'] });

  // iPad Pro 1366x1024
  console.log('\n=== iPad Pro (1366x1024) ===');
  let ctx = await browser.newContext({ viewport: { width: 1366, height: 1024 } });
  let page = await ctx.newPage();
  await screenshot(page, '/category', '1366x1024_ipad_pro_category.png');
  await screenshot(page, '/follow', '1366x1024_ipad_pro_follow.png');
  await screenshot(page, '/douyu/63136', '1366x1024_ipad_pro_play.png');
  await ctx.close();

  // Desktop 1920x1080
  console.log('\n=== Desktop (1920x1080) ===');
  ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
  page = await ctx.newPage();
  await screenshot(page, '/all', '1920x1080_desktop_home.png');
  await screenshot(page, '/category', '1920x1080_desktop_category.png');
  await screenshot(page, '/follow', '1920x1080_desktop_follow.png');
  await screenshot(page, '/douyu/63136', '1920x1080_desktop_play.png');
  await ctx.close();

  // 2K 2560x1440
  console.log('\n=== 2K (2560x1440) ===');
  ctx = await browser.newContext({ viewport: { width: 2560, height: 1440 } });
  page = await ctx.newPage();
  await screenshot(page, '/all', '2560x1440_2k_home.png');
  await ctx.close();

  await browser.close();
  console.log('\n完成!');
}

main().catch(console.error);
