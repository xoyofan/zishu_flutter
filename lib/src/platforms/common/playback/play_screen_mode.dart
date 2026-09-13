/// 播放页窗口呈现模式(对齐参考实现 pure_live 的 `VideoMode` 三态)。
///
/// 三态语义:
/// - [normal]     常规布局:房间头 + 视频舞台 + 信息侧栏,控制条常显;
/// - [widescreen] 网页全屏:视频区占满窗口、隐藏房间头与侧栏,但**不动**系统窗口;
/// - [fullscreen] 在 [widescreen] 基础上再请求系统窗口全屏(无边框、覆盖任务栏),
///                控制条进入自动隐藏。
///
/// 本枚举是「页面呈现」的唯一真源:布局、控制条图标、自动隐藏、快捷键分派、
/// 平台窗口调用全部由它派生,禁止再各自维护一份本地 bool(旧实现
/// `PlayView._immersive` 与平台 `window_manager` 状态互不感知,是全屏错位的根因)。
library;

enum PlayScreenMode { normal, widescreen, fullscreen }

extension PlayScreenModeX on PlayScreenMode {
  /// 是否需要隐藏页面 chrome(房间头/侧栏)并启用控制条自动隐藏。
  bool get hidesChrome => this != PlayScreenMode.normal;

  /// 是否需要系统窗口全屏(只有 [PlayScreenMode.fullscreen] 需要)。
  bool get wantsSystemFullscreen => this == PlayScreenMode.fullscreen;

  /// 是否处于「网页全屏」态:视频铺满窗口、隐藏 chrome,但不请求系统窗口全屏。
  bool get isWidescreen => this == PlayScreenMode.widescreen;

  /// 是否处于「系统全屏」态(控制条按钮据此切换图标/激活色)。
  bool get isFullscreen => this == PlayScreenMode.fullscreen;

  /// 中文标签:控制条 tooltip 与测试失败信息用。
  String get label => switch (this) {
    PlayScreenMode.normal => '常规',
    PlayScreenMode.widescreen => '网页全屏',
    PlayScreenMode.fullscreen => '全屏',
  };
}
