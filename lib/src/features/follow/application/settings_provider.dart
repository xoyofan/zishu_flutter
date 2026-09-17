/// 设置页状态层:Notifier + shared_preferences 持久化。
/// 启动时异步 load(以 hydrated 标记完成),每次变更立即 save。
library;

import 'dart:convert';

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

/// 线路格式偏好。
///
/// 播放侧生效由后续任务接入(见回报备注);本轨只负责设置状态 + 持久化 + 面板反映。
enum PreferredLineFormat {
  auto('自动', 'auto'),
  hls('HLS', 'hls'),
  flv('FLV', 'flv');

  const PreferredLineFormat(this.label, this.value);

  /// UI 文案。
  final String label;

  /// 持久化用的稳定值。
  final String value;

  /// 从存储值恢复;未知值回退「自动」。
  static PreferredLineFormat fromValue(String? value) => switch (value) {
    'hls' => PreferredLineFormat.hls,
    'flv' => PreferredLineFormat.flv,
    _ => PreferredLineFormat.auto,
  };
}

/// 设置状态;[hydrated] 表示是否已完成持久化恢复。
class SettingsState {
  const SettingsState({
    required this.themeMode,
    required this.defaultQuality,
    required this.danmakuEnabled,
    required this.chatEnabled,
    required this.preferredLineFormat,
    required this.serverUrl,
    this.defaultQualityBySite = const {},
    this.roomVolumes = const {},
    this.globalMuted = false,
    this.defaultVolume = defaultVolumeLevel,
    this.hydrated = false,
  });

  final ThemeModeChoice themeMode;

  /// 全平台默认画质(与播放页 fixture 画质名对齐)。
  final String defaultQuality;

  /// 各平台单独配置的默认画质(site → 画质名)。
  ///
  /// 语义(2026-09-11 收口裁决):各平台可在设置里单独指定默认档,未配置的
  /// 平台回落 [defaultQuality]。房间缺档不在这里处理,由播放侧
  /// `PlayController._pickQuality` 回退 streams.first。
  final Map<String, String> defaultQualityBySite;

  /// 每房间独立音量表:键 `room_vol_{site}_{roomId}`(见
  /// `features/play/application/room_volume_provider.dart`),值 0-100。
  ///
  /// 上游 pure_live 的 `live_room_volume_manager` 同一张表但为 0-1 口径;
  /// 本仓与 `LivePlayer.setVolume` 统一走 **0-100**,解析/写入时钳制。
  final Map<String, double> roomVolumes;

  /// 全局静音:开启时所有房间的有效音量恒为 0(压过房间值与默认值)。
  final bool globalMuted;

  /// 默认音量(0-100):房间无记忆值时的回落值。
  final double defaultVolume;

  final bool danmakuEnabled;

  /// 聊天 tab 总开关:关闭时聊天 tab 内容区显示「聊天已关闭」占位(聊天 provider 不停,只藏 UI)。
  final bool chatEnabled;

  /// 线路格式偏好(auto/hls/flv)。
  final PreferredLineFormat preferredLineFormat;

  /// streaming-server 基础地址(Web 端经它访问解析 API)。
  final String serverUrl;
  final bool hydrated;

  /// 画质候选(全平台默认可选,与 fixture 画质名对齐)。
  static const List<String> qualityOptions = ['蓝光8M', '超清', '高清', '流畅'];

  /// 各平台原生画质档位(对齐 SFVideoLive `PLATFORM_QUALITY_OPTIONS`),
  /// 设置页「平台独立默认清晰度」按此列表展示;未收录的平台回落 [qualityOptions]。
  /// 档位名为各平台解析输出文案(含 twitch/youtube 分辨率后缀),播放侧
  /// `_pickQuality` 做双向包含匹配,名称带 fps 后缀也能命中。
  static const Map<String, List<String>> platformQualityOptions = {
    'douyu': ['原画', '蓝光10M', '蓝光8M', '蓝光4M', '超清', '高清', '流畅'],
    'huya': ['原画', '蓝光20M', '蓝光10M', '蓝光8M', '蓝光4M', '超清', '高清', '流畅'],
    'bilibili': ['原画', '蓝光', '超清', '高清', '流畅'],
    'douyin': ['原画', '蓝光', '超清', '高清', '流畅'],
    'kuaishou': ['原画', '蓝光', '超清', '高清', '流畅'],
    'yy': ['原画', '蓝光20M', '蓝光10M', '蓝光', '超清', '高清', '流畅'],
    'twitch': ['自动', '1080p', '720p', '480p', '360p', '160p'],
    'soop': ['原画', '8K', '4K', '蓝光', '超清', '高清', '标清', '流畅'],
    'youtube': ['自动', '1080p', '720p', '480p', '360p', '240p', '144p'],
    'iptv': ['直播'],
  };

  /// 平台默认档(未在设置里单独选择时的值,对齐 SF `PLATFORM_DEFAULT_QUALITY`):
  /// soop/twitch/youtube 取高清档,解析侧只取该档,进房更快。
  static const Map<String, String> platformDefaultQuality = {
    'soop': '高清',
    'twitch': '720p',
    'youtube': '720p',
  };

  /// 某平台设置页可选档位(平台原生文案);未收录平台回落通用预设。
  static List<String> qualityOptionsForSite(String site) =>
      platformQualityOptions[site] ?? qualityOptions;

  /// 某平台生效的默认画质:平台单独配置 > 平台默认档 > 全平台默认。
  String effectiveDefaultQuality(String site) =>
      defaultQualityBySite[site] ??
      platformDefaultQuality[site] ??
      defaultQuality;

  /// 服务器地址默认值。
  static const String defaultServerUrl = 'http://127.0.0.1:8787';

  /// 音量统一口径上界/下界(与 `LivePlayer.setVolume` 一致,0-100)。
  static const double volumeMax = 100;
  static const double volumeMin = 0;

  /// 出厂默认音量(满音量)。
  static const double defaultVolumeLevel = volumeMax;

  SettingsState copyWith({
    ThemeModeChoice? themeMode,
    String? defaultQuality,
    Map<String, String>? defaultQualityBySite,
    Map<String, double>? roomVolumes,
    bool? globalMuted,
    double? defaultVolume,
    bool? danmakuEnabled,
    bool? chatEnabled,
    PreferredLineFormat? preferredLineFormat,
    String? serverUrl,
    bool? hydrated,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      defaultQualityBySite: defaultQualityBySite ?? this.defaultQualityBySite,
      roomVolumes: roomVolumes ?? this.roomVolumes,
      globalMuted: globalMuted ?? this.globalMuted,
      defaultVolume: defaultVolume ?? this.defaultVolume,
      danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
      chatEnabled: chatEnabled ?? this.chatEnabled,
      preferredLineFormat: preferredLineFormat ?? this.preferredLineFormat,
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

  /// 按平台默认画质,存 JSON `Map<String, String>`(site → 画质名)。
  static const String _kDefaultQualityBySite =
      'zishu.settings.defaultQualityBySite';
  static const String _kDanmakuEnabled = 'zishu.settings.danmakuEnabled';
  static const String _kChatEnabled = 'zishu.settings.chatEnabled';
  static const String _kPreferredLineFormat =
      'zishu.settings.preferredLineFormat';
  static const String _kServerUrl = 'zishu.settings.serverUrl';

  /// 每房间独立音量表,存 JSON `Map<String, double>`。
  static const String _kRoomVolumes = 'zishu.settings.roomVolumes';
  static const String _kGlobalMuted = 'zishu.settings.globalMuted';
  static const String _kDefaultVolume = 'zishu.settings.defaultVolume';

  @override
  SettingsState build() {
    // 启动时异步恢复;完成前 UI 先使用默认值(hydrated=false)。
    Future<void>.microtask(_restore);
    return const SettingsState(
      themeMode: ThemeModeChoice.system,
      defaultQuality: '超清',
      danmakuEnabled: true,
      chatEnabled: true,
      preferredLineFormat: PreferredLineFormat.auto,
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
      final bySiteRaw = await prefs.getString(_kDefaultQualityBySite);
      final danmaku = await prefs.getBool(_kDanmakuEnabled);
      final chat = await prefs.getBool(_kChatEnabled);
      final format = await prefs.getString(_kPreferredLineFormat);
      final server = await prefs.getString(_kServerUrl);
      final roomVolumesRaw = await prefs.getString(_kRoomVolumes);
      final globalMuted = await prefs.getBool(_kGlobalMuted);
      final defaultVolume = await prefs.getDouble(_kDefaultVolume);
      state = state.copyWith(
        themeMode: mode == null ? null : ThemeModeChoice.fromName(mode),
        defaultQuality:
            quality != null && SettingsState.qualityOptions.contains(quality)
            ? quality
            : null,
        defaultQualityBySite: _decodeQualityBySite(bySiteRaw),
        roomVolumes: _decodeRoomVolumes(roomVolumesRaw),
        globalMuted: globalMuted,
        defaultVolume: defaultVolume
            ?.clamp(SettingsState.volumeMin, SettingsState.volumeMax)
            .toDouble(),
        danmakuEnabled: danmaku,
        chatEnabled: chat,
        preferredLineFormat: PreferredLineFormat.fromValue(format),
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

  /// 设置某平台的默认画质并持久化;传 null 清除该平台覆盖,回落平台默认档。
  Future<void> setDefaultQualityForSite(String site, String? quality) async {
    if (quality != null &&
        !SettingsState.qualityOptionsForSite(site).contains(quality)) {
      return;
    }
    final next = Map<String, String>.of(state.defaultQualityBySite);
    if (quality == null) {
      next.remove(site);
    } else {
      next[site] = quality;
    }
    state = state.copyWith(defaultQualityBySite: next);
    try {
      await SharedPreferencesAsync().setString(
        _kDefaultQualityBySite,
        jsonEncode(next),
      );
    } catch (_) {
      // 写盘失败:内存态仍生效,下次启动回退旧值。
    }
  }

  /// 解析按平台默认画质(JSON `Map<String, String>`);非字符串/空值剔除,
  /// 整体解析失败返回 null(保留出厂默认,与其它字段同口径)。
  /// 档位名是否合法在写入侧([setDefaultQualityForSite])已校验,这里只做形状校验。
  static Map<String, String>? _decodeQualityBySite(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is String && value.trim().isNotEmpty) {
          result[key] = value;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 设置弹幕开关并持久化。
  Future<void> setDanmakuEnabled(bool enabled) async {
    state = state.copyWith(danmakuEnabled: enabled);
    try {
      await SharedPreferencesAsync().setBool(_kDanmakuEnabled, enabled);
    } catch (_) {}
  }

  /// 设置聊天 tab 总开关并持久化(关闭时聊天 tab 仅显示占位,聊天 provider 不停)。
  Future<void> setChatEnabled(bool enabled) async {
    state = state.copyWith(chatEnabled: enabled);
    try {
      await SharedPreferencesAsync().setBool(_kChatEnabled, enabled);
    } catch (_) {}
  }

  /// 设置线路格式偏好并持久化(auto/hls/flv);播放侧生效由后续任务接入。
  Future<void> setPreferredLineFormat(PreferredLineFormat format) async {
    state = state.copyWith(preferredLineFormat: format);
    try {
      await SharedPreferencesAsync().setString(
        _kPreferredLineFormat,
        format.value,
      );
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

  /// 覆盖整张房间音量表并持久化。
  ///
  /// 写入入口在 `features/play/application/room_volume_provider.dart`:
  /// 那里先做整表 copy 再交给本方法落盘,避免两处各写一遍复制逻辑。
  Future<void> setRoomVolumes(Map<String, double> volumes) async {
    final sanitized = <String, double>{
      for (final entry in volumes.entries)
        entry.key: entry.value
            .clamp(SettingsState.volumeMin, SettingsState.volumeMax)
            .toDouble(),
    };
    state = state.copyWith(roomVolumes: sanitized);
    try {
      await SharedPreferencesAsync().setString(
        _kRoomVolumes,
        jsonEncode(sanitized),
      );
    } catch (_) {}
  }

  /// 设置全局静音并持久化。
  Future<void> setGlobalMuted(bool muted) async {
    state = state.copyWith(globalMuted: muted);
    try {
      await SharedPreferencesAsync().setBool(_kGlobalMuted, muted);
    } catch (_) {}
  }

  /// 设置默认音量(0-100)并持久化;越界值钳制到合法区间。
  Future<void> setDefaultVolume(double volume) async {
    final clamped = volume
        .clamp(SettingsState.volumeMin, SettingsState.volumeMax)
        .toDouble();
    state = state.copyWith(defaultVolume: clamped);
    try {
      await SharedPreferencesAsync().setDouble(_kDefaultVolume, clamped);
    } catch (_) {}
  }

  /// 解析房间音量表(JSON `Map<String, double>`);非数值/非法键剔除,
  /// 整体解析失败返回 null(保留出厂默认,与其它字段同口径)。
  static Map<String, double>? _decodeRoomVolumes(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final result = <String, double>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && key.isNotEmpty && value is num) {
          result[key] = value
              .toDouble()
              .clamp(SettingsState.volumeMin, SettingsState.volumeMax)
              .toDouble();
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }
}

/// 设置 provider(应用级)。
final settingsProvider = NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);
