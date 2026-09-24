/// RoomRecord 模型契约:live/无观众、有效 0、replay、旧 JSON 键与刷新合并。
///
/// 钉住统一房间记录的三类语义(2026-09-24 Windows 统一契约 Task 1):
/// 1. 状态真源是 `roomState`,统计缺失为 `null`,有效 `'0'` 不当作缺失;
/// 2. 旧 JSON 键(`online`/`diamondFans`/缺 `roomState`)可读,`toJson`
///    迁移期同时输出兼容键;
/// 3. `mergeRefresh` 校验房间身份,只覆盖有值字段、状态强制取 fresh,
///    且不把已有已知字段覆盖为空。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  group('RoomRecord 状态与统计空值', () {
    test('live 房间即使没有 audience 仍为 live', () {
      final room = RoomRecord(
        site: 'douyu',
        roomId: '1',
        roomState: RoomState.live,
      );
      expect(room.isLive, isTrue);
      expect(room.audience, isNull);
      expect(room.toJson().containsKey('audience'), isFalse);
    });

    test('0 与未知不同,刷新只覆盖有值字段而始终更新状态', () {
      final old = RoomRecord(
        site: 'huya',
        roomId: '2',
        roomState: RoomState.live,
        audience: '123',
        followers: '9',
      );
      final fresh = RoomRecord(
        site: 'huya',
        roomId: '2',
        roomState: RoomState.replay,
        audience: '0',
      );
      final merged = old.mergeRefresh(fresh);
      expect(merged.roomState, RoomState.replay);
      expect(merged.isLive, isFalse);
      expect(merged.audience, '0');
      expect(merged.followers, '9');
    });

    test('replay 与 notFound 状态保留,isLive 均为 false', () {
      final replay = RoomRecord(
        site: 'bilibili',
        roomId: '9',
        roomState: RoomState.replay,
      );
      expect(replay.isReplay, isTrue);
      expect(replay.isLive, isFalse);

      final missing = RoomRecord(
        site: 'douyu',
        roomId: '0',
        roomState: RoomState.notFound,
      );
      expect(missing.roomState, RoomState.notFound);
      expect(missing.isLive, isFalse);
      expect(
        RoomRecord.fromJson(missing.toJson()).roomState,
        RoomState.notFound,
      );
    });
  });

  group('RoomRecord 旧 JSON 兼容', () {
    test('旧 JSON 统计键能读取', () {
      final room = RoomRecord.fromJson({
        'site': 'huya',
        'roomId': '2',
        'online': '12',
        'diamondFans': '3',
        'roomState': 'live',
      });
      expect(room.audience, '12');
      expect(room.svip, '3');
    });

    test('缺 roomState 的旧 JSON 按旧 online 判据映射,显式状态优先', () {
      expect(
        RoomRecord.fromJson({'site': 'douyu', 'roomId': '1', 'online': '9'})
            .roomState,
        RoomState.live,
      );
      expect(
        RoomRecord.fromJson({'site': 'douyu', 'roomId': '1', 'online': ''})
            .roomState,
        RoomState.offline,
      );
      expect(
        RoomRecord.fromJson({
          'site': 'douyu',
          'roomId': '1',
          'online': '9',
          'roomState': 'offline',
        }).roomState,
        RoomState.offline,
        reason: '显式 roomState 是真源,不被统计数字推翻',
      );
      expect(
        RoomRecord.fromJson({
          'site': 'huya',
          'roomId': '9527',
          'nickname': '虎牙主播',
          'online': '',
        }).anchorName,
        '虎牙主播',
        reason: '旧摘要 JSON 的 nickname 键可读',
      );
    });

    test('toJson 迁移期输出兼容键 online/diamondFans', () {
      final room = RoomRecord(
        site: 'huya',
        roomId: '2',
        roomState: RoomState.live,
        audience: '12',
        svip: '3',
      );
      final json = room.toJson();
      expect(json['audience'], '12');
      expect(json['online'], '12');
      expect(json['svip'], '3');
      expect(json['diamondFans'], '3');

      final blank = RoomRecord(
        site: 'douyu',
        roomId: '1',
        roomState: RoomState.offline,
      );
      expect(
        blank.toJson()['online'],
        '',
        reason: '迁移期兼容键:旧消费者依赖 online 键存在,空串表示未提供',
      );
      expect(blank.toJson().containsKey('diamondFans'), isFalse);
      expect(blank.toJson().containsKey('error'), isFalse);
    });

    test('roundtrip:状态、统计与展示字段经 toJson/fromJson 保留', () {
      final room = RoomRecord(
        site: 'douyu',
        roomId: '1',
        roomState: RoomState.replay,
        title: '标题',
        anchorName: '主播',
        audience: '0',
        followers: '0',
        vip: '1',
        svip: '2',
        sourceUrl: 'https://r/1',
        cover: 'c',
        avatar: 'a',
        category: 'cat',
        cid: '1',
        cateNo: '2',
        promoTag: 'p',
        startedAt: DateTime(2026, 9, 24, 20),
        source: 'live_parser/douyu',
        fetchedAt: DateTime(2026, 9, 24, 21),
      );

      final restored = RoomRecord.fromJson(room.toJson());
      expect(restored.roomState, RoomState.replay);
      expect(restored.title, '标题');
      expect(restored.anchorName, '主播');
      expect(restored.audience, '0', reason: '有效数值 0 不当作缺失');
      expect(restored.followers, '0');
      expect(restored.vip, '1');
      expect(restored.svip, '2');
      expect(restored.sourceUrl, 'https://r/1');
      expect(restored.cover, 'c');
      expect(restored.avatar, 'a');
      expect(restored.category, 'cat');
      expect(restored.cid, '1');
      expect(restored.cateNo, '2');
      expect(restored.promoTag, 'p');
      expect(restored.startedAt, DateTime(2026, 9, 24, 20));
      expect(restored.source, 'live_parser/douyu');
      expect(restored.fetchedAt, DateTime(2026, 9, 24, 21));
    });

    test('未知扩展不影响公共字段读取', () {
      final room = RoomRecord.fromJson({
        'site': 'douyu',
        'roomId': '1',
        'roomState': 'live',
        'title': '标题',
        'extension': {'site': 'douyu', 'version': 99, 'foo': 'bar'},
      });
      expect(room.roomState, RoomState.live);
      expect(room.title, '标题');
      expect(room.extension, isNull, reason: '尚无已知扩展子类可映射');
    });
  });

  group('RoomRecord 刷新合并', () {
    test('不同房间合并抛 ArgumentError', () {
      final old = RoomRecord(
        site: 'huya',
        roomId: '2',
        roomState: RoomState.live,
      );
      expect(
        () => old.mergeRefresh(
          RoomRecord(site: 'douyu', roomId: '2', roomState: RoomState.live),
        ),
        throwsArgumentError,
      );
      expect(
        () => old.mergeRefresh(
          RoomRecord(site: 'huya', roomId: '3', roomState: RoomState.live),
        ),
        throwsArgumentError,
      );
    });

    test('真实离线状态覆盖旧在播,刷新未提供的线路不被清空', () {
      const line = StreamLine(
        name: '线路1',
        url: 'https://a/hls',
        format: 'hls',
        headers: {'Referer': 'https://r/'},
      );
      const quality = StreamQuality(name: '原画', rate: 10000, lines: [line]);
      final old = RoomRecord(
        site: 'douyu',
        roomId: '1',
        roomState: RoomState.live,
        title: '标题',
        audience: '100',
        streams: const [quality],
      );
      final fresh = RoomRecord(
        site: 'douyu',
        roomId: '1',
        roomState: RoomState.offline,
        fetchedAt: DateTime(2026, 9, 24),
      );
      final merged = old.mergeRefresh(fresh);
      expect(merged.roomState, RoomState.offline);
      expect(merged.isLive, isFalse);
      expect(merged.title, '标题');
      expect(merged.audience, '100');
      expect(merged.streams, const [quality]);
      expect(merged.fetchedAt, DateTime(2026, 9, 24));
    });
  });

  group('RoomRecord 与旧模型转换', () {
    test('fromSummary/toSummary:online ↔ audience、diamondFans ↔ svip', () {
      const summary = RoomSummary(
        site: 'huya',
        roomId: '2',
        title: '标题',
        anchorName: '主播',
        cid: '1',
        category: '分类',
        online: '12',
        cover: 'c',
        avatar: 'a',
        promoTag: 'p',
        followers: '9',
        vip: '75',
        diamondFans: '3',
        roomState: RoomState.live,
      );
      final record = RoomRecord.fromSummary(summary);
      expect(record.audience, '12');
      expect(record.followers, '9');
      expect(record.vip, '75');
      expect(record.svip, '3');
      expect(record.roomState, RoomState.live);
      expect(record.isLive, isTrue);

      final back = record.toSummary();
      expect(back.online, '12');
      expect(back.followers, '9');
      expect(back.vip, '75');
      expect(back.diamondFans, '3');
      expect(back.roomState, RoomState.live);
      expect(back.promoTag, 'p');
      expect(back.avatar, 'a');
    });

    test('fromSummary:online 空串归 null,不误判在播', () {
      const summary = RoomSummary(
        site: 'douyu',
        roomId: '1',
        title: '',
        anchorName: '',
        cid: '',
        category: '',
        online: '',
        cover: '',
      );
      final record = RoomRecord.fromSummary(summary);
      expect(record.audience, isNull);
      expect(record.title, isNull);
      expect(record.isLive, isFalse);
      expect(record.roomState, RoomState.offline);
      expect(record.toSummary().online, '');
    });

    test('fromSummary replay 摘要按 roomState 判定,不看 online', () {
      const summary = RoomSummary(
        site: 'bilibili',
        roomId: '9',
        title: '',
        anchorName: '',
        cid: '',
        category: '',
        online: '',
        cover: '',
        roomState: RoomState.replay,
      );
      final record = RoomRecord.fromSummary(summary);
      expect(record.roomState, RoomState.replay);
      expect(record.isLive, isFalse);
      expect(record.isReplay, isTrue);
    });

    test('fromPayload/toPayload:streams/headers/error 保留,错误不转换为空', () {
      const line = StreamLine(
        name: '线路1',
        url: 'https://a/flv',
        format: 'flv',
        headers: {'Referer': 'https://r/'},
      );
      final payload = RoomPayload(
        site: 'douyu',
        roomId: '1',
        sourceUrl: 'https://r/1',
        anchorName: '主播',
        title: '标题',
        cover: 'c',
        avatar: 'av',
        category: '分类',
        cid: '1',
        roomState: RoomState.live,
        streams: const [
          StreamQuality(name: '原画', rate: 10000, lines: [line]),
        ],
        availableQualities: const [QualityOption(name: '原画', rate: 10000)],
        source: 'live_parser/douyu',
        fetchedAt: DateTime(2026, 9, 24, 20),
        error: '解析失败',
        startedAt: DateTime(2026, 9, 24, 19),
      );

      final record = RoomRecord.fromPayload(payload);
      expect(record.error, '解析失败', reason: '请求错误不转换为空');
      expect(record.source, 'live_parser/douyu');
      expect(record.fetchedAt, payload.fetchedAt);
      expect(
        record.streams.single.lines.single.headers['Referer'],
        'https://r/',
      );
      expect(record.startedAt, DateTime(2026, 9, 24, 19));

      final back = record.toPayload();
      expect(back.error, '解析失败');
      expect(back.sourceUrl, 'https://r/1');
      expect(back.source, 'live_parser/douyu');
      expect(back.fetchedAt, payload.fetchedAt);
      expect(back.startedAt, payload.startedAt);
      expect(back.roomState, RoomState.live);
      expect(back.streams.single.lines.single.headers, {
        'Referer': 'https://r/',
      }, reason: '线路 headers 随转换保留');
      expect(back.availableQualities.single.name, '原画');
    });
  });

  group('RoomRecord 播放只读行为', () {
    const hd = StreamQuality(
      name: '蓝光10M',
      rate: 10000,
      lines: [
        StreamLine(name: '线路1', url: 'https://a/flv', format: 'flv'),
        StreamLine(name: '线路2', url: 'https://a/hls', format: 'hls'),
      ],
    );
    const sd = StreamQuality(
      name: '超清',
      rate: 5000,
      lines: [StreamLine(name: 's', url: 'https://a/s', format: 'flv')],
    );
    final room = RoomRecord(
      site: 'douyu',
      roomId: '1',
      roomState: RoomState.live,
      streams: const [hd, sd],
    );

    test('playUrl 取首选画质的首选线路(hls 优先)', () {
      expect(room.playUrl, 'https://a/hls');
      expect(
        RoomRecord(
          site: 'douyu',
          roomId: '1',
          roomState: RoomState.offline,
        ).playUrl,
        '',
      );
    });

    test('qualityByName 与 RoomPayload 同语义:精确、双向包含、回退首选档', () {
      expect(room.qualityByName('超清'), sd);
      expect(room.qualityByName('超'), sd);
      expect(room.qualityByName(null), hd);
      expect(room.qualityByName(''), hd);
      expect(room.qualityByName('不存在'), hd);
      expect(
        RoomRecord(
          site: 'douyu',
          roomId: '1',
          roomState: RoomState.offline,
        ).qualityByName('超清'),
        isNull,
      );
    });
  });
}
