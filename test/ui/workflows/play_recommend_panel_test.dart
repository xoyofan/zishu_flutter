/// 播放页侧栏「推荐」tab 编排测试:跨平台交错 / 去重 / 分类映射 / 热门兜底 / 分页。
///
/// 为什么自造数据源:`FixtureBrowseSource` 对所有 site 都返回同一批房间,
/// 跨平台交错、去重、分类映射这些规则在它上面**无法被证伪**(实测会全绿但
/// 逻辑是错的)。这里用记录调用的 `_FakeBrowseSource` 精确控制每站每页的返回。
///
/// 宿主约定:直接 pump [PlayRecommendPanel](不经 router —— 面板只依赖
/// `browseSourceProvider`,与播放页路由无关),固定次数 pump,不用 pumpAndSettle
/// (封面图在 VM 中不会真正加载)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/play/application/play_recommend_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_recommend_panel.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

/// 固定 pump 步长(与既有 workflow 测试一致)。
const Duration _kFrame = Duration(milliseconds: 50);

/// 一次房间列表请求的记录(断言「该站到底按分类取还是按热门取」)。
typedef _Call = ({String site, String? cid, int page});

/// 可编排的浏览数据源:按 `site|cid|page` 精确返回,并记录每次调用。
class _FakeBrowseSource implements BrowseSource {
  _FakeBrowseSource();

  /// 键:`'$site|${cid ?? ''}|$page'`(cid 空串代表热门/推荐流)。
  final Map<String, List<RoomRecord>> rooms = {};

  /// 各站分类索引(名字 → cid 映射用)。
  final Map<String, CategoryResult> categories = {};

  final List<_Call> calls = <_Call>[];

  /// 设置某站某页的房间(热门流:`cid` 传 null)。
  void setRooms(
    String site,
    List<RoomRecord> list, {
    String? cid,
    int page = 1,
  }) {
    rooms['$site|${cid ?? ''}|$page'] = list;
  }

  /// 设置某站的分类索引;`items` 为 (cid, 分类名) 列表。
  void setCategories(String site, List<(String, String)> items) {
    categories[site] = CategoryResult(
      site: site,
      groups: [
        CategoryGroup(
          id: 'g',
          name: '网游竞技',
          items: [
            for (final (cid, name) in items)
              CategoryItem(cid: cid, name: name, pic: ''),
          ],
        ),
      ],
    );
  }

  /// 某站某 cid 的调用次数(`cid: null` 即该站热门/推荐流)。
  int callsFor(String site, {required String? cid}) =>
      calls.where((call) => call.site == site && call.cid == cid).length;

  @override
  Future<CategoryResult> fetchCategories(String site) async =>
      categories[site] ?? CategoryResult(site: site, groups: const []);

  @override
  Future<RoomListResult> fetchRooms({
    required String site,
    String? cid,
    int page = 1,
    int? limit,
  }) async {
    calls.add((site: site, cid: cid, page: page));
    final list = rooms['$site|${cid ?? ''}|$page'] ?? const <RoomRecord>[];
    return RoomListResult(
      rooms: list,
      page: page,
      // 与真实分页语义一致:满一页即认为还有下一页。
      hasMore: list.length >= kRecommendPerSite,
    );
  }
}

/// 造一个房间;`online` 传空串即「未开播」(roomState=offline、audience=null)。
RoomRecord _room(
  String site,
  String id, {
  String cid = '1',
  String category = '英雄联盟',
  String online = '1.2万',
}) => RoomRecord(
  site: site,
  roomId: id,
  roomState: online.isEmpty ? RoomState.offline : RoomState.live,
  title: '$site-$id',
  anchorName: '主播$id',
  cid: cid,
  category: category,
  audience: online.isEmpty ? null : online,
  cover: '',
);

/// 当前房间(必须从推荐里被剔除)。
const String _kCurrentRoom = '63136';

/// pump 面板:宽 340(侧栏档位)高 700。
Future<void> _pumpPanel(
  WidgetTester tester,
  _FakeBrowseSource source, {
  String site = 'douyu',
  String roomId = _kCurrentRoom,
  String cid = '1',
  String category = '英雄联盟',
  void Function(RoomRecord room)? onTap,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [browseSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              height: 700,
              child: PlayRecommendPanel(
                site: site,
                roomId: roomId,
                cid: cid,
                category: category,
                onTap: onTap ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _pumpFrames(tester, 6);
}

Future<void> _pumpFrames(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// 面板内房间卡锚点(按构建顺序,即交错顺序)。
List<String> _roomKeys(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'play-recommend-room-',
            ),
      ),
    )
    .map((widget) => (widget.key as ValueKey<String>).value)
    .toList();

void main() {
  testWidgets('跨平台交错:douyu/huya/bilibili/douyin 按站点轮转排序', (tester) async {
    final source = _FakeBrowseSource()
      // 当前房间平台:直接用房间自身 cid,不需要分类索引。
      ..setRooms('douyu', [
        _room('douyu', '1001'),
        _room('douyu', '1002'),
        _room('douyu', '1003'),
      ], cid: '1')
      // 其余平台:分类名「英雄联盟」映射到该站 cid。
      ..setCategories('huya', [('HY-LOL', '英雄联盟')])
      ..setCategories('bilibili', [('B-LOL', '英雄联盟')])
      ..setRooms('huya', [
        _room('huya', '2001'),
        _room('huya', '2002'),
      ], cid: 'HY-LOL')
      ..setRooms('bilibili', [
        _room('bilibili', '3001'),
        _room('bilibili', '3002'),
      ], cid: 'B-LOL')
      // douyin 没有分类索引 → 走该站热门(cid == null)。
      ..setRooms('douyin', [
        _room('douyin', '4001'),
        _room('douyin', '4002'),
      ]);

    await _pumpPanel(tester, source);

    expect(
      _roomKeys(tester).take(6).toList(),
      [
        'play-recommend-room-douyu-1001',
        'play-recommend-room-huya-2001',
        'play-recommend-room-bilibili-3001',
        'play-recommend-room-douyin-4001',
        'play-recommend-room-douyu-1002',
        'play-recommend-room-huya-2002',
      ],
      reason: '第 i 轮各站各出一条 —— 前几屏必须是多平台混合',
    );
    expect(find.byKey(const Key('play-side-recommend-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('过滤:剔除当前房间、跨页去重、未开播不出现在推荐里', (tester) async {
    final source = _FakeBrowseSource()
      ..setRooms('douyu', [
        _room('douyu', '1001'),
        // 重复条目:同一 site:roomId 只能出现一次。
        _room('douyu', '1001'),
        // 当前房间:必须被剔除。
        _room('douyu', _kCurrentRoom),
        // 未开播:online 空串。
        _room('douyu', '1004', online: ''),
      ], cid: '1')
      ..setCategories('huya', [('HY-LOL', '英雄联盟')])
      ..setRooms('huya', [_room('huya', '2001')], cid: 'HY-LOL');

    await _pumpPanel(tester, source);

    final keys = _roomKeys(tester);
    expect(keys, contains('play-recommend-room-douyu-1001'));
    expect(keys, contains('play-recommend-room-huya-2001'));
    expect(
      keys.where((key) => key == 'play-recommend-room-douyu-1001').length,
      1,
      reason: '同一房间去重后只能出现一次',
    );
    expect(
      keys,
      isNot(contains('play-recommend-room-douyu-$_kCurrentRoom')),
      reason: '当前房间不能推荐给自己',
    );
    expect(
      keys,
      isNot(contains('play-recommend-room-douyu-1004')),
      reason: '未开播房间不进推荐',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类映射:其它平台按分类名命中该站 cid,而不是直接取热门', (tester) async {
    final source = _FakeBrowseSource()
      ..setRooms('douyu', [_room('douyu', '1001')], cid: '1')
      ..setCategories('huya', [('HY-LOL', '英雄联盟'), ('HY-SING', '唱见')])
      ..setRooms('huya', [_room('huya', '2001')], cid: 'HY-LOL');

    await _pumpPanel(tester, source);

    expect(
      source.callsFor('huya', cid: 'HY-LOL'),
      greaterThanOrEqualTo(1),
      reason: '分类名命中 → 必须按映射到的 cid 取该站同分类',
    );
    expect(
      source.callsFor('huya', cid: null),
      0,
      reason: '分类线路成功时不该再打该站热门',
    );
    expect(find.byKey(const Key('play-recommend-fallback-hint')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类兜底:映射命中但该分类无结果 → 该站热门 + 兜底提示', (tester) async {
    final source = _FakeBrowseSource()
      ..setRooms('douyu', [_room('douyu', '1001')], cid: '1')
      ..setCategories('huya', [('HY-LOL', '英雄联盟')])
      // 分类线路整页为空 → 应回落该站热门。
      ..setRooms('huya', const <RoomRecord>[], cid: 'HY-LOL')
      ..setRooms('huya', [_room('huya', '2009')]);

    await _pumpPanel(tester, source);

    expect(source.callsFor('huya', cid: 'HY-LOL'), 1);
    expect(
      source.callsFor('huya', cid: null),
      greaterThanOrEqualTo(1),
      reason: '分类无结果必须回落该站热门',
    );
    expect(_roomKeys(tester), contains('play-recommend-room-huya-2009'));
    expect(find.byKey(const Key('play-recommend-fallback-hint')), findsOneWidget);
    expect(find.text(kRecommendCategoryFallbackHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无分类上下文:全部走热门,不显示分类兜底提示', (tester) async {
    final source = _FakeBrowseSource()
      ..setRooms('douyu', [_room('douyu', '1001', cid: '', category: '')])
      ..setRooms('huya', [_room('huya', '2001', cid: '', category: '')]);

    await _pumpPanel(tester, source, cid: '', category: '');

    expect(_roomKeys(tester), isNotEmpty);
    expect(
      find.byKey(const Key('play-recommend-fallback-hint')),
      findsNothing,
      reason: '本来就没有分类上下文,不该提示「已展示综合推荐」以外的兜底',
    );
    expect(
      find.text(kRecommendCategoryFallbackHint),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('分页:滚到底部追加下一页,无更多时显示「没有更多了」', (tester) async {
    final source = _FakeBrowseSource()
      ..setRooms('douyu', [
        _room('douyu', '1001'),
        _room('douyu', '1002'),
        _room('douyu', '1003'),
      ], cid: '1')
      ..setRooms('douyu', [
        _room('douyu', '1004'),
      ], cid: '1', page: 2)
      ..setCategories('huya', [('HY-LOL', '英雄联盟')])
      ..setRooms('huya', [
        _room('huya', '2001'),
        _room('huya', '2002'),
        _room('huya', '2003'),
      ], cid: 'HY-LOL', page: 1)
      ..setRooms('huya', [
        _room('huya', '2004'),
      ], cid: 'HY-LOL', page: 2);

    await _pumpPanel(tester, source);
    expect(
      find.text('向下滚动加载更多…'),
      findsOneWidget,
      reason: '首屏取满一页 → 应提示还能继续加载',
    );

    // 滚到底部:触发下一页请求(page=2)。
    await tester.drag(
      find.byKey(const Key('play-recommend-scroll')),
      const Offset(0, -2000),
    );
    await _pumpFrames(tester, 6);

    expect(
      source.calls.where((call) => call.page == 2),
      isNotEmpty,
      reason: '触底必须请求下一页',
    );
    expect(
      _roomKeys(tester),
      contains('play-recommend-room-douyu-1004'),
      reason: '第二页房间应追加进列表',
    );
    await tester.drag(
      find.byKey(const Key('play-recommend-scroll')),
      const Offset(0, -2000),
    );
    await _pumpFrames(tester, 6);
    expect(find.text('没有更多了'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点推荐房:回调把房间上抛给播放页(切房)', (tester) async {
    final source = _FakeBrowseSource()
      ..setRooms('douyu', [_room('douyu', '1001')], cid: '1');
    RoomRecord? tapped;
    await _pumpPanel(tester, source, onTap: (room) => tapped = room);

    await tester.tap(find.byKey(const ValueKey('play-recommend-room-douyu-1001')));
    await _pumpFrames(tester, 2);

    expect(tapped?.roomId, '1001');
    expect(tapped?.site, 'douyu');
    expect(tester.takeException(), isNull);
  });

  testWidgets('全部站点取数失败:显示失败文案而非空白面板', (tester) async {
    // 不设置任何房间 → 各站返回空列表(不抛异常的情形)。
    final source = _FakeBrowseSource();
    await _pumpPanel(tester, source);
    expect(find.text('暂无推荐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
