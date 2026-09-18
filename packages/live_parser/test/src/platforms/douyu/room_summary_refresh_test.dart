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

Map<String, Object?> _betard({required int showStatus}) => {
  'room': {
    'room_id': 9527,
    'nickname': '测试主播',
    'show_status': showStatus,
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

    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, isNot(contains('getEncryption')), reason: '刷新不得取白名单密钥');
    expect(urls, isNot(contains('getH5PlayV1')), reason: '刷新不得请求取流接口');
    expect(urls, isNot(contains('hlsH5Preview')), reason: '刷新不得请求预览流');
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
