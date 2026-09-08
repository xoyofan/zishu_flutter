#!/usr/bin/env node
/**
 * E7 播放冒烟脚本（playwright 无头）。
 *
 * 前置：
 *   1. `.\tool\build-web.ps1 -StreamApiUrl 'http://127.0.0.1:8766'` 构建成功；
 *   2. streaming-server 已启动（解析/代理可用）；
 *   3. 以任意静态服务器伺服 build/web（如 `npx serve build/web -l 8090`）。
 *
 * 用法：
 *   node tool/smoke_play.mjs --room <roomId> [--url http://127.0.0.1:8090]
 *                            [--site douyu] [--timeout 30000]
 *
 * 流程：打开 {url}/#/{site}/play/{room}（GetX web 默认 hash 路由；失败自动重试
 * history 形态 {url}/{site}/play/{room}）→ 等待 #smoke-video 出现 → 30s 内断言
 * video.readyState>=2 且 videoWidth>0 → 再等 5s 断言 currentTime 增长 >0.5 →
 * 输出 JSON 结果（每项断言 pass/fail + 实测值），整体通过 exit 0 否则 exit 1。
 *
 * playwright 解析顺序：本地 node_modules → 全局 npm(@playwright/cli) →
 * opencode mcp-gateway 自带副本；三者皆缺时给出安装提示退出 2。
 */

import { pathToFileURL } from 'node:url';
import path from 'node:path';

// ---- 参数解析 -------------------------------------------------------------

function parseArgs(argv) {
  const args = { url: 'http://127.0.0.1:8090', site: 'douyu', room: '', timeout: 30000 };
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--url') args.url = argv[++i];
    else if (k === '--site') args.site = argv[++i];
    else if (k === '--room') args.room = argv[++i];
    else if (k === '--timeout') args.timeout = Number(argv[++i]);
    else if (k === '--help' || k === '-h') args.help = true;
  }
  return args;
}

const args = parseArgs(process.argv);
if (args.help || !args.room) {
  console.error('用法: node tool/smoke_play.mjs --room <roomId> [--url URL] [--site douyu] [--timeout 30000]');
  process.exit(args.help ? 0 : 2);
}

// ---- playwright 解析（多副本兜底） ----------------------------------------

async function loadPlaywright() {
  const candidates = [
    'playwright',
    path.join(process.env.APPDATA ?? '', 'npm/node_modules/@playwright/cli/node_modules/playwright/index.mjs'),
    'C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/@playwright/test/node_modules/playwright/index.mjs',
    'C:/Users/XXF/.config/opencode/mcp-gateways/servers/playwright/node_modules/playwright/index.mjs',
  ];
  for (const spec of candidates) {
    if (!spec) continue;
    try {
      const mod = spec.includes(':') || spec.startsWith('.')
        ? await import(pathToFileURL(spec).href)
        : await import(spec);
      if (mod?.chromium) return mod;
    } catch (_) { /* 试下一个 */ }
  }
  console.error('未找到 playwright：请 `npm i -D playwright` 或全局安装后重试。');
  process.exit(2);
}

// ---- 断言结果收集 ----------------------------------------------------------

const results = [];
function record(name, pass, actual, detail = '') {
  results.push({ name, pass, actual, ...(detail ? { detail } : {}) });
  console.error(`[${pass ? 'PASS' : 'FAIL'}] ${name} ${actual}${detail ? '  ' + detail : ''}`);
}

async function main() {
  const { chromium } = await loadPlaywright();

  // 网关用系统 Chrome；缺 bundled chromium 时退回 channel:'chrome'。
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (_) {
    browser = await chromium.launch({ headless: true, channel: 'chrome' });
  }
  const page = await browser.newPage();

  const smokeVideoPresent = () => {
    const v = document.querySelector('#smoke-video');
    return !!v;
  };

  const openWith = async (target) => {
    await page.goto(target, { waitUntil: 'domcontentloaded', timeout: args.timeout });
    return page.waitForSelector('#smoke-video', { timeout: args.timeout }).then(() => true).catch(() => false);
  };

  const hashUrl = `${args.url.replace(/\/+$/, '')}/#/${args.site}/play/${args.room}`;
  const pathUrl = `${args.url.replace(/\/+$/, '')}/${args.site}/play/${args.room}`;

  let videoFound = await openWith(hashUrl);
  let usedUrl = hashUrl;
  if (!videoFound) {
    console.error(`[smoke] hash 路由未出现 video，重试 history 形态: ${pathUrl}`);
    videoFound = await openWith(pathUrl);
    usedUrl = pathUrl;
  }
  record('video-element-appeared', videoFound, videoFound ? 'yes' : 'no', `url=${usedUrl}`);
  if (!videoFound) {
    // 尽量带出页面上的错误信息帮助定位
    const smoke = await page.evaluate(() => window.zishuSmoke ?? null).catch(() => null);
    console.log(JSON.stringify({ url: usedUrl, results, zishuSmoke: smoke }, null, 2));
    await browser.close();
    process.exit(1);
  }

  // 断言 1：30s 内 readyState>=2 且 videoWidth>0（拿到可播流并解码出画面）。
  const readyOk = await page
    .waitForFunction(
      () => {
        const v = document.querySelector('#smoke-video');
        return !!v && v.readyState >= 2 && v.videoWidth > 0;
      },
      { timeout: args.timeout, polling: 250 },
    )
    .then(() => true)
    .catch(() => false);

  const metrics = await page.evaluate(() => {
    const v = document.querySelector('#smoke-video');
    if (!v) return null;
    return {
      readyState: v.readyState,
      videoWidth: v.videoWidth,
      videoHeight: v.videoHeight,
      currentTime: v.currentTime,
      paused: v.paused,
    };
  });

  record(
    'video-ready-with-frame',
    readyOk,
    metrics ? `readyState=${metrics.readyState} videoWidth=${metrics.videoWidth}` : 'video missing',
  );

  // 断言 2：再等 5s，currentTime 增长 >0.5（直播流确实在推进）。
  let timeGrowth = null;
  if (metrics) {
    const t0 = metrics.currentTime;
    await page.waitForTimeout(5000);
    const t1 = await page.evaluate(() => {
      const v = document.querySelector('#smoke-video');
      return v ? v.currentTime : NaN;
    });
    timeGrowth = t1 - t0;
  }
  record('playback-advancing', timeGrowth !== null && timeGrowth > 0.5, `growth=${timeGrowth?.toFixed(2) ?? 'n/a'}s`);

  // 附带 phase 信息（页面 zishuSmoke 钩子，便于失败定位）。
  const smoke = await page.evaluate(() => window.zishuSmoke ?? null).catch(() => null);

  const allPass = results.every((r) => r.pass);
  const report = {
    url: usedUrl,
    site: args.site,
    room: args.room,
    pass: allPass,
    assertions: results,
    metrics,
    zishuSmoke: smoke,
  };
  console.log(JSON.stringify(report, null, 2));

  await browser.close();
  process.exit(allPass ? 0 : 1);
}

main().catch((err) => {
  console.error('[smoke] 脚本异常:', err);
  process.exit(1);
});
