/// 占位视图 —— U2 路由壳阶段统一占位，后续卡（U3/U5/U6/U7）逐个替换为真实视图。
library;

import 'package:flutter/material.dart';

class PlaceholderView extends StatelessWidget {
  const PlaceholderView({super.key, required this.title, this.detail});

  final String title;

  /// 可选的补充说明（如路由参数回显），缺省为通用占位文案。
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          detail ?? '占位页：待后续任务卡替换',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
