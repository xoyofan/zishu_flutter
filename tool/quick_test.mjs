// 快速首页截图
import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright-core/index.js');

const outDir = path.resolve('tool/screenshots/sfvideo');
mkdirSync(outDir, { recursive: true });

const exe = 'C:/Users/XXF/AppData/Local/ms-playwright/chromium-1228/chrome-win64/chrome.exe';

async function main() {
  const browser = await chromium.launch({ executablePath: exe, headless: true, args: ['--no-sandbox'] });
  const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
  const page = await context.newPage();
  
  // 监听网络请求
  page.on('request', req => {
    if (req.url().includes('/api/')) console.log('API:', req.url().slice(0, 80));
  });
  
  console.log('加载 /all ...');
  try {
    await page.goto('http://127.0.0.1:9000/all', { waitUntil: 'networkidle', timeout: 30000 });
  } catch(e) {
    console.log('导航超时，继续...');
  }
  
  await page.waitForTimeout(5000);
  
  // 隐藏登录
  await page.evaluate(() => {
    document.querySelectorAll('.auth-dialog, .el-overlay').forEach(el => el.style.display = 'none');
  });
  
  const roomCount = await page.evaluate(() => {
    const cards = document.querySelectorAll('[class*="room-card"], [class*="RoomCard"]');
    return cards.length;
  });
  console.log('房间卡片数:', roomCount);
  
  const text = await page.evaluate(() => document.body.innerText.slice(0, 200));
  console.log('文本:', text);
  
  await page.screenshot({ path: path.join(outDir, 'desktop_all_home.png') });
  console.log('OK');
  await browser.close();
}

main().catch(console.error);
