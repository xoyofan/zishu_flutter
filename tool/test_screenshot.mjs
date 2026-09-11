// SFVideo 首页截图测试（单个视口）
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
  
  // 测试 640x800 首页
  const context = await browser.newContext({ viewport: { width: 640, height: 800 } });
  const page = await context.newPage();
  
  console.log('加载首页...');
  await page.goto(`${base}/`, { waitUntil: 'domcontentloaded', timeout: 20000 });
  
  // 等待更长时间让数据加载
  console.log('等待数据加载 (15s)...');
  await page.waitForTimeout(15000);
  
  // 滚动触发懒加载
  await page.evaluate(() => window.scrollBy(0, 500));
  await page.waitForTimeout(3000);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(1000);
  
  // 隐藏登录弹窗
  await page.evaluate(hideAuthDialog);
  await page.waitForTimeout(500);
  
  // 检查页面内容
  const content = await page.evaluate(() => document.body.innerText.slice(0, 500));
  console.log('页面内容预览:', content.slice(0, 200));
  
  await page.screenshot({ path: path.join(outDir, 'test_home_640.png') });
  console.log('截图保存: test_home_640.png');
  
  await browser.close();
}

main().catch(console.error);
