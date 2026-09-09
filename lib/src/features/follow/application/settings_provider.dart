/// 设置页状态层:Notifier + shared_preferences 持久化。
/// 启动时异步 load(以 hydrated 标记完成),每次变更立即 save。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式选项(当前阶段仅作为设置项持久化,接全局主题由后续任务完成)。
enum ThemeModeChoice {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const ThemeModeChoice(this.label);

  /// UI 文案。
  final String label;

  /// 持久化用的稳定名字。
  String get storageName => name;

  /// 从存储值恢复;未知值回退「跟随系统」。
  static ThemeModeChoice fromName(String? name) => switch (name) {
        'light' => ThemeModeChoice.light,
        'dark' => ThemeModeChoice.dark,
        _ => ThemeModeChoice.system,
      };
}

/// 设置状态;[hydrated] 表示是否已完成持久化恢复。
class SettingsState {
  const SettingsState({
    required this.themeMode,
    required this.defaultQuality,
    required this.danmakuEnabled,
    required this.serverUrl,
    this.hydrated = false,
  });

  final ThemeModeChoice themeMode;

  /// 默认画质(与播放页 fixture 画质名对齐)。
  final String defaultQuality;
  final bool danmakuEnabled;

  /// streaming-server 基础地址(Web 端经它访问解析 API)。
  final String serverUrl;
  final bool hydrated;

  /// 画质候选。
  static const List<String> qualityOptions = ['蓝光8M', '超清', '高清', '流畅'];

  /// 服务器地址默认值。
  static const String defaultServerUrl = 'http://127.0.0.1:8787';

  SettingsState copyWith({
    ThemeModeChoice? themeMode,
    String? defaultQuality,
    bool? danmakuEnabled,
    String? serverUrl,
    bool? hydrated,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
      serverUrl: serverUrl ?? this.serverUrl,
      hydrated: hydrated ?? this.hydrated,
    );
  }
}

/// 设置控制器:变更即写盘;读取/写入失败均静默回退,不阻塞 UI。
class SettingsController extends Notifier<SettingsState> {
  // SharedPreferencesAsync 的存储键(带前缀避免与其他模块冲突)。
  static const String _kThemeMode = 'zishu.settings.themeMode';
  static const String _kDefaultQuality = 'zishu.settings.defaultQuality';
  static const String _kDanmakuEnabled = 'zishu.settings.danmakuEnabled';
  static const String _kServerUrl = 'zishu.settings.serverUrl';

  @override
  SettingsState build() {
    // 启动时异步恢复;完成前 UI 先使用默认值(hydrated=false)。
    Future<void>.microtask(_restore);
    return const SettingsState(
      themeMode: ThemeModeChoice.system,
      defaultQuality: '超清',
      danmakuEnabled: true,
      serverUrl: SettingsState.defaultServerUrl,
    );
  }

  /// 从本地存储恢复设置。
  Future<void> _restore() async {
    try {
      // 采用 SharedPreferencesAsync(新版异步 API,按 key 读写平台存储,
      // 不依赖旧版 SharedPreferences 单例缓存)。
      final prefs = SharedPreferencesAsync();
      final mode = await prefs.getString(_kThemeMode);
      final quality = await prefs.getString(_kDefaultQuality);
      final danmaku = await prefs.getBool(_kDanmakuEnabled);
      final server = await prefs.getString(_kServerUrl);
      state = state.copyWith(
        themeMode:
            mode == null ? null : ThemeModeChoice.fromName(mode),
        defaultQuality: quality != null &&
                SettingsState.qualityOptions.contains(quality)
            ? quality
            : null,
        danmakuEnabled: danmaku,
        serverUrl: server != null && server.isNotEmpty ? server : null,
        hydrated: true,
      );
    } catch (_) {
      // 平台存储不可用等异常:静默保留默认值,页面不崩溃。
      state = state.copyWith(hydrated: true);
    }
  }

  /// 设置主题模式并持久化。
  Future<void> setThemeMode(ThemeModeChoice mode) async {
    state = state.copyWith(themeMode: mode);
    try {
      await SharedPreferencesAsync().setString(_kThemeMode, mode.storageName);
    } catch (_) {
      // 写盘失败:内存态仍生效,下次启动回退旧值。
    }
  }

  /// 设置默认画质并持久化。
  Future<void> setDefaultQuality(String quality) async {
    if (!SettingsState.qualityOptions.contains(quality)) return;
    state = state.copyWith(defaultQuality: quality);
    try {
      await SharedPreferencesAsync().setString(_kDefaultQuality, quality);
    } catch (_) {}
  }

  /// 设置弹幕开关并持久化。
  Future<void> setDanmakuEnabled(bool enabled) async {
    state = state.copyWith(danmakuEnabled: enabled);
    try {
      await SharedPreferencesAsync().setBool(_kDanmakuEnabled, enabled);
    } catch (_) {}
  }

  /// 设置服务器地址并持久化(空串视为非法,由调用方先校验)。
  Future<void> setServerUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(serverUrl: trimmed);
    try {
      await SharedPreferencesAsync().setString(_kServerUrl, trimmed);
    } catch (_) {}
  }
}

/// 设置 provider(应用级)。
final settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
