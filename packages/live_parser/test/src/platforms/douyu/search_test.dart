import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/search.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyu_api.dart';

void main() {
  late FakeDouyuApi fake;
  late DouyuSearchRepository search;

  setUp(() {
    fake = FakeDouyuApi();
    search = DouyuSearchRepository(ParserHttp(client: fake));
  });

  test('searchUser + searchShow 合并去重排序', () async {
    final result = await search.search(const SearchRequest(site: 'douyu', query: '测试', limit: 20));

    expect(result.site, 'douyu');
    // 主播 3 条(空 anchorInfo 跳过)+ 房间 2 条,rid=9527 重复去重 → 4 条
    expect(result.hits, hasLength(4));

    // 相关性:4444 标题 startsWith「测试」80 分;9527 昵称命中 60 分;
    // 3002 标题含「测试」但非前缀 60 分(live 优先于 offline);3001 无命中 0 分
    expect(result.hits.map((h) => h.id).toList(), ['9527', '4444', '3002', '3001']);

    expect(result.hits[0].id, '9527');
    expect(result.hits[0].state, SearchHitState.live);
    expect(result.hits[0].anchor, '测试主播');
    expect(result.hits[0].title, '测试主播的房间', reason: '重复 rid 保留主播搜索条目');
    expect(result.hits[0].avatar, 'https://shf1-ali-douyucdn.cn/avatar.jpg', reason: 'http:// 强制升级 https');
    expect(result.hits[0].fans, '128万');

    // 轮播判定 replay;房间条目 hot 格式化
    expect(result.hits[3].state, SearchHitState.replay);
    expect(result.hits[1].online, '8.5万', reason: 'searchShow hot=85000 格式化');

    // pageSize 收敛与空关键词
    final userCall = fake.requests.firstWhere((r) => r.url.contains('searchUser'));
    expect(userCall.url, contains('pageSize=20'));
    expect(userCall.url, contains('kw=%E6%B5%8B%E8%AF%95'));

    final showCall = fake.requests.firstWhere((r) => r.url.contains('searchShow'));
    expect(showCall.url, contains('pageSize=20'));

    final empty = await search.search(const SearchRequest(site: 'douyu', query: '  '));
    expect(empty.hits, isEmpty);
  });

  test('sortSearchHits 精确命中优先', () {
    final hits = [
      const SearchHit(
        id: '1',
        anchor: '测试二号',
        title: '随便播播',
        avatar: '',
        cover: '',
        state: SearchHitState.live,
        category: '',
        online: '',
      ),
      const SearchHit(
        id: '2',
        anchor: '路人甲',
        title: '路人测试中',
        avatar: '',
        cover: '',
        state: SearchHitState.live,
        category: '',
        online: '',
      ),
    ];
    final sorted = sortSearchHits('测试二号', hits);
    expect(sorted.first.id, '1', reason: '昵称精确命中得 100 分排最前');
  });

  test('trimSearchHits 去重与 limit', () {
    const hitA = SearchHit(
      id: '1',
      anchor: 'a',
      title: '',
      avatar: '',
      cover: '',
      state: SearchHitState.live,
      category: '',
      online: '',
    );
    final trimmed = trimSearchHits([hitA, hitA], 2);
    expect(trimmed, hasLength(1));
  });

  test('搜索请求必带 dy_did cookie(缺失时上游返回 error 9)', () async {
    await search.search(const SearchRequest(site: 'douyu', query: '测试', limit: 5));

    final searchCalls = fake.requests
        .where((r) => r.url.contains('japi/search/api/'))
        .toList();
    expect(searchCalls, isNotEmpty);
    for (final call in searchCalls) {
      expect(
        call.header('cookie'),
        startsWith('dy_did='),
        reason: '${call.url} 缺 dy_did 时上游会返回 error 9(搜索过于频繁)',
      );
      expect(call.header('referer'), 'https://www.douyu.com/');
    }
  });

  test('上游 error != 0 抛异常,不静默返回空结果', () async {
    fake.searchResponse = {'error': 9, 'msg': '搜索过于频繁，请稍后再试'};

    await expectLater(
      search.search(const SearchRequest(site: 'douyu', query: '测试', limit: 5)),
      throwsA(
        isA<ParserHttpException>().having(
          (e) => e.message,
          'message',
          '搜索过于频繁，请稍后再试',
        ),
      ),
    );
  });
}
