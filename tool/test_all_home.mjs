// SFVideo 首页截图 - 使用全平台路由
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const base = 'http://127.0.0.1:9000';
const outDir = path.resolve('tool/screenshots/sfvideo');
mkdirSync(outDir, { recursive: true });

const exeCandidates = [
  'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe',
];
const executablePath = exeCandidates.find((p) => require('node:fs').existsSync(p));
if (!executablePath) throw new Error('chromium not found');

const hideAuthDialog = `
  document.querySelectorAll('.auth-dialog, .el-overlay').forEach(el => {
    if (el.querySelector('.auth-dialog') || el.classList.contains('auth-dialog')) {
      el.style.display = 'none';
    }
  });
`;

async function main() {
  const browser = await chromium.launch({ executablePath, headless: true, args: ['--no-sandbox'] });
  
  // 测试 1920x1080 桌面首页
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
  const page = await context.newPage();
  
  console.log('加载全平台首页 /all ...');
  await page.goto(`${base}/all`, { waitUntil: 'domcontentloaded', timeout: 20000 });
  
  // 等待数据加载
  console.log('等待数据加载 (20s)...');
  await page.waitForTimeout(20000);
  
  // 滚动触发懒加载
  await page.evaluate(() => window.scrollBy(0, 500));
  await page.waitForTimeout(3000);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(1000);
  
  // 隐藏登录弹窗
  await page.evaluate(hideAuthDialog);
  await page.waitForTimeout(500);
  
  // 检查页面内容
  const content = await page.evaluate(() => document.body.innerText.slice(0, 300));
  console.log('页面内容预览:', content);
  
  // 检查是否有房间卡片
  const roomCount = await page.evaluate(() => document.querySelectorAll('.room-card, [class*="room"]').length);
  console.log('房间元素数量:', roomCount);
  
  await page.screenshot({ path: path.join(outDir, 'desktop_all_home.png') });
  console.log('截图保存: desktop_all_home.png');
  
  await browser.close();
}

main().catch(console.error);
