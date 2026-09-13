/// [PlayerSnapshot] 的错误字段语义单测。
///
/// 这些断言锁死的是**播放层与 UI 之间的契约**:错误类别必须与错误文案同生
/// 同灭,`copyWith` 必须能显式清错 —— 这套语义当年就是因为 `error` 用 `null`
/// 作默认值而写坏过(错误出现后再也清不掉,错误卡片永久悬在画面上)。
/// 新增 [PlayerSnapshot.errorKind] / `retryAttempt` / `retryLimit` 三个字段是
/// 纯增量的(带默认值),本测试同时确认构造与去重语义未被破坏。
library;

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/player_error.dart';

void main() {
  group('默认值', () {
    test('全新快照无错误、无重连进度', () {
      const snapshot = PlayerSnapshot();
      expect(snapshot.error, isNull);
      expect(snapshot.errorKind, PlayerErrorKind.none);
      expect(snapshot.retryAttempt, 0);
      expect(snapshot.retryLimit, 0);
      expect(snapshot.reconnecting, isFalse);
    });

    test('const 构造可用(21 个测试替身依赖此用法)', () {
      expect(const PlayerSnapshot().playing, isFalse);
    });
  });

  group('copyWith 清错语义', () {
    const withError = PlayerSnapshot(
      error: '网络中断',
      errorKind: PlayerErrorKind.network,
      retryAttempt: 2,
      retryLimit: 6,
    );

    test('不传 error 时保持原值(含类别)', () {
      final next = withError.copyWith(playing: true);
      expect(next.error, '网络中断');
      expect(next.errorKind, PlayerErrorKind.network);
      expect(next.retryAttempt, 2);
    });

    test('显式传 null 清空错误,并同步把类别归位', () {
      final cleared = withError.copyWith(error: null);
      expect(cleared.error, isNull);
      expect(
        cleared.errorKind,
        PlayerErrorKind.none,
        reason: '不应残留"没有错误却有类别"的漂移态',
      );
    });

    test('无错误时 copyWith 其他字段不会凭空产生类别', () {
      const clean = PlayerSnapshot();
      final next = clean.copyWith(volume: 50);
      expect(next.errorKind, PlayerErrorKind.none);
    });

    test('设置新错误时类别随之更新', () {
      final next = withError.copyWith(
        error: '地址失效',
        errorKind: PlayerErrorKind.source,
      );
      expect(next.error, '地址失效');
      expect(next.errorKind, PlayerErrorKind.source);
    });
  });

  group('reconnecting 判定', () {
    test('有错误且计数已推进才算重连中', () {
      const reconnecting = PlayerSnapshot(
        error: '网络中断',
        errorKind: PlayerErrorKind.network,
        retryAttempt: 1,
        retryLimit: 6,
      );
      expect(reconnecting.reconnecting, isTrue);
    });

    test('仅有错误但未开始重连时为 false(展示纯错误卡片)', () {
      const failed = PlayerSnapshot(
        error: '地址失效',
        errorKind: PlayerErrorKind.source,
      );
      expect(failed.reconnecting, isFalse);
    });

    test('仅有计数但无错误时为 false', () {
      const progressOnly = PlayerSnapshot(retryAttempt: 3, retryLimit: 6);
      expect(progressOnly.reconnecting, isFalse);
    });
  });

  group('相等性与去重', () {
    test('三个新字段参与相等性判定(否则 UI 不会重建)', () {
      const a = PlayerSnapshot(retryAttempt: 1, retryLimit: 6);
      const b = PlayerSnapshot(retryAttempt: 2, retryLimit: 6);
      expect(a == b, isFalse);

      const c = PlayerSnapshot(
        error: 'e',
        errorKind: PlayerErrorKind.network,
      );
      const d = PlayerSnapshot(
        error: 'e',
        errorKind: PlayerErrorKind.source,
      );
      expect(c == d, isFalse);
    });

    test('字段全等则相等(避免同值重复广播)', () {
      const a = PlayerSnapshot(
        error: 'e',
        errorKind: PlayerErrorKind.network,
        retryAttempt: 1,
        retryLimit: 6,
      );
      const b = PlayerSnapshot(
        error: 'e',
        errorKind: PlayerErrorKind.network,
        retryAttempt: 1,
        retryLimit: 6,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('尺寸', () {
    test('宽高未出画面时为 null', () {
      expect(const PlayerSnapshot().size, isNull);
    });

    test('宽高齐全时给出 Size(重连后 PiP 靠它沿用原宽高比)', () {
      expect(
        const PlayerSnapshot(width: 1920, height: 1080).size,
        const Size(1920, 1080),
      );
    });
  });
}
