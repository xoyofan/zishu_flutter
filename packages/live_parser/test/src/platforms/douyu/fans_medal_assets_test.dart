import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  // 按官网 `wconf.douyucdn.cn/resource/common/fans_medal_web_v5.json`
  // 2026-09-27 实测结构构造的最小 fixture。
  Map<String, Object?> fixture() => {
        'commBg': <String, String>{
          'bg_0': 'com_bg_0',
          'bg_1': 'com_bg_1',
          'bg_5': 'com_bg_1', // 5 级一档:1..5 同桶
          'bg_6': 'com_bg_6',
          'bg_12': 'com_bg_11', // 12 → 桶 11
          'bg_61': 'com_bg_51',
          'lbg_1': 'com_lbg_1',
          'lbg_16': 'com_lbg_16',
          // 非 bg/lbg 键应被忽略
          'hpx_1': 'com_h_1',
        },
        'bgPics': <String, String>{
          'com_bg_0': 'https://sta-op.douyucdn.cn/a/com_bg_0.png',
          'com_bg_1': 'https://sta-op.douyucdn.cn/a/com_bg_1.png',
          'com_bg_6': 'https://sta-op.douyucdn.cn/a/com_bg_6.png',
          'com_bg_11': 'https://sta-op.douyucdn.cn/a/com_bg_11.png',
          'com_bg_51': 'https://sta-op.douyucdn.cn/a/com_bg_51.png',
          'com_lbg_1': 'https://sta-op.douyucdn.cn/a/com_lbg_1.png',
          'com_lbg_16': 'https://sta-op.douyucdn.cn/a/com_lbg_16.png',
          'com_h_1': 'https://sta-op.douyucdn.cn/a/com_h_1.png',
        },
        'fansMedals': <Object?>[
          {
            't': '3',
            'resource': {
              'webHdPic': 'https://sta-op.douyucdn.cn/prefix-a.webp',
            },
            'room_ids_v2': {'941266': 1, '6999879': 1},
          },
          {
            't': '5',
            'resource': {
              'webHdPic': 'https://sta-op.douyucdn.cn/prefix-b.webp',
            },
            'room_ids_v2': {'96555': 1},
          },
          // 无前缀资源的条目应被跳过
          {'t': '7', 'room_ids_v2': {'123': 1}},
        ],
      };

  group('parseDouyuFansMedalConfig', () {
    test('等级桶映射:bg_{lv} → bgPics 完整 URL', () {
      final config = parseDouyuFansMedalConfig(fixture())!;
      expect(
        config.backdropUrl(1),
        'https://sta-op.douyucdn.cn/a/com_bg_1.png',
      );
      expect(
        config.backdropUrl(12),
        'https://sta-op.douyucdn.cn/a/com_bg_11.png',
      );
      expect(
        config.backdropUrl(61),
        'https://sta-op.douyucdn.cn/a/com_bg_51.png',
      );
      expect(config.backdropUrl(0), isNotNull);
    });

    test('大图映射:lbg_{lv} 独立成表,不混入普通背景', () {
      final config = parseDouyuFansMedalConfig(fixture())!;
      expect(
        config.backdropUrl(16, large: true),
        'https://sta-op.douyucdn.cn/a/com_lbg_16.png',
      );
      // 普通表里没有 16( fixture 没放 bg_16 )
      expect(config.backdropUrl(16), isNull);
    });

    test('非法等级/null 桶安全返回 null', () {
      final config = parseDouyuFansMedalConfig(fixture())!;
      expect(config.backdropUrl(-1), isNull);
      expect(config.backdropUrl(999), isNull);
    });

    test('房间前缀索引:room_ids_v2 反转成 brid → webHdPic', () {
      final config = parseDouyuFansMedalConfig(fixture())!;
      expect(config.prefixUrl(941266), 'https://sta-op.douyucdn.cn/prefix-a.webp');
      expect(config.prefixUrl(96555), 'https://sta-op.douyucdn.cn/prefix-b.webp');
    });

    test('无前缀资源/未知房间/非法 brid 返回 null', () {
      final config = parseDouyuFansMedalConfig(fixture())!;
      expect(config.prefixUrl(123), isNull); // 有条目但无 resource
      expect(config.prefixUrl(456), isNull); // 完全未知
      expect(config.prefixUrl(0), isNull);
      expect(config.prefixUrl(null), isNull);
    });

    test('缺 commBg/bgPics 返回 null(加载失败语义)', () {
      expect(parseDouyuFansMedalConfig(null), isNull);
      expect(parseDouyuFansMedalConfig({}), isNull);
      expect(
        parseDouyuFansMedalConfig({'commBg': <String, String>{}}),
        isNull,
      );
    });
  });

  // 按 `inter_com_w_anchor_rights.json` 2026-09-27 实测结构构造的 fixture。
  group('parseDouyuDiamondSuffixIcons', () {
    Map<String, Object?> rightsFixture() => {
          'list': <String, Object?>{
            '126': {
              'id': 126,
              'btype': 'wsj2023',
              'webPic': 'https://sta-op.douyucdn.cn/dygev/a/126.webp',
              'vswitch': {'ios': '', 'android': '', 'web': 1, 'pc': 1},
            },
            // web 开关关闭 → 不收
            '127': {
              'id': 127,
              'webPic': 'https://sta-op.douyucdn.cn/dygev/a/127.webp',
              'vswitch': {'web': 0},
            },
            // 缺 webPic → 不收
            '128': {
              'id': 128,
              'vswitch': {'web': 1},
            },
            // 非法 id → 不收
            'abc': {
              'webPic': 'https://sta-op.douyucdn.cn/dygev/a/x.webp',
              'vswitch': {'web': 1},
            },
          },
        };

    test('webPic + vswitch.web==1 的条目进入映射', () {
      final icons = parseDouyuDiamondSuffixIcons(rightsFixture());
      expect(icons[126], 'https://sta-op.douyucdn.cn/dygev/a/126.webp');
      expect(icons.containsKey(127), isFalse);
      expect(icons.containsKey(128), isFalse);
      expect(icons.containsKey(0), isFalse); // 'abc' 解析不出正整数
    });

    test('null/缺 list 返回空表(降级默认款语义)', () {
      expect(parseDouyuDiamondSuffixIcons(null), isEmpty);
      expect(parseDouyuDiamondSuffixIcons({}), isEmpty);
      expect(parseDouyuDiamondSuffixIcons({'list': 'x'}), isEmpty);
    });

    test('diamondSuffixUrl:命中返回装扮款,未命中/0/null 返回 null', () {
      final base = parseDouyuFansMedalConfig(fixture())!;
      final config = DouyuFansMedalConfig(
        backdropByLevel: base.backdropByLevel,
        largeBackdropByLevel: base.largeBackdropByLevel,
        prefixByRoomId: base.prefixByRoomId,
        diamondIconByDiafid: parseDouyuDiamondSuffixIcons(rightsFixture()),
      );
      expect(config.diamondSuffixUrl(126),
          'https://sta-op.douyucdn.cn/dygev/a/126.webp');
      expect(config.diamondSuffixUrl(999), isNull);
      expect(config.diamondSuffixUrl(0), isNull);
      expect(config.diamondSuffixUrl(null), isNull);
    });
  });
}
