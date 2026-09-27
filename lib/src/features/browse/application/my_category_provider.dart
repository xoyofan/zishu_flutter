/// 我的分类:用户收藏的分类快捷入口(对齐 SFVideoLive 导航「我的分类」)。
///
/// 条目以 (site, cid) 唯一,name 仅用于渲染与 `/all/category/:key` 路由匹配;
/// 收藏只落本机 SharedPreferences(`zishu.myCategories.v2`),不上行 data-server
/// (关注数据才走云同步)。
///
/// **收藏语义按跨平台分类**(对齐 web `useMyCrossCategories` 的 crossKey 口径,
/// 2026-09-20):「英雄联盟」是一个分类,不区分虎牙/斗鱼各自 cid —— 判定
/// 「已收藏」优先比较跨平台 key([crossKeyForPlatformCategory]),未命中映射表
/// 的平台私有分类才退回 (site, cid) 精确比较。存储仍存首次收藏时所在平台的
/// (site, cid)(展示名/路由快照),不迁移旧数据。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/domain/category_display.dart';

/// 一条收藏分类。
class MyCategoryEntry {
  const MyCategoryEntry({
    required this.site,
    required this.cid,
    required this.name,
  });

  /// 站点 id(`all` = 全平台聚合)。
  final String site;

  /// 子分类 id。
  final String cid;

  /// 分类名(收藏时刻的快照,平台改名后仍按 cid 命中)。
  final String name;

  /// 唯一键。
  String get key => '$site|$cid';

  bool get isValid => site.isNotEmpty && cid.isNotEmpty;

  Map<String, dynamic> toJson() => {'site': site, 'cid': cid, 'name': name};

  factory MyCategoryEntry.fromJson(Object? raw) {
    if (raw is! Map) {
      return const MyCategoryEntry(site: '', cid: '', name: '');
    }
    return MyCategoryEntry(
      site: raw['site']?.toString() ?? '',
      cid: raw['cid']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
    );
  }
}

/// 我的分类控制器:本地持久化的收藏集合,带数量上限。
class MyCategoryController extends Notifier<List<MyCategoryEntry>> {
  /// 存储键(与 follow 的 `zishu.` 前缀一致)。
  ///
  /// v2(2026-09-19):跨平台分类映射表/remap 表修正后(如「动物与动物园」
  /// 含逗号别名曾被错拆、twitch 英文名中文化),旧快照里的 name 可能是
  /// 英文原名或错拆名。对齐 web c4f8ba4「改表即升缓存版本」流程,升版让
  /// 旧键整体作废、用户按新表重新收藏;不迁移旧数据以避免错名残留。
  ///
  /// v3(2026-09-19):soop 播放页收藏曾把 payload.cid(房间号)当分类号
  /// 存入,且分类中文化修复前的快照是韩文原名 —— cid/name 双错,展示层
  /// 的 (site,cid) 反查救不回。根源已修(RoomPayload.cateNo + 收藏改用),
  /// 按先例升版作废旧收藏,用户在中文分类树/播放页重新收藏即可。
  static const String storeKey = 'zishu.myCategories.v3';

  /// 上限:对齐 SFVideoLive `MAX_MY_CROSS_CATEGORIES`。
  static const int maxCount = 12;

  @override
  List<MyCategoryEntry> build() {
    // 启动时异步恢复;完成前为空集合,浮层渲染「暂无收藏分类」。
    Future.microtask(_restore);
    return const <MyCategoryEntry>[];
  }

  /// 用户已做过本地增删(收藏/取消/移除)。置位后 [_restore] 的迟到回放必须
  /// 放弃 —— 此前只靠「state 非空」判据,漏了「用户把收藏清空」的场景:
  /// 启动恢复窗口内取消最后一条收藏,迟到的读盘回放会把旧条目复活
  /// (2026-09-27 全平台目录回归测试实捕)。
  bool _userMutated = false;

  /// 是否已收藏(精确键,仅浮层渲染等展示场景使用;收藏判定请用
  /// [isCategoryFavorited] 的跨平台口径)。
  bool contains(String site, String cid) =>
      state.any((entry) => entry.site == site && entry.cid == cid);

  /// 按**分类跨平台口径**收藏/取消(播放页星标/索引 tile 共用):
  /// 目标分类命中跨平台 key 时,任一平台的同 key 条目都算已收藏,
  /// 取消时全部移除;新增仍落当前平台的 (site, cid) 快照。
  /// 未命中映射表的分类退回 (site, cid) 精确匹配,行为同旧口径。
  /// 已达上限且是新增时返回 false(UI 侧提示)。
  Future<bool> toggleForCategory(MyCategoryEntry entry) async {
    if (!entry.isValid) return false;
    _userMutated = true;
    final key = myCategoryCrossKey(entry);
    final matchedKeys = {
      for (final item in state)
        if (key.isNotEmpty
            ? myCategoryCrossKey(item) == key
            : (item.site == entry.site && item.cid == entry.cid))
          item.key,
    };
    if (matchedKeys.isNotEmpty) {
      state = [for (final item in state) if (!matchedKeys.contains(item.key)) item];
      await _persist();
      return true;
    }
    if (state.length >= maxCount) return false;
    state = [...state, entry];
    await _persist();
    return true;
  }

  /// 收藏/取消收藏;已达上限且是新增时返回 false(UI 侧提示)。
  Future<bool> toggle(MyCategoryEntry entry) async {
    if (!entry.isValid) return false;
    _userMutated = true;
    if (contains(entry.site, entry.cid)) {
      state = [for (final item in state) if (item.key != entry.key) item];
    } else {
      if (state.length >= maxCount) return false;
      state = [...state, entry];
    }
    await _persist();
    return true;
  }

  Future<void> remove(MyCategoryEntry entry) async {
    _userMutated = true;
    state = [for (final item in state) if (item.key != entry.key) item];
    await _persist();
  }

  Future<void> _restore() async {
    try {
      final prefs = SharedPreferencesAsync();
      final raw = await prefs.getString(storeKey);
      List<MyCategoryEntry>? restored;
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          restored = [
            for (final item in decoded)
              if (MyCategoryEntry.fromJson(item).isValid)
                MyCategoryEntry.fromJson(item),
          ];
        }
      } else {
        // v3 键不存在/为空:尝试从 v2 救援迁移(见 [_migrateFromV2])。
        restored = await _migrateFromV2(prefs);
      }
      if (restored == null) return;
      // 恢复是**一次性**的:若用户在读盘完成前已收藏/取消,不得用存储回放
      // 覆盖用户动作 —— 否则刚点的收藏会被静默抹掉,且伴随写盘会把被抹掉的
      // 结果固化成真实数据(实测:连续 toggle 丢条目)。判据是 [_userMutated]
      // (任一用户增删动作同步置位),不能只看 state 非空 —— 用户清空收藏后
      // state 为空,迟到回放仍会把旧条目复活。
      if (_userMutated || state.isNotEmpty) return;
      state = restored;
    } catch (_) {
      // 存储不可用/数据损坏:保持空集合,不阻塞 UI。
    }
  }

  /// v2 → v3 一次性救援迁移:升版不应陪葬好数据。
  ///
  /// - name 已含中文 → 直接保留(收藏快照本就是中文展示名);
  /// - 否则按 (site,cid) 过跨平台映射表换中文名保留(如 twitch 英文旧快照);
  /// - 都救不回(soop 播放页曾错绑「房间号 cid + 韩文快照」)→ 丢弃。
  /// 迁移结果固化进 v3 键并删除 v2 键,迁移只发生一次。
  Future<List<MyCategoryEntry>?> _migrateFromV2(
    SharedPreferencesAsync prefs,
  ) async {
    const legacyKey = 'zishu.myCategories.v2';
    try {
      final raw = await prefs.getString(legacyKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final migrated = <MyCategoryEntry>[];
      for (final item in decoded) {
        final entry = MyCategoryEntry.fromJson(item);
        if (!entry.isValid) continue;
        if (_hasCJK(entry.name)) {
          migrated.add(entry);
          continue;
        }
        final mapped = displayCategoryName(entry.site, entry.name, entry.cid);
        if (mapped != entry.name && _hasCJK(mapped)) {
          migrated.add(
            MyCategoryEntry(site: entry.site, cid: entry.cid, name: mapped),
          );
        }
      }
      await prefs.setString(
        storeKey,
        jsonEncode([for (final entry in migrated) entry.toJson()]),
      );
      await prefs.remove(legacyKey);
      return migrated;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    try {
      final payload = [for (final entry in state) entry.toJson()];
      await SharedPreferencesAsync().setString(storeKey, jsonEncode(payload));
    } catch (_) {
      // 写盘失败:内存态仍生效。
    }
  }
}

/// 我的分类收藏集合。
final myCategoriesProvider =
    NotifierProvider<MyCategoryController, List<MyCategoryEntry>>(
  MyCategoryController.new,
);

/// 条目的跨平台收藏 key(命中映射表才有;空 = 平台私有分类,不参与跨平台)。
String myCategoryCrossKey(MyCategoryEntry entry) =>
    crossKeyForPlatformCategory(entry.site, entry.cid, entry.name);

/// 「已收藏」判定单一来源(播放页分类星标/分类索引 tile 共用):
/// 优先跨平台 key 相等 —— 收藏任一平台的「英雄联盟」,所有平台的英雄联盟
/// 房间与分类 tile 都算已收藏(对齐 web `useMyCrossCategories` crossKey 口径);
/// 目标或条目未命中映射表时退回 (site, cid) 精确比较(平台私有分类)。
bool isCategoryFavorited(
  List<MyCategoryEntry> entries, {
  required String site,
  required String cid,
  required String name,
}) {
  final key = crossKeyForPlatformCategory(site, cid, name);
  if (key.isNotEmpty) {
    return entries.any((entry) => myCategoryCrossKey(entry) == key);
  }
  return entries.any((entry) => entry.site == site && entry.cid == cid);
}

/// 是否含中文字符(救援迁移的「好快照」判据)。
bool _hasCJK(String text) => RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
