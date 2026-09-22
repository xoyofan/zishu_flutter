/// 页面过渡(氛围轨清单 §3.5)的测试等待帮助函数。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';

/// 推进到「页面过渡结束」——切路由后要断言之前必须先调它。
///
/// 背景:`_shellPage` 现在是 fade-through 过渡(`AmbientMotion.pageTransition`,
/// 180ms)。**过渡进行中新旧两个页面同时在树上**(旧页要等过渡结束才从
/// Navigator 卸载),因此:
/// - `findsOneWidget` / `findsNothing` / 按锚点前缀计数这类唯一性断言,不等过渡
///   结束就会数到两份(旧页 + 新页);
/// - 「离开页面 → 资源释放」类断言(如播放页 autoDispose 后 `stop()`)也要等旧页
///   真正卸载才会触发。
///
/// 为什么不用 `pumpAndSettle`:UI 用例的封面走 CachedNetworkImage,VM 中请求被
/// 测试桩拦成 400,**永远存在待决状态/定时器**,pumpAndSettle 会一直等到超时;
/// 这里只推进确定时长(沿用各用例「固定次数 pump」的既有约定)。
///
/// 帧序(实测):`go` 之后第一帧才把新页面落到树上,过渡的 Ticker 同时起跳;
/// 之后必须跨过完整时长才会 completed,旧页在同一帧之后被卸载 ——
/// 故序列为「一帧起跳 → 跨过时长 + 一帧余量 → 一帧卸载」。
Future<void> pumpPageTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(
    AmbientMotion.pageTransition + const Duration(milliseconds: 50),
  );
  await tester.pump();
}
