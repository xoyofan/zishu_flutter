/// 虎牙房间级粉丝牌资源(`wupui/getResourceInfo`)的请求字节与响应解码。
///
/// 字段号**逐条核对自官网 Tars 生成代码**
/// (`assets/modules/taf/structs/ResourceManagerServant.js`),见
/// `huya_fans_badge_resource.dart` 文件头;本文件的 golden 用真实抓包
/// 字节回放(探针 `tool/_probe_huya_resource_info.dart`,2026-09-26)。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/huya_wup.dart';
import 'package:live_parser/src/platforms/huya/tars_codec.dart';
import 'package:test/test.dart';

/// `LIST<struct>` 字段字节(LIST 头手写,同 danmaku_test 的做法:
/// `TarsWriter` 未暴露裸 LIST 头,头编码与 `_writeHead` 同款)。
Uint8List _structListField(int tag, List<Uint8List> elements) {
  final sizes = TarsWriter()..writeInt(elements.length, 0);
  final out = BytesBuilder();
  if (tag < 15) {
    out.add([(tag << 4) | 9]);
  } else {
    out.add([(15 << 4) | 9, tag]);
  }
  out.add(sizes.takeBytes());
  for (final element in elements) {
    out
      ..add(const [0x0a])
      ..add(element)
      ..add(const [0x0b]);
  }
  return out.takeBytes();
}

/// `STRUCT` 字段字节(头尾手写)。
Uint8List _structOf(List<Uint8List> fields) {
  final out = BytesBuilder()..add(const [0x0a]);
  for (final field in fields) {
    out.add(field);
  }
  return (out..add(const [0x0b])).takeBytes();
}

/// 构造 `GetResourceInfoRsp{0 vResource, 1 sVersion, 2 iRetCode, 3 sMsg,
/// 4 iAllResource}`;每个 `UniformResourceInfo{0 iBizType, 1 vItem,
/// 2 vDeletedId}`,item 为 `UniformResourceItem{0 sId, 1 iType, 2 vData,
/// 3 iLoadType}`。
Uint8List _rsp({
  required int bizType,
  required int dataType,
  required Uint8List payload,
  String sId = '1',
}) {
  final item = (TarsWriter()
        ..writeString(sId, 0)
        ..writeInt(dataType, 1)
        ..writeBytes(payload, 2)
        ..writeInt(0, 3))
      .takeBytes();
  final resourceFields = (BytesBuilder()
        ..add((TarsWriter()..writeInt(bizType, 0)).takeBytes())
        ..add(_structListField(1, [item])))
      .takeBytes();
  final tail = (TarsWriter()
        ..writeString('1=md5&14=md5', 1)
        ..writeInt(0, 2)
        ..writeString('', 3)
        ..writeInt(1, 4))
      .takeBytes();
  return _structOf([_structListField(0, [resourceFields]), tail]);
}

/// `CommonFansBadgeSplitResource{0 iMaxBadgeLevel, 1 tCommonBadge}`。
Uint8List _commonFansBadgeSplit({
  required String floorUrl,
  required String identityUrl,
  int maxLevel = 52,
}) => (TarsWriter()
      ..writeStruct((resource) {
        resource.writeInt(maxLevel, 0);
        resource.writeStruct((common) {
          common.writeString(floorUrl, 0);
          common.writeString(identityUrl, 1);
          common.writeString('https://example.invalid/app.zip', 2);
        }, 1);
      }, 0))
    .takeBytes();

const String kFloorTemplate =
    'https://fileserver.cdn.huya.com/web_admin_badgeDefaultFloorUrl/'
    '73b846b6b8684ce9b1793d50824a3d4d/<size>_<ua>_<dark>_<level>.name';
const String kIdentityTemplate =
    'https://fileserver.cdn.huya.com/web_admin_badgeDefaultIdentityUrl/'
    'b42f4df0d47540c28e11b1b10b57e870/<ua>_<dark>_<identity>.name';

void main() {
  group('getResourceInfo 请求', () {
    test('只发 tUserId{tag3} + sScene@1="web",不编造 lPid 字段号', () {
      final bytes = buildResourceInfoRequest(requestId: 7);
      // 4 字节大端包长(含自身)。
      final total =
          (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
      expect(total, bytes.length);
      final packet = TarsReader(Uint8List.sublistView(bytes, 4));
      expect(packet.readInt(1), 3, reason: 'tupVersion=3');
      expect(packet.readInt(4), 7, reason: 'requestId 原样写入');
      expect(packet.readString(5), 'wupui');
      expect(packet.readString(6), 'getResourceInfo');

      final sBuffer = packet.readBytes(7);
      final req = TarsReader(sBuffer).readBytesMap(0)['tReq']!;
      final reader = TarsReader(req);
      var scene = '';
      var hasPid = false;
      reader.readStruct(0, (r) {
        r.readStruct(0, (userId) {
          expect(userId.readString(3), 'webh5&0.0.0&official');
        });
        scene = r.readString(1);
        hasPid = r.readInt(3) > 0; // lPid 未发 → 0
      });
      expect(scene, 'web');
      expect(hasPid, isFalse, reason: 'lPid 未填,不得写入猜测值');
    });
  });

  group('getResourceInfo 响应解码', () {
    test('取 CommonFansBadgeSplit(bizType=14/type=14) 的 sFloorUrl', () {
      final tRsp = _rsp(
        bizType: 14,
        dataType: 14,
        payload: _commonFansBadgeSplit(
          floorUrl: kFloorTemplate,
          identityUrl: kIdentityTemplate,
        ),
      );
      final resource = parseHuyaResourceInfoResponse(tRsp);
      expect(resource, isNotNull);
      expect(resource!.floorUrlTemplate, kFloorTemplate);
      expect(resource.identityTemplate, kIdentityTemplate);
      expect(resource.maxBadgeLevel, 52);
      expect(resource.hasFloorTemplate, isTrue);
      expect(
        resource.identityUrl(12),
        'https://fileserver.cdn.huya.com/web_admin_badgeDefaultIdentityUrl/'
            'b42f4df0d47540c28e11b1b10b57e870/3_0_12.png',
      );
    });

    test('bizType 不匹配 → null(不误取其它资源)', () {
      final tRsp = _rsp(
        bizType: 11,
        dataType: 11,
        payload: _commonFansBadgeSplit(
          floorUrl: kFloorTemplate,
          identityUrl: kIdentityTemplate,
        ),
      );
      expect(parseHuyaResourceInfoResponse(tRsp), isNull);
    });

    test('iType 不匹配 → null', () {
      final tRsp = _rsp(
        bizType: 14,
        dataType: 17,
        payload: _commonFansBadgeSplit(
          floorUrl: kFloorTemplate,
          identityUrl: kIdentityTemplate,
        ),
      );
      expect(parseHuyaResourceInfoResponse(tRsp), isNull);
    });

    test('空包/垃圾字节 → null,不抛异常', () {
      expect(parseHuyaResourceInfoResponse(Uint8List(0)), isNull);
      expect(
        parseHuyaResourceInfoResponse(
          Uint8List.fromList(utf8.encode('not-a-tars-struct')),
        ),
        isNull,
      );
    });
  });

  group('官方底图 URL 拼装(纯函数)', () {
    test('替换全部占位符 + .name → .png(level<21)', () {
      expect(
        huyaFansBadgeFloorUrl(template: kFloorTemplate, level: 15),
        'https://fileserver.cdn.huya.com/web_admin_badgeDefaultFloorUrl/'
            '73b846b6b8684ce9b1793d50824a3d4d/2_3_0_15.png',
        reason: '实测该 URL 200(image/png)',
      );
    });

    test('level>=21 → .webp;identity/dark/size 按协议值替换', () {
      expect(
        huyaFansBadgeFloorUrl(template: kFloorTemplate, level: 21),
        'https://fileserver.cdn.huya.com/web_admin_badgeDefaultFloorUrl/'
            '73b846b6b8684ce9b1793d50824a3d4d/2_3_0_21.webp',
        reason: '实测该 URL 200(image/webp)',
      );
      expect(
        huyaFansBadgeFloorUrl(
          template: kFloorTemplate,
          level: 15,
          identity: 4,
          dark: 1,
          size: 3,
        ),
        'https://fileserver.cdn.huya.com/web_admin_badgeDefaultFloorUrl/'
            '73b846b6b8684ce9b1793d50824a3d4d/3_3_1_15.png',
        reason: '实测该 URL 200(image/png)',
      );
    });

    test('size 钳制为 max(size,2)(官网 fans-icon 同款)', () {
      for (final size in [0, 1, 2]) {
        expect(
          huyaFansBadgeFloorUrl(
            template: kFloorTemplate,
            level: 15,
            size: size,
          ),
          contains('/2_3_0_15.png'),
        );
      }
    });

    test('HTML 转义的占位符(&lt;level&gt;)同样替换', () {
      const escaped =
          'https://example.invalid/floor/<size>_<ua>_<dark>_'
          '&lt;level&gt;.name';
      expect(
        huyaFansBadgeFloorUrl(template: escaped, level: 8),
        'https://example.invalid/floor/2_3_0_8.png',
      );
    });

    test('模板缺失/无 <level>/等级非法 → 空串(调用方必须降级)', () {
      expect(huyaFansBadgeFloorUrl(template: '', level: 15), '');
      expect(
        huyaFansBadgeFloorUrl(
          template: 'https://example.invalid/floor.png',
          level: 15,
        ),
        '',
      );
      expect(huyaFansBadgeFloorUrl(template: kFloorTemplate, level: 0), '');
    });
  });
}
