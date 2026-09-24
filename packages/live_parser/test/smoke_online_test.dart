/// 非 CI 在线 smoke:依赖真实网络,默认跳过。
/// 本地手动运行:dart test --run-skipped test/smoke_online_test.dart
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  twitchSmoke();
  yySmoke();
  soopSmoke();
  kuaishouSmoke();
  douyinSmoke();
  youtubeSmoke();
  test(
    '斗鱼真实链路:首页 → 房间解析 → 搜索',
    () async {
      final registry = buildSiteRegistry();
      final douyu = registry['douyu']!;

      // P2:首页推荐流
      final rooms = await douyu.browse!.fetchRooms(
        const RoomListRequest(site: 'douyu', cid: null, page: 1, limit: 5),
      );
      expect(rooms.rooms, isNotEmpty, reason: '首页应至少返回一个直播间');
      // ignore: avoid_print
      print('首页示例: ${rooms.rooms.first.roomId} ${rooms.rooms.first.title}');

      // P1:对首页第一个房间做真实解析
      final first = rooms.rooms.first;
      final payload = await douyu.resolver.resolveRoom(
        RoomRequest(site: 'douyu', roomIdOrUrl: first.roomId),
      );
      // ignore: avoid_print
      print(
        '解析: room=${payload.roomId} state=${payload.roomState.name} '
        'qualities=${payload.availableQualities.map((q) => q.name).toList()} '
        'startedAt=${payload.startedAt?.toIso8601String() ?? "(未知)"}',
      );
      if (payload.isLive) {
        expect(payload.streams, isNotEmpty);
        expect(payload.playUrl, isNotEmpty);
        // 契约:列出来的档 == 点得动的档(否则 UI chip 是死键)
        expect(
          payload.availableQualities.map((q) => q.name),
          payload.streams.map((s) => s.name),
          reason: 'availableQualities 必须与 streams 严格同源',
        );
        // 在播房间应能拿到开播时间(betard show_time)
        expect(payload.startedAt, isNotNull, reason: '斗鱼 betard 提供 show_time');
        // ignore: avoid_print
        print('播放地址(截断): ${payload.playUrl.substring(0, 60)}...');
      }

      // P3:搜索
      final search = await douyu.search!.search(
        const SearchRequest(site: 'douyu', query: 'lol', limit: 5),
      );
      // ignore: avoid_print
      print('搜索命中: ${search.hits.length} 条');
      expect(search.hits, isNotEmpty);

      // 分类索引
      final categories = await douyu.browse!.fetchCategories('douyu');
      expect(categories.groups, isNotEmpty);
      // ignore: avoid_print
      print('一级分类: ${categories.groups.map((g) => g.name).take(5).toList()}');

      // 弹幕:对同一真实房间建立会话,预期 30s 内收到 loginres + 至少一条弹幕
      final session = await douyu.danmaku!.connect(
        DanmakuSessionRequest(site: 'douyu', roomId: first.roomId),
      );
      final danmakuReceived = <DanmakuMessage>[];
      final states = <DanmakuSessionState>[];
      final subStates = session.states.listen(states.add);
      final subMessages = session.messages.listen(danmakuReceived.add);
      try {
        await Future<void>.delayed(const Duration(seconds: 30));
      } finally {
        await subStates.cancel();
        await subMessages.cancel();
        await session.close();
      }
      // ignore: avoid_print
      print('弹幕状态: $states, 30s 收到 ${danmakuReceived.length} 条');
      if (danmakuReceived.take(5).isNotEmpty) {
        // ignore: avoid_print
        for (final m in danmakuReceived.take(5)) {
          // ignore: avoid_print
          print('弹幕示例: [${m.userName}] ${m.text}');
        }
      }
      expect(states, contains(DanmakuSessionState.connected), reason: 'loginres 应到达');
      expect(danmakuReceived, isNotEmpty, reason: '在播房间 30s 内应有弹幕');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: '需真实网络;本地运行: dart test --run-skipped test/smoke_online_test.dart',
  );

  test(
    '虎牙真实链路:解析 → 弹幕 → 搜索/分类',
    () async {
      final registry = buildSiteRegistry();
      final huya = registry['huya']!;

      // 浏览:分类房间列表取一个在播房间
      final rooms = await huya.browse!.fetchRooms(
        const RoomListRequest(site: 'huya', cid: '1', page: 1, limit: 5),
      );
      expect(rooms.rooms, isNotEmpty, reason: '虎牙网游分类应有在播房间');
      final first = rooms.rooms.first;
      // ignore: avoid_print
      print('虎牙房间: ${first.roomId} ${first.title} (${first.audience})');

      // 房间解析:多 CDN 多画质
      final payload = await huya.resolver.resolveRoom(
        RoomRequest(site: 'huya', roomIdOrUrl: first.roomId),
      );
      // ignore: avoid_print
      print(
        '解析: room=${payload.roomId} state=${payload.roomState.name} '
        'qualities=${payload.availableQualities.map((q) => q.name).toList()} '
        'lines=${payload.streams.firstOrNull?.lines.map((l) => l.name).toList()}',
      );
      if (payload.isLive) {
        expect(payload.playUrl, isNotEmpty);
        expect(payload.playUrl, contains('wsSecret='));
        // ignore: avoid_print
        print('播放地址(截断): ${payload.playUrl.substring(0, 70)}...');
      }

      // 弹幕:Tars WS,20s 内应有 connected + 弹幕
      final session = await huya.danmaku!.connect(
        DanmakuSessionRequest(site: 'huya', roomId: first.roomId),
      );
      final received = <DanmakuMessage>[];
      final states = <DanmakuSessionState>[];
      final subStates = session.states.listen(states.add);
      final subMessages = session.messages.listen(received.add);
      try {
        await Future<void>.delayed(const Duration(seconds: 20));
      } finally {
        await subStates.cancel();
        await subMessages.cancel();
        await session.close();
      }
      // ignore: avoid_print
      print('弹幕状态: $states, 20s 收到 ${received.length} 条');
      for (final m in received.take(5)) {
        // ignore: avoid_print
        print('弹幕示例: [${m.userName}] ${m.text}');
      }
      expect(states, contains(DanmakuSessionState.connected));
      expect(received, isNotEmpty, reason: '在播房间 20s 内应有弹幕');

      // 搜索与分类
      final search = await huya.search!.search(
        const SearchRequest(site: 'huya', query: 'lol', limit: 5),
      );
      // ignore: avoid_print
      print('搜索命中: ${search.hits.length} 条');
      expect(search.hits, isNotEmpty);

      final categories = await huya.browse!.fetchCategories('huya');
      expect(categories.groups, isNotEmpty);
      // ignore: avoid_print
      print('虎牙分类: ${categories.groups.map((g) => g.name).toList()}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: '需真实网络;本地运行: dart test --run-skipped test/smoke_online_test.dart',
  );

  test(
    'B站真实链路:解析 → 弹幕 → 搜索/分类',
    () async {
      final registry = buildSiteRegistry();
      final bilibili = registry['bilibili']!;

      // 浏览:首页推荐流取一个在播房间(分区 id 会随官方调整下线,首页更稳)
      final rooms = await bilibili.browse!.fetchRooms(
        const RoomListRequest(site: 'bilibili', cid: null, page: 1, limit: 5),
      );
      expect(rooms.rooms, isNotEmpty, reason: 'B站首页应有在播房间');
      // 弹幕验证选在线人数最高的房间,保证有聊天
      final sorted = [...rooms.rooms]..sort((a, b) {
          final aWan = double.tryParse((a.audience ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
          final bWan = double.tryParse((b.audience ?? '').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
          int unit(String s0) => s0.contains('万') ? 10000 : 1;
          final aVal = aWan * unit(a.audience ?? '');
          final bVal = bWan * unit(b.audience ?? '');
          return bVal.compareTo(aVal);
        });
      final first = sorted.first;
      // ignore: avoid_print
      print('B站房间: ${first.roomId} ${first.title} (${first.audience})');

      // 房间解析
      final payload = await bilibili.resolver.resolveRoom(
        RoomRequest(site: 'bilibili', roomIdOrUrl: first.roomId),
      );
      // ignore: avoid_print
      print(
        '解析: room=${payload.roomId} state=${payload.roomState.name} '
        'qualities=${payload.availableQualities.map((q) => q.name).toList()}',
      );
      if (payload.isLive) {
        expect(payload.playUrl, isNotEmpty);
        // ignore: avoid_print
        print('播放地址(截断): ${payload.playUrl.substring(0, 70)}...');
      }

      // 弹幕:zlib protover=2。优先选搜索结果中的直播房间(预告房无聊天)。
      final searchForDanmaku = await bilibili.search!.search(
        const SearchRequest(site: 'bilibili', query: '英雄联盟', limit: 10),
      );
      final liveHits = searchForDanmaku.hits.where((h) => h.state == SearchHitState.live).toList();
      // 兜底用 B 站官方直播间(恒有弹幕)
      final danmakuRoom = liveHits.isNotEmpty ? liveHits.first.id : '6';
      // ignore: avoid_print
      print('弹幕验证房间: $danmakuRoom');
      final session = await bilibili.danmaku!.connect(
        DanmakuSessionRequest(site: 'bilibili', roomId: danmakuRoom),
      );
      final received = <DanmakuMessage>[];
      final states = <DanmakuSessionState>[];
      final subStates = session.states.listen(states.add);
      final subMessages = session.messages.listen(received.add);
      try {
        await Future<void>.delayed(const Duration(seconds: 20));
      } finally {
        await subStates.cancel();
        await subMessages.cancel();
        await session.close();
      }
      // ignore: avoid_print
      print('弹幕状态: $states, 20s 收到 ${received.length} 条');
      for (final m in received.take(5)) {
        // ignore: avoid_print
        print('弹幕示例: [${m.userName}] ${m.text}');
      }
      expect(states, contains(DanmakuSessionState.connected), reason: '认证应答应到达');
      expect(received, isNotEmpty, reason: '在播房间 20s 内应有弹幕');

      // 搜索与分类
      final search = await bilibili.search!.search(
        const SearchRequest(site: 'bilibili', query: 'lol', limit: 5),
      );
      // ignore: avoid_print
      print('搜索命中: ${search.hits.length} 条');
      expect(search.hits, isNotEmpty);

      final categories = await bilibili.browse!.fetchCategories('bilibili');
      expect(categories.groups, isNotEmpty);
      // ignore: avoid_print
      print('B站分类: ${categories.groups.map((g) => g.name).toList()}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: '需真实网络;本地运行: dart test --run-skipped test/smoke_online_test.dart',
  );
}


void twitchSmoke() {
  test(
    'Twitch 真实链路:首页 → 分类 → 房间解析 → 搜索',
    () async {
      final registry = buildSiteRegistry();
      final twitch = registry['twitch']!;

      // 首页热门流
      final rooms = await twitch.browse!.fetchRooms(
        const RoomListRequest(site: 'twitch', cid: null, page: 1, limit: 5),
      );
      expect(rooms.rooms, isNotEmpty, reason: 'Twitch 首页应有在播房间');
      // ignore: avoid_print
      print('首页示例: ${rooms.rooms.first.roomId} ${rooms.rooms.first.title} (${rooms.rooms.first.audience})');

      // 分类索引 + 分类房间
      final categories = await twitch.browse!.fetchCategories('twitch');
      expect(categories.groups, isNotEmpty);
      // ignore: avoid_print
      print('热门分类: ${categories.groups.single.items.take(5).map((i) => i.name).toList()}');
      final gameRooms = await twitch.browse!.fetchRooms(
        RoomListRequest(site: 'twitch', cid: categories.groups.single.items.first.cid, page: 1, limit: 3),
      );
      expect(gameRooms.rooms, isNotEmpty);
      // ignore: avoid_print
      print('分类房间: ${gameRooms.rooms.map((r) => r.roomId).toList()}');

      // 房间解析:多画质 HLS
      final payload = await twitch.resolver.resolveRoom(
        RoomRequest(site: 'twitch', roomIdOrUrl: rooms.rooms.first.roomId),
      );
      // ignore: avoid_print
      print(
        '解析: room=${payload.roomId} state=${payload.roomState.name} '
        'qualities=${payload.availableQualities.map((q) => q.name).toList()}',
      );
      if (payload.isLive) {
        expect(payload.streams, isNotEmpty);
        expect(payload.playUrl, isNotEmpty);
        expect(payload.playUrl, contains('.m3u8'));
        // ignore: avoid_print
        print('播放地址(截断): ${payload.playUrl.substring(0, 60)}...');
      }

      // 搜索
      final search = await twitch.search!.search(
        const SearchRequest(site: 'twitch', query: 'shroud', limit: 5),
      );
      // ignore: avoid_print
      print('搜索命中: ${search.hits.map((h) => h.id).toList()}');
      expect(search.hits, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: '需真实网络;本地运行: dart test --run-skipped --plain-name Twitch test/smoke_online_test.dart',
  );
}

void yySmoke() {
  test(
    'YY 真实链路：首页 → 分类 → 房间解析 → 搜索',
    () async {
      final registry = buildSiteRegistry();
      final yy = registry['yy']!;

      final rooms = await yy.browse!.fetchRooms(
        const RoomListRequest(site: 'yy', page: 1, limit: 5),
      );
      expect(rooms.rooms, isNotEmpty, reason: 'YY 首页应有在播房间');
      final first = rooms.rooms.first;
      // ignore: avoid_print
      print('YY 首页示例: ${first.roomId} ${first.title} (${first.audience})');

      final payload = await yy.resolver.resolveRoom(
        RoomRequest(site: 'yy', roomIdOrUrl: first.roomId),
      );
      // ignore: avoid_print
      print(
        'YY 解析: room=${payload.roomId} state=${payload.roomState.name} '
        'qualities=${payload.availableQualities.map((q) => q.name).toList()}',
      );
      expect(payload.roomState, anyOf(RoomState.live, RoomState.offline));
      if (payload.isLive) {
        expect(payload.streams, isNotEmpty);
        expect(payload.playUrl, isNotEmpty);
        // ignore: avoid_print
        print('YY 播放地址(截断): ${payload.playUrl.substring(0, 70)}...');
      }

      final categories = await yy.browse!.fetchCategories('yy');
      expect(categories.groups, isNotEmpty);
      // ignore: avoid_print
      print('YY 分类: ${categories.groups.map((g) => g.name).toList()}');

      final search = await yy.search!.search(
        const SearchRequest(site: 'yy', query: '电子', limit: 5),
      );
      // ignore: avoid_print
      print('YY 搜索命中: ${search.hits.length} 条');
      expect(search.hits, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: '需真实网络;本地运行: dart test --run-skipped --plain-name YY test/smoke_online_test.dart',
  );
}

void soopSmoke() {
  test(
    'SOOP 真实链路:推荐 → 房间解析 → 分类 → 搜索 → 弹幕',
    () async {
      final registry = buildSiteRegistry();
      final soop = registry['soop']!;

      final rooms = await soop.browse!.fetchRooms(
        const RoomListRequest(site: 'soop', page: 1, limit: 10),
      );
      expect(rooms.rooms, isNotEmpty, reason: 'SOOP 推荐位应有在播房间');
      final first = rooms.rooms.first;
      // ignore: avoid_print
      print('SOOP 推荐示例: ${first.roomId} ${first.title} (${first.audience})');

      final payload = await soop.resolver.resolveRoom(
        RoomRequest(site: 'soop', roomIdOrUrl: first.roomId),
      );
      // ignore: avoid_print
      print(
        'SOOP 解析: room=${payload.roomId} state=${payload.roomState.name} '
        'qualities=${payload.availableQualities.map((q) => q.name).toList()}',
      );
      if (payload.isLive) {
        expect(payload.streams, isNotEmpty);
        expect(payload.playUrl, isNotEmpty);
        // ignore: avoid_print
        print('SOOP 播放地址(截断): ${payload.playUrl.substring(0, 80)}...');
      }

      final categories = await soop.browse!.fetchCategories('soop');
      expect(categories.groups, isNotEmpty);
      // ignore: avoid_print
      print('SOOP 分类数: ${categories.groups.single.items.length}');

      final search = await soop.search!.search(
        const SearchRequest(site: 'soop', query: 'lol', limit: 5),
      );
      // ignore: avoid_print
      print('SOOP 搜索命中: ${search.hits.length} 条');
      expect(search.hits, isNotEmpty);

      // 弹幕:SOOP 聊天网关是 CHPT 指定的非 443 端口,部分受限网络(代理只放行
      // 443)不可达;这里 best-effort 记录,不把环境性失败算作解析链路失败。
      try {
        final session = await soop.danmaku!.connect(
          DanmakuSessionRequest(site: 'soop', roomId: first.roomId),
        );
        final received = <DanmakuMessage>[];
        final sub = session.messages.listen(received.add);
        try {
          await Future<void>.delayed(const Duration(seconds: 30));
        } finally {
          await sub.cancel();
          await session.close();
        }
        // ignore: avoid_print
        print('SOOP 弹幕: 30s 收到 ${received.length} 条');
        for (final m in received.take(5)) {
          // ignore: avoid_print
          print('弹幕示例: [${m.userName}] ${m.text}');
        }
      } catch (error) {
        // ignore: avoid_print
        print('SOOP 弹幕: 连接失败(若为受限网络属预期): $error');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: '需真实网络;本地运行: dart test --run-skipped --plain-name SOOP test/smoke_online_test.dart',
  );
}

void kuaishouSmoke() {
  test(
    '快手真实链路:首页 → 分类 → 房间解析 → feed 弹幕',
    () async {
      final registry = buildSiteRegistry();
      final kuaishou = registry['kuaishou']!;

      final rooms = await kuaishou.browse!.fetchRooms(
        const RoomListRequest(site: 'kuaishou', page: 1, limit: 30),
      );
      expect(rooms.rooms, isNotEmpty, reason: '快手首页应有在播房间');
      final sorted = [...rooms.rooms]..sort(
        (a, b) =>
            parseOnlineCount(b.audience ?? '').compareTo(parseOnlineCount(a.audience ?? '')),
      );
      final first = sorted.first;
      // ignore: avoid_print
      print('快手首页示例: ${first.roomId} ${first.title} (${first.audience})');

      final payload = await kuaishou.resolver.resolveRoom(
        RoomRequest(site: 'kuaishou', roomIdOrUrl: first.roomId),
      );
      // ignore: avoid_print
      print(
        '快手解析: room=${payload.roomId} state=${payload.roomState.name} '
        'qualities=${payload.availableQualities.map((q) => q.name).toList()}',
      );
      if (payload.isLive) {
        expect(payload.streams, isNotEmpty);
        expect(payload.playUrl, isNotEmpty);
        // ignore: avoid_print
        print('快手播放地址(截断): ${payload.playUrl.substring(0, 80)}...');
      }

      final categories = await kuaishou.browse!.fetchCategories('kuaishou');
      expect(categories.groups, hasLength(kKuaishouTopCategories.length));
      // ignore: avoid_print
      print('快手一级分类: ${categories.groups.map((g) => g.name).toList()}');

      // 弹幕:人数最高的房间,30s 内应有评论
      final session = await kuaishou.danmaku!.connect(
        DanmakuSessionRequest(site: 'kuaishou', roomId: first.roomId),
      );
      final received = <DanmakuMessage>[];
      final sub = session.messages.listen(received.add);
      try {
        await Future<void>.delayed(const Duration(seconds: 30));
      } finally {
        await sub.cancel();
        await session.close();
      }
      // ignore: avoid_print
      print('快手弹幕: 30s 收到 ${received.length} 条');
      for (final m in received.take(5)) {
        // ignore: avoid_print
        print('弹幕示例: [${m.userName}] ${m.text}');
      }
      expect(received, isNotEmpty, reason: '在播房间 30s 内应有评论');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: '需真实网络;本地运行: dart test --run-skipped --plain-name 快手 test/smoke_online_test.dart',
  );
}

void douyinSmoke() {
  test(
    '抖音真实链路:推荐 → 房间解析 → 分类 → 弹幕(best-effort)',
    () async {
      final registry = buildSiteRegistry();
      final douyin = registry['douyin']!;

      final rooms = await douyin.browse!.fetchRooms(
        const RoomListRequest(site: 'douyin', page: 1, limit: 10),
      );
      expect(rooms.rooms, isNotEmpty, reason: '抖音推荐应有在播房间');
      final sorted = [...rooms.rooms]..sort(
        (a, b) =>
            parseOnlineCount(b.audience ?? '').compareTo(parseOnlineCount(a.audience ?? '')),
      );
      final first = sorted.first;
      // ignore: avoid_print
      print('抖音推荐示例: ${first.roomId} ${first.title} (${first.audience})');

      final payload = await douyin.resolver.resolveRoom(
        RoomRequest(site: 'douyin', roomIdOrUrl: first.roomId),
      );
      // ignore: avoid_print
      print(
        '抖音解析: room=${payload.roomId} state=${payload.roomState.name} '
        'title=${payload.title} qualities=${payload.availableQualities.map((q) => q.name).toList()}',
      );
      expect(payload.roomState, anyOf(RoomState.live, RoomState.offline));
      if (payload.isLive) {
        expect(payload.streams, isNotEmpty);
        expect(payload.playUrl, isNotEmpty);
        // ignore: avoid_print
        print('抖音播放地址(截断): ${payload.playUrl.substring(0, 80)}...');
      }

      final categories = await douyin.browse!.fetchCategories('douyin');
      expect(categories.groups, isNotEmpty);
      // ignore: avoid_print
      print(
        '抖音分类组: ${categories.groups.map((g) => g.name).toList()}',
      );

      // 弹幕:X-Bogus 变体签名对上游可能已失效,记录不视为链路失败。
      try {
        final session = await douyin.danmaku!.connect(
          DanmakuSessionRequest(site: 'douyin', roomId: first.roomId),
        );
        final received = <DanmakuMessage>[];
        final sub = session.messages.listen(received.add);
        try {
          await Future<void>.delayed(const Duration(seconds: 30));
        } finally {
          await sub.cancel();
          await session.close();
        }
        // ignore: avoid_print
        print('抖音弹幕: 30s 收到 ${received.length} 条');
        for (final m in received.take(5)) {
          // ignore: avoid_print
          print('弹幕示例: [${m.userName}] ${m.text}');
        }
      } catch (error) {
        // ignore: avoid_print
        print('抖音弹幕: 连接失败(签名/风控环境): $error');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: '需真实网络;本地运行: dart test --run-skipped --plain-name 抖音 test/smoke_online_test.dart',
  );
}

void youtubeSmoke() {
  test(
    'YouTube 真实链路:直播页浏览 → 房间解析 → 聊天(best-effort)',
    () async {
      final registry = buildSiteRegistry();
      final youtube = registry['youtube']!;

      final rooms = await youtube.browse!.fetchRooms(
        const RoomListRequest(site: 'youtube', page: 1, limit: 10),
      );
      expect(rooms.rooms, isNotEmpty, reason: 'YouTube /live 应有直播房间');
      final first = rooms.rooms.first;
      // ignore: avoid_print
      print('YouTube 直播示例: ${first.roomId} ${first.title}');

      final payload = await youtube.resolver.resolveRoom(
        RoomRequest(site: 'youtube', roomIdOrUrl: first.roomId),
      );
      // ignore: avoid_print
      print(
        'YouTube 解析: room=${payload.roomId} state=${payload.roomState.name} '
        'title=${payload.title} error=${payload.error ?? "-"} '
        'qualities=${payload.availableQualities.map((q) => q.name).toList()}',
      );
      expect(payload.roomState, anyOf(RoomState.live, RoomState.offline));
      if (payload.isLive) {
        expect(payload.streams, isNotEmpty);
        expect(payload.playUrl, contains('.m3u8'));
        // ignore: avoid_print
        print('YouTube 播放地址(截断): ${payload.playUrl.substring(0, 80)}...');
      }

      // 弹幕:匿名 live_chat 轮询(best-effort,地区/风控可能不可达)。
      try {
        final session = await youtube.danmaku!.connect(
          DanmakuSessionRequest(site: 'youtube', roomId: first.roomId),
        );
        final received = <DanmakuMessage>[];
        final sub = session.messages.listen(received.add);
        try {
          await Future<void>.delayed(const Duration(seconds: 30));
        } finally {
          await sub.cancel();
          await session.close();
        }
        // ignore: avoid_print
        print('YouTube 弹幕: 30s 收到 ${received.length} 条');
        for (final m in received.take(5)) {
          // ignore: avoid_print
          print('弹幕示例: [${m.userName}] ${m.text}');
        }
      } catch (error) {
        // ignore: avoid_print
        print('YouTube 弹幕: 连接失败(地区/风控环境): $error');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: '需真实网络;本地运行: dart test --run-skipped --plain-name YouTube test/smoke_online_test.dart',
  );
}
