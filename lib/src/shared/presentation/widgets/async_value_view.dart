import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../zishu_tokens.dart';
import 'empty_view.dart';
import 'error_view.dart';

/// AsyncValue 三态渲染组件：loading → 居中加载圈；
/// error → ErrorView；data → builder。
/// 让页面一行完成三态渲染。
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.builder,
    this.emptyMessage,
    this.loading,
    this.onRetry,
  });

  /// Riverpod 异步状态。
  final AsyncValue<T> value;

  /// 数据就绪后的构建回调。
  final Widget Function(T data) builder;

  /// 非空且数据为空集合(List/Set/Map)时展示 EmptyView。
  final String? emptyMessage;

  /// 自定义 loading 占位，缺省为主题色加载圈。
  final Widget? loading;

  /// 错误态「重试」回调，透传给 ErrorView。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () =>
          loading ??
          Center(
            child: CircularProgressIndicator(color: context.tokens.brand),
          ),
      error: (Object error, StackTrace stackTrace) =>
          ErrorView(message: error.toString(), onRetry: onRetry),
      data: (T data) {
        if (emptyMessage != null && data is Iterable && data.isEmpty) {
          return EmptyView(message: emptyMessage!);
        }
        return builder(data);
      },
    );
  }
}
