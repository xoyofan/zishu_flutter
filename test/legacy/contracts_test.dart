import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/legacy/core/core.dart';

void main() {
  test('RoomPayload 解析在线房间（对齐 room.schema.json）', () {
    final json = jsonDecode('''
{
  "ok": true,
  "site": "douyu",
  "room_id": "9999",
  "title": "测试房间",
  "anchor_name": "主播A",
  "cover": "https://example.test/cover.jpg",
  "category": "英雄联盟",
  "room_state": "live",
  "is_live": true,
  "available_qualities": [
    {"name": "原画", "rate": 0},
    {"name": "蓝光8M", "rate": 8}
  ],
  "streams": [
    {"name": "原画", "rate": 0, "lines": [
      {"name": "线路1", "url": "https://example.test/live.flv", "format": "flv",
       "headers": {"Referer": "https://example.test/"}},
      {"name": "线路2", "url": "https://example.test/live.m3u8", "format": "hls", "headers": {}}
    ]},
    {"name": "蓝光8M", "rate": 8, "lines": [
      {"name": "线路1", "url": "https://example.test/b8.flv", "format": "flv", "headers": {}}
    ]}
  ],
  "fetched_at": "2026-09-08T00:00:00Z",
  "cached": false
}
''') as Map<String, dynamic>;

    final room = RoomPayload.fromJson(json);
    expect(room.ok, isTrue);
    expect(room.site, 'douyu');
    expect(room.roomId, '9999');
    expect(room.roomState, RoomState.live);
    expect(room.isLive, isTrue);
    expect(room.qualityNames, ['原画', '蓝光8M']);
    expect(room.streams, hasLength(2));

    final q0 = room.streamByName('原画')!;
    expect(q0.lines, hasLength(2));
    expect(q0.lines[0].isFlv, isTrue);
    expect(q0.lines[0].needsProxy, isTrue, reason: '带 Referer 头的线路浏览器不能直连');
    expect(q0.lines[1].isHls, isTrue);
    expect(q0.lines[1].needsProxy, isFalse);

    expect(room.lineUrl(1, 0), 'https://example.test/b8.flv');
    expect(room.lineUrl(5, 0), '', reason: '越界档位返回空串');
  });

  test('RoomPayload 解析离线/错误形态', () {
    final offline = RoomPayload.fromJson({
      'ok': true,
      'site': 'huya',
      'room_id': '1',
      'is_live': false,
      'room_state': 'offline',
    });
    expect(offline.isLive, isFalse);
    expect(offline.roomState, RoomState.offline);
    expect(offline.qualityNames, isEmpty);

    final err = RoomPayload.fromJson({
      'ok': false,
      'error': 'room not found',
      'site': 'douyu',
      'room_id': 'x',
      'is_live': false,
    });
    expect(err.ok, isFalse);
    expect(err.error, 'room not found');
  });

  test('CategoriesResponse 兼容新旧两种结构', () {
    final newStyle = CategoriesResponse.fromJson({
      'ok': true,
      'site': 'bilibili',
      'categories': [
        {
          'id': 1,
          'name': '网游',
          'list': [
            {'cid': 2, 'name': '英雄联盟', 'pic': 'https://x/p.png', 'pid': 1},
          ],
        },
      ],
    });
    expect(newStyle.groups.single.name, '网游');
    expect(newStyle.groups.single.list.single.cid, '2');

    final flat = CategoriesResponse.fromJson({
      'ok': true,
      'site': 'douyu',
      'categories': [
        {'cid': 1, 'name': '户外'},
        {'cid': 2, 'name': '美食'},
      ],
    });
    expect(flat.groups, hasLength(2));
    expect(flat.groups.every((g) => g.list.single.name.isNotEmpty), isTrue);
  });
}
