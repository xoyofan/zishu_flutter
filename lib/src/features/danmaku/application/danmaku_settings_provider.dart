/// 弹幕细粒度设置控制器(A3):Notifier + SharedPreferencesAsync 持久化。
///
/// 与 `browse/sidebar_pref_provider.dart` 同构:启动时异步读盘,完成前 UI 先
/// 用默认值;读盘失败静默保留默认。每次改值立即 clamp 并写盘(写盘失败内存态
/// 仍生效)。key 前缀 `zishu.danmaku.` 避免与其它模块冲突。
///
/// 本文件只承载「设置」这一层,A2 overlay 的总开关 `danmakuEnabled` 不在此处
/// (在 follow/settings_provider),本控制器不重复做开关。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/danmaku_settings.dart';

/// 弹幕细粒度设置控制器。
class DanmakuSettingsController extends Notifier<DanmakuSettings> {
  /// 持久化键(带模块前缀,避免与总开关 `zishu.settings.danmakuEnabled` 冲突)。
  static const String _kOpacity = 'zishu.danmaku.opacity';
  static const String _kFontSize = 'zishu.danmaku.fontSize';
  static const String _kSpeed = 'zishu.danmaku.speed';
  static const String _kDisplayArea = 'zishu.danmaku.displayArea';

  @override
  DanmakuSettings build() {
    // 启动时异步恢复;完成前 UI 先使用默认值。
    Future<void>.microtask(_restore);
    return const DanmakuSettings();
  }

  /// 从本地存储恢复;全字段缺失视为「未设置」,保留默认(不写盘)。
  Future<void> _restore() async {
    try {
      final prefs = SharedPreferencesAsync();
      final opacity = await prefs.getInt(_kOpacity);
      final fontSize = await prefs.getInt(_kFontSize);
      final speed = await prefs.getInt(_kSpeed);
      final area = await prefs.getDouble(_kDisplayArea);
      // 四项全空:首次启动,默认值即出厂值,无需覆盖 state。
      if (opacity == null &&
          fontSize == null &&
          speed == null &&
          area == null) {
        return;
      }
      state = DanmakuSettings.clamp(
        opacity: opacity,
        fontSize: fontSize,
        speed: speed,
        displayAreaRatio: area,
      );
    } catch (_) {
      // 平台存储不可用等异常:保持默认值,页面不崩溃。
    }
  }

  /// 设置不透明度(百分比)并持久化。
  Future<void> setOpacity(int opacity) async {
    state = DanmakuSettings.clamp(
      opacity: opacity,
      fontSize: state.fontSize,
      speed: state.speed,
      displayAreaRatio: state.displayAreaRatio,
    );
    try {
      await SharedPreferencesAsync().setInt(_kOpacity, state.opacity);
    } catch (_) {
      // 写盘失败:内存态仍生效,下次启动回退旧值。
    }
  }

  /// 设置字号(px)并持久化。
  Future<void> setFontSize(int fontSize) async {
    state = DanmakuSettings.clamp(
      opacity: state.opacity,
      fontSize: fontSize,
      speed: state.speed,
      displayAreaRatio: state.displayAreaRatio,
    );
    try {
      await SharedPreferencesAsync().setInt(_kFontSize, state.fontSize);
    } catch (_) {
      // 写盘失败:内存态仍生效。
    }
  }

  /// 设置速度档(1~10)并持久化。
  Future<void> setSpeed(int speed) async {
    state = DanmakuSettings.clamp(
      opacity: state.opacity,
      fontSize: state.fontSize,
      speed: speed,
      displayAreaRatio: state.displayAreaRatio,
    );
    try {
      await SharedPreferencesAsync().setInt(_kSpeed, state.speed);
    } catch (_) {
      // 写盘失败:内存态仍生效。
    }
  }

  /// 设置显示区域比例(取 [DanmakuSettings.kDisplayAreaRatios] 之一)并持久化。
  Future<void> setDisplayAreaRatio(double ratio) async {
    state = DanmakuSettings.clamp(
      opacity: state.opacity,
      fontSize: state.fontSize,
      speed: state.speed,
      displayAreaRatio: ratio,
    );
    try {
      await SharedPreferencesAsync().setDouble(
        _kDisplayArea,
        state.displayAreaRatio,
      );
    } catch (_) {
      // 写盘失败:内存态仍生效。
    }
  }

  /// 整体替换为给定设置(供「重置默认」等场景复用)。
  Future<void> setAll(DanmakuSettings next) async {
    final clamped = DanmakuSettings.clamp(
      opacity: next.opacity,
      fontSize: next.fontSize,
      speed: next.speed,
      displayAreaRatio: next.displayAreaRatio,
    );
    state = clamped;
    try {
      final prefs = SharedPreferencesAsync();
      await prefs.setInt(_kOpacity, clamped.opacity);
      await prefs.setInt(_kFontSize, clamped.fontSize);
      await prefs.setInt(_kSpeed, clamped.speed);
      await prefs.setDouble(_kDisplayArea, clamped.displayAreaRatio);
    } catch (_) {
      // 写盘失败:内存态仍生效。
    }
  }
}

/// 弹幕细粒度设置 provider。
final danmakuSettingsProvider =
    NotifierProvider<DanmakuSettingsController, DanmakuSettings>(
      DanmakuSettingsController.new,
    );
