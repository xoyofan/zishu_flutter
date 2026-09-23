import 'package:package_info_plus/package_info_plus.dart';

String? _appVersion;

/// 启动时读取一次构建版本，供所有路由标题复用。
Future<String> loadAppVersion() async {
  final cached = _appVersion;
  if (cached != null) return cached;
  try {
    return _appVersion = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    return _appVersion = '';
  }
}

String formatWindowTitle({
  required String pageTitle,
  required String appName,
  required String version,
}) {
  final productTitle = version.trim().isEmpty
      ? appName
      : '$appName ${version.trim()}';
  return '$pageTitle · $productTitle';
}

String currentAppVersion() => _appVersion ?? '';
