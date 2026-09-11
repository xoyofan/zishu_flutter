# tool/ — 验收、冒烟与视觉对比工具

## 对比测试流程(其他电脑复现)

> 目标:把本项目 exe 的实拍界面与 `screenshots/sfvideo/` 的参考基线(SFVideoLive
> 浏览器实拍)并排对比,验证布局/色彩/结构 1:1。**口径注意**:fixture 与真实
> 数据的内容不同,只比布局/色彩/结构/密度,不比像素;Windows 与 Web 渲染的
> 字体度量差异放宽到几何级。

1. **参考基线**:`screenshots/sfvideo/` 已入库,无需重抓。文件名即视口与页面:
   `{width}x{height}_{device}_{page}.png`(home/play/category/follow)。
   如需重抓(参考站改版时):`node tool/sfvideo_screenshot.mjs`(Playwright 无头;
   登录态走 `sfvideo_real_login.mjs`,产出的 `sfvideo_session.json` 含登录
   token,**不入库**)。各脚本头注释有参数说明。
2. **构建本项目 exe**:
   ```bash
   flutter build windows --debug -t lib/main.dart
   # 真实解析版(首页/播放为真实站点数据):
   flutter build windows --debug -t lib/main.dart --dart-define=ZISHU_REAL_PARSER=true
   ```
3. **启动并驱动 exe**(`win_tool.py` 零编译,需 Python 3.10+ 与 Pillow/pyautogui;
   PrintWindow 抓 GPU 合成内容,后台截图不打扰前台):
   ```bash
   py tool/win_tool.py move 60 60 1600 900            # 归位窗口
   py tool/win_tool.py shot tool/screenshots/zishu/exe_home.png
   py tool/win_tool.py click 412 212                  # 点房间卡(屏幕绝对坐标)
   py tool/win_tool.py shot tool/screenshots/zishu/exe_play1.png
   ```
   注意:最小化状态下 Flutter 暂停渲染,恢复(`restore`)后需激活一次窗口
   渲染循环才会继续;`shot` 本身永不激活窗口。
4. **对比**:同视口的 `zishu/*.png` 与 `sfvideo/*.png` 并排比对;逐轮实拍
   按日期留档即可,过期帧删除。

## 文件清单

| 文件/目录 | 用途 | 入库 |
|---|---|---|
| `win_tool.py` | Windows 窗口驱动:PrintWindow 后台截图 / 点击 / 移动窗口 | ✅ |
| `screenshots/sfvideo/` | SFVideoLive 参考基线截图(多视口) | ✅ |
| `screenshots/zishu/*.png` | 本项目 exe 实拍(与参考同视口) | ✅ |
| `screenshots/sfvideo_session.json` | SFVideo 登录 token | ❌ 敏感 |
| `screenshots/zishu/app_*.log` | exe 运行日志 | ❌(`*.log` 全局忽略) |
| `sfvideo_*.mjs` | 参考截图抓取脚本(Playwright 无头) | ✅ |
| `extra_screenshots.mjs` `test_*.mjs` `quick_test.mjs` | 参考站多视口截图辅助 | ✅ |
| `check.ps1` | 全量门禁:pub get → analyze → test → build web | ✅ |
| `build-web.ps1` | legacy Web UI 构建(build/web) | ✅ |
| `e7_run.mjs` | douyu E2E 无头验证(legacy web 链路) | ✅ |
| `smoke_play.mjs` | 播放冒烟(legacy web 链路) | ✅ |
| `serve_web.mjs` | 静态服务器(冒烟用,`node tool/serve_web.mjs [port] [dir]`) | ✅ |
