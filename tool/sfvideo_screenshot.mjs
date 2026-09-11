// SFVideo 响应式布局截图脚本（隐藏登录弹窗）
// 用法: node tool/sfvideo_screenshot.mjs [--url http://127.0.0.1:9000] [--out screenshots]

import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => {
  if (v.startsWith('--')) acc.push([v.slice(2), arr[i + 1]]);
  return acc;
}, []));

const base = args.url ?? 'http://127.0.0.1:9000';
const outDir = args.out ?? path.resolve('tool/screenshots/sfvideo');
mkdirSync(outDir, { recursive: true });

const exeCandidates = [
  'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe',
  'C:/Users/XXF/AppData/Local/ms-playwright/chromium_headless_shell-1228/chrome-headless-shell-win64/chrome-headless-shell.exe',
];
const executablePath = exeCandidates.find((p) => require('node:fs').existsSync(p));
if (!executablePath) throw new Error('chromium executable not found');

// 响应式断点尺寸 (参考 SFVideoLive breakpoints.ts)
const viewports = [
  { name: '360x640_mobile',       width: 360,  height: 640,  desc: '手机竖屏' },
  { name: '640x800_compact',      width: 640,  height: 800,  desc: 'Compact 断点' },
  { name: '768x1024_tablet',      width: 768,  height: 1024, desc: 'Mobile/Tablet 竖屏' },
  { name: '1024x768_tablet_land', width: 1024, height: 768,  desc: 'PlayStack 断点' },
  { name: '1366x1024_ipad_pro',   width: 1366, height: 1024, desc: 'iPad Pro 横屏' },
  { name: '1920x1080_desktop',    width: 1920, height: 1080, desc: 'Wide 桌面' },
  { name: '2560x1440_2k',         width: 2560, height: 1440, desc: '2K 宽屏' },
];

// 需要截图的页面
const pages = [
  { name: 'home',      path: '/',            desc: '首页' },
  { name: 'category',  path: '/category',    desc: '分类页' },
  { name: 'follow',    path: '/follow',      desc: '关注页' },
  { name: 'play',      path: '/douyu/63136', desc: '播放页-斗鱼' },
];

// 隐藏登录弹窗的 JS
const hideAuthDialog = `
  // 隐藏 auth-dialog
  const authDialog = document.querySelector('.auth-dialog');
  if (authDialog) authDialog.style.display = 'none';
  // 遮罩层
  const overlays = document.querySelectorAll('.el-overlay');
  overlays.forEach(el => {
    if (el.querySelector('.auth-dialog')) el.style.display = 'none';
  });
  // 移动端底部可能有的登录按钮
  document.querySelectorAll('[class*="auth"], [class*="login"]').forEach(el => {
    if (el.closest('.auth-dialog')) el.style.display = 'none';
  });
`;

async function main() {
  const browser = await chromium.launch({
    executablePath,
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  console.log(`输出目录: ${outDir}`);

  for (const vp of viewports) {
    console.log(`\n=== ${vp.desc} (${vp.width}x${vp.height}) ===`);
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();

    for (const pg of pages) {
      const url = `${base}${pg.path}`;
      const filename = `${vp.name}_${pg.name}.png`;
      console.log(`  ${pg.desc}: ${url}`);

      try {
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
        // 等待房间列表或主要内容加载
        await page.waitForTimeout(8000);
        // 滚动一下触发懒加载
        await page.evaluate(() => window.scrollBy(0, 300));
        await page.waitForTimeout(2000);
        await page.evaluate(() => window.scrollTo(0, 0));
        await page.waitForTimeout(500);

        // 隐藏登录弹窗
        await page.evaluate(hideAuthDialog);
        await page.waitForTimeout(500);

        // 截图
        await page.screenshot({
          path: path.join(outDir, filename),
          fullPage: false, // 仅视口截图
        });
        console.log(`    -> ${filename}`);
      } catch (e) {
        console.log(`    -> 失败: ${e.message}`);
      }
    }

    await context.close();
  }

  await browser.close();
  console.log(`\n完成! 截图保存在: ${outDir}`);
}

main().catch(console.error);
