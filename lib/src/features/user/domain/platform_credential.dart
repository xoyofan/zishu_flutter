/// 平台登录态凭据:用户粘贴的 cookie / token(仅存本机)。
///
/// 用途:部分站点(YouTube 反爬、小红书需 `a1`+`web_session`、斗鱼/虎牙的
/// 高清档等)必须带登录态才能解析或取流。这里只承载**数据 + 展示辅助**,
/// 读写与持久化在 application 层(platform_credentials_provider.dart)。
///
/// 安全口径:值只落本机 SharedPreferences,**不进日志、不进构建产物**;
/// UI 只展示脱敏摘要([maskedPreview]),不回显整串。
library;

/// 单个平台的凭据快照。
class PlatformCredential {
  const PlatformCredential({
    required this.site,
    this.value = '',
    this.updatedAt,
  });

  /// 平台品牌 id(`PlatformBrandCatalog` 的 id,如 `youtube` / `xhs`)。
  final String site;

  /// cookie / token 原文;空串 = 未配置。
  final String value;

  /// 最近一次保存时间;`null` = 从未保存。
  final DateTime? updatedAt;

  /// 是否已配置(有非空值)。
  bool get isConfigured => value.trim().isNotEmpty;

  /// 脱敏摘要:整串绝不回显,只给「前 6 位…后 4 位 + 长度」。
  String get maskedPreview {
    final text = value.trim();
    if (text.isEmpty) return '';
    if (text.length <= 12) return '已保存 ${text.length} 字符';
    return '${text.substring(0, 6)}…${text.substring(text.length - 4)}'
        '(${text.length} 字符)';
  }

  PlatformCredential copyWith({String? value, DateTime? updatedAt}) {
    return PlatformCredential(
      site: site,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 持久化用的 JSON(`updatedAt` 存 epoch ms,便于跨平台稳定还原)。
  Map<String, dynamic> toJson() => {
    'value': value,
    if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
  };

  /// 从持久化 JSON 还原;字段缺失/类型不符时退化为未配置,不抛。
  factory PlatformCredential.fromJson(String site, Map<String, dynamic> json) {
    final rawValue = json['value'];
    final rawAt = json['updatedAt'];
    return PlatformCredential(
      site: site,
      value: rawValue is String ? rawValue : '',
      updatedAt: rawAt is num
          ? DateTime.fromMillisecondsSinceEpoch(rawAt.toInt())
          : null,
    );
  }

  @override
  String toString() =>
      'PlatformCredential(site: $site, configured: $isConfigured)';
}
