/// 一次性脚本:适配 bilibiliFetchJson 返回 Object? 的调用点,运行后删除。
const fs = require('fs');

function patch(path, pairs) {
  let s = fs.readFileSync(path, 'utf8');
  for (const [from, to] of pairs) {
    if (!s.includes(from)) {
      console.error(`MISS in ${path}: ${from.slice(0, 60)}...`);
      process.exitCode = 1;
      continue;
    }
    s = s.split(from).join(to);
  }
  fs.writeFileSync(path, s);
  console.log(`patched ${path}`);
}

patch('lib/src/platforms/bilibili/danmaku.dart', [
  [
    `    final data = await bilibiliFetchJson(
      _http,
      _credentials,
      Uri.parse('https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo'),
      params: {'id': room, 'type': '0'},
      roomId: room,
    );
    token = jsonText(data['token']);`,
    `    final data = jsonMapOf(
      await bilibiliFetchJson(
        _http,
        _credentials,
        Uri.parse('https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo'),
        params: {'id': room, 'type': '0'},
        roomId: room,
      ),
    );
    token = jsonText(data['token']);`,
  ],
  [
    `      final data = await bilibiliFetchJson(
        _http,
        _credentials,
        Uri.parse('https://api.live.bilibili.com/room/v1/Danmu/getConf'),
        params: {'room_id': room},
        roomId: room,
      );
      token = jsonText(data['token']);`,
    `      final data = jsonMapOf(
        await bilibiliFetchJson(
          _http,
          _credentials,
          Uri.parse('https://api.live.bilibili.com/room/v1/Danmu/getConf'),
          params: {'room_id': room},
          roomId: room,
        ),
      );
      token = jsonText(data['token']);`,
  ],
]);

patch('lib/src/platforms/bilibili/search.dart', [
  [
    `    final data = await bilibiliFetchJson(
      _http,
      _credentials,
      Uri.parse('https://api.bilibili.com/x/web-interface/wbi/search/type'),
      params: params,
    );`,
    `    final data = jsonMapOf(
      await bilibiliFetchJson(
        _http,
        _credentials,
        Uri.parse('https://api.bilibili.com/x/web-interface/wbi/search/type'),
        params: params,
      ),
    );`,
  ],
  [
    `        return bilibiliFetchJson(
          _http,
          _credentials,
          Uri.parse('https://api.bilibili.com/x/web-interface/search/type'),
          params: params,
        );`,
    `        return jsonMapOf(
          await bilibiliFetchJson(
            _http,
            _credentials,
            Uri.parse('https://api.bilibili.com/x/web-interface/search/type'),
            params: params,
          ),
        );`,
  ],
]);

patch('lib/src/platforms/bilibili/browse.dart', [
  [
    `    final data = await bilibiliFetchJson(
      _http,
      _credentials,
      Uri.parse('https://api.live.bilibili.com/room/v1/Area/getRoomList'),
      params: {'page': '\$page', 'page_size': '\${request.limit}'},
    );`,
    `    final data = await bilibiliFetchJson(
      _http,
      _credentials,
      Uri.parse('https://api.live.bilibili.com/room/v1/Area/getRoomList'),
      params: {'page': '\$page', 'page_size': '\${request.limit}'},
    );`,
  ],
]);

// danmaku_test 删除未用 _zlibJson
patch('test/src/platforms/bilibili/danmaku_test.dart', [
  [
    `Uint8List _zlibJson(Object json) =>
    Uint8List.fromList(ZLibEncoder().convert(utf8.encode(jsonEncode(json))));

`,
    ``,
  ],
]);
