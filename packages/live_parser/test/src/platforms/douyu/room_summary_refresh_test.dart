/// 斗鱼房间状态轻量刷新:只读 betard + m.douyu 房间信息,不取流/不签名。
///
/// 钉住三件事:在播时热度非空、离线时热度必须为空串(宿主以「online 非空」
/// 当在播判据)、以及刷新路径**不得**触碰取密钥 / getH5PlayV1 / HLS preview
/// 等取流接口(否则关注列表定时刷新会顺带打爆播放接口)。
library;

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/douyu_site.dart';
import 'package:live_parser/src/platforms/douyu/room_api.dart' show RoomNotFoundException;
import 'package:test/test.dart';

import '../../../support/fake_douyu_api.dart';

Map<String, Object?> _betard({required int showStatus, int videoLoop = 0}) => {
  'room': {
    'room_id': 9527,
    'nickname': '测试主播',
    'show_status': showStatus,
    'videoLoop': videoLoop,
    'room_name': '斗鱼测试房间',
    'room_pic': 'https://rpic.douyucdn.cn/live_cover/240x135.jpg',
    'cate_id': 1,
    'cate_name': '英雄联盟',
  },
};

void main() {
  late FakeDouyuApi fake;
  late DouyuRoomResolver resolver;

  setUp(() {
    fake = FakeDouyuApi();
    resolver = DouyuRoomResolver(DouyuClient(httpClient: fake));
  });

  test('在播:热度取 m.douyu 的 hn,元信息合并 betard,且不碰取流接口', () async {
    fake
      ..betardResponse = _betard(showStatus: 1)
      ..roomInfoResponse = {
        'code': 0,
        'data': {
          'roomInfo': {
            'hn': '1.2万',
            'roomName': '移动端标题',
            'nickname': '移动端主播名',
          },
        },
      }
      ..anchorCardResponse = {
        'code': 0,
        'data': {
          'roomInfo': {'fansNum': 123456},
          'functionShow': {
            'giftCard': {'total': 321},
          },
        },
      };

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyu', roomIdOrUrl: '9527'),
    );

    expect(summary.site, 'douyu');
    expect(summary.roomId, '9527');
    expect(summary.title, '移动端标题');
    expect(summary.anchorName, '移动端主播名');
    expect(summary.cid, '1');
    expect(summary.category, '英雄联盟');
    expect(summary.online, '1.2万');
    expect(summary.cover, contains('douyucdn'));
    // 资料卡:粉丝/贵宾(web fetchDouyuAnchorCard 同源,fansNum/giftCard.total)。
    expect(summary.followers, '123456', reason: 'web formatCount 口径:完整数字');
    expect(summary.vip, '321', reason: '贵宾取卡片 giftCard.total(WS oni 不复刻)');
    expect(summary.roomState, RoomState.live);

    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, isNot(contains('getEncryption')), reason: '刷新不得取白名单密钥');
    expect(urls, isNot(contains('getH5PlayV1')), reason: '刷新不得请求取流接口');
    expect(urls, isNot(contains('hlsH5Preview')), reason: '刷新不得请求预览流');
  });

  test('资料卡缺失/非 JSON:followers/vip 留空,刷新本身不失败', () async {
    fake
      ..betardResponse = _betard(showStatus: 1)
      ..roomInfoResponse = {
        'code': 0,
        'data': {
          'roomInfo': {'hn': '5千'},
        },
      }
      ..anchorCardResponse = null; // 路由 500 + 非 JSON 文本。

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyu', roomIdOrUrl: '9527'),
    );

    expect(summary.online, '5千');
    expect(summary.followers, '', reason: '统计是展示增强,拿不到就留空');
    expect(summary.vip, '');
  });

  test('分类:mobile cate2Name 优先;betard 无 cate_name 时兜 second_lvl_name', () async {
    // 2026-09 真实探针(tool/_probe_douyu_refresh_fields.dart)实证:
    // betard 响应已不再下发 `cate_name`,分类名在 `second_lvl_name`;
    // m.douyu roomInfo 在 `cate2Name`。两者都与 web
    // `resolveDouyuFollowCategory` 的候选链一致(mobileInfo.cate2Name 优先)。
    fake
      ..betardResponse = {
        'room': {
          'room_id': 9527,
          'nickname': '测试主播',
          'show_status': 1,
          'room_name': '斗鱼测试房间',
          'room_pic': 'https://rpic.douyucdn.cn/live_cover/240x135.jpg',
          'cate_id': 181,
          'second_lvl_name': '王者荣耀',
        },
      }
      ..roomInfoResponse = {
        'code': 0,
        'data': {
          'roomInfo': {'hn': '1.2万', 'cate2Name': '王者荣耀'},
        },
      }
      ..anchorCardResponse = {'code': 0, 'data': {}};

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyu', roomIdOrUrl: '9527'),
    );

    expect(summary.cid, '181');
    expect(summary.category, '王者荣耀');

    // mobile 缺 cate2Name(接口偶发)时回退 betard second_lvl_name。
    fake.roomInfoResponse = {
      'code': 0,
      'data': {
        'roomInfo': {'hn': '1.2万'},
      },
    };
    final fallback = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyu', roomIdOrUrl: '9527'),
    );
    expect(fallback.category, '王者荣耀', reason: 'betard second_lvl_name 兜底');
  });

  test('离线:即使上游给了热度,online 也必须为空串', () async {
    fake
      ..betardResponse = _betard(showStatus: 2)
      ..roomInfoResponse = {
        'code': 0,
        'data': {
          'roomInfo': {'hn': '9999', 'roomName': '离线房间', 'nickname': '离线主播'},
        },
      };

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyu', roomIdOrUrl: '9528'),
    );

    expect(summary.title, '离线房间');
    expect(summary.online, '', reason: '契约:空串即未开播,宿主据此判在播');
    expect(summary.roomState, RoomState.offline);
  });

  test('轮播(videoLoop=1):roomState=replay,online 契约同离线为空串', () async {
    // web douyuState(SFVideoLive follow/status.ts:126):show_status==1
    // 且 videoLoop==1 → replay,非实时直播。
    fake
      ..betardResponse = _betard(showStatus: 1, videoLoop: 1)
      ..roomInfoResponse = {
        'code': 0,
        'data': {
          'roomInfo': {'hn': '8888', 'roomName': '轮播房间', 'nickname': '轮播主播'},
        },
      };

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyu', roomIdOrUrl: '9529'),
    );

    expect(summary.title, '轮播房间');
    expect(summary.roomState, RoomState.replay);
    expect(summary.isLive, isFalse, reason: 'online 为空,不进侧栏在播判据');
    expect(summary.online, '', reason: '轮播不是实时直播,热度归空串');
  });

  test('移动端房间信息缺失:title 回退 betard,online 允许为空', () async {
    fake
      ..betardResponse = _betard(showStatus: 1)
      ..roomInfoResponse = null; // 404

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyu', roomIdOrUrl: '9527'),
    );

    expect(summary.title, '斗鱼测试房间');
    expect(summary.anchorName, '测试主播');
    expect(summary.online, '');
  });

  test('房间不存在:抛异常(由调用方按条目隔离,保留旧数据)', () async {
    fake
      ..betardResponse = '404'
      ..roomInfoResponse = null;

    await expectLater(
      resolver.refreshRoomSummary(
        const RoomRequest(site: 'douyu', roomIdOrUrl: '9527'),
      ),
      throwsA(isA<RoomNotFoundException>()),
    );
  });
}
