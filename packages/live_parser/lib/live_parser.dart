/// live_parser 公开 API:站点解析核心的唯一出口。
///
/// 依赖边界:本 package 禁止依赖 Flutter、Widget、media-kit、dart:ui、
/// package:web 与 dart:js_interop;仅允许纯 Dart。
library;

export 'src/catalog/cross_catalog.dart';
export 'src/contracts/contracts.dart';
export 'src/cross/cross_browse.dart';
export 'src/http/danmaku_transport.dart';
export 'src/http/parser_http.dart';
export 'src/models/models.dart';
export 'src/registry/site_registry.dart';
