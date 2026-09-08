// 来源：pure_live（AGPL-3.0）lib/model/live_category.dart
// 移植调整：import 由 pure_live 的 models/index.dart 改为相对引用 live_area.dart。
import 'dart:convert';

import 'live_area.dart';

class LiveCategory {
  final String name;
  final String id;
  final List<LiveArea> children;
  LiveCategory({required this.id, required this.name, required this.children});

  @override
  String toString() {
    return json.encode({'name': name, 'id': id, 'children': children});
  }
}
