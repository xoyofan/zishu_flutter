// SFVideo 真实登录态截图：用 Playwright 登录 xoyofan sf2012 后截 follow + category
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
  document.querySelectorAll('.el-overlay, .mute-hint').forEach(el => {
    if (el.querySelector('.auth-dialog')) el.style.display = 'none';
  });
`;

async function main() {
  const browser = await chromium.launch({
    executablePath: exe,
    headless: true,
    args: ['--autoplay-policy=no-user-gesture-required', '--mute-audio', '--no-sandbox'],
  });

  // 登录流程
  console.log('=== 登录流程 ===');
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
  const page = await context.newPage();

  page.on('console', (m) => {
    const t = m.text();
    if (t.includes('auth') || t.includes('登录')) console.log('[console]', t.slice(0, 200));
  });

  await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(2500);

  // 未登录时 auth-dialog 会自动弹出；若没弹出再手动点登录按钮
  const dialogVisible = await page.locator('.auth-dialog').isVisible().catch(() => false);
  if (!dialogVisible) {
    await page.locator('button.nav-item[title="登录"], button.nav-item[aria-label="登录"]').first().click();
  }
  await page.waitForSelector('.auth-dialog', { timeout: 10000 });
  console.log('auth-dialog 已打开 (自动弹出=' + dialogVisible + ')');

  // 在对话框内填写用户名密码
  await page.locator('.auth-dialog input[autocomplete="username"]').fill('xoyofan');
  await page.locator('.auth-dialog input[type="password"]').first().fill('sf2012');
  await page.waitForTimeout(300);

  // 提交
  await page.locator('.auth-dialog .auth-dialog__submit').click();
  console.log('已提交登录');

  // 等待登录完成（localStorage 出现 token）
  let logged = null;
  for (let i = 0; i < 20; i++) {
    await page.waitForTimeout(1000);
    logged = await page.evaluate(() => {
      const raw = localStorage.getItem('lemon_live.auth');
      if (!raw) return null;
      try { return JSON.parse(raw); } catch { return null; }
    });
    if (logged?.token) break;
  }

  console.log('登录状态:', logged ? `成功 user=${logged.user?.username}` : '失败');

  // 保存登录态到文件，后续脚本可复用
  if (logged?.token) {
    mkdirSync('tool/screenshots', { recursive: true });
    const { writeFileSync } = await import('node:fs');
    writeFileSync('tool/screenshots/sfvideo_session.json', JSON.stringify(logged, null, 2));
    console.log('登录态已保存: tool/screenshots/sfvideo_session.json');
  }

  // 截图各页面（登录态）
  const pages = [
    { name: 'follow', path: '/follow', desc: '关注页' },
    { name: 'category', path: '/douyu/category', desc: '分类页' },
    { name: 'home', path: '/all', desc: '首页' },
    { name: 'play', path: '/douyu/play/63136', desc: '播放页' },
  ];

  for (const pg of pages) {
    const filename = `1920x1080_logged_${pg.name}.png`;
    console.log(`\n=== ${pg.desc} ===`);

    try {
      await page.goto(`${base}${pg.path}`, { waitUntil: 'domcontentloaded', timeout: 20000 });
      await page.waitForTimeout(12000);
      await page.evaluate(() => window.scrollBy(0, 400));
      await page.waitForTimeout(2000);
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(500);
      await page.evaluate(hideAllOverlays);
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(outDir, filename), fullPage: false });
      console.log(`  -> ${filename}`);
    } catch (e) {
      console.log(`  失败: ${e.message.slice(0, 100)}`);
    }
  }

  await context.close();
  await browser.close();
  console.log('\n完成!');
}

main().catch(console.error);
