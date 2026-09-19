import 'dart:convert';
import 'dart:io';

const ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Future<String> get(String url, Map<String, String> headers) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', ua);
    req.headers.set('Referer', 'https://www.sooplive.co.kr/');
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 10));
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> main() async {
  // 1. player_live_api 带/不带 Accept-Language
  for (final withLang in [false, true]) {
    final body = 'bid=phonics1&bno=&type=live&pwd=&player_type=html5'
        '&stream_type=common&quality=HD&mode=landing&from_api=0&is_revive=false';
    final client = HttpClient();
    final req = await client.postUrl(Uri.parse(
      'https://live.sooplive.co.kr/afreeca/player_live_api.php?bjid=phonics1',
    ));
    req.headers.set('User-Agent', ua);
    req.headers.set('Referer', 'https://www.sooplive.co.kr/');
    req.headers.set('Origin', 'https://www.sooplive.co.kr');
    req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
    if (withLang) req.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
    req.write(body);
    final res = await req.close().timeout(const Duration(seconds: 10));
    final json = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
    final ch = json['CHANNEL'] as Map;
    print('player_live_api Accept-Language=$withLang:');
    print('  TITLE=${ch['TITLE']}');
    print('  BJNICK=${ch['BJNICK']}');
    print('  CATEGORY_TAGS=${ch['CATEGORY_TAGS']}');
    client.close();
  }

  // 2. categoryContentsList 带/不带
  for (final withLang in [false, true]) {
    final headers = withLang
        ? {'Accept-Language': 'zh-CN,zh;q=0.9'}
        : <String, String>{};
    final text = await get(
      'https://sch.sooplive.co.kr/api.php?m=categoryContentsList&szType=live&nPageNo=1&nListCnt=3&szPlatform=pc&szOrder=view_cnt_desc&szCateNo=00040019',
      headers,
    );
    final items = ((jsonDecode(text) as Map)['data'] as Map)['list'] as List;
    print('categoryContentsList Accept-Language=$withLang:');
    for (final it in items.take(3)) {
      print('  ${it['user_id']} | ${it['user_nick']} | ${it['broad_title']}');
    }
  }

  // 3. 推荐流 lang 参数
  for (final lang in ['ko_KR', 'zh_CN']) {
    final text = await get(
      'https://live.sooplive.co.kr/api/main_broad_list_api.php?selectType=action&selectValue=all&orderType=view_cnt&pageNo=1&lang=$lang',
      {'Accept-Language': 'zh-CN,zh;q=0.9'},
    );
    final broad = (jsonDecode(text) as Map)['broad'] as List?;
    print('main_broad_list lang=$lang:');
    for (final it in (broad ?? const []).take(3)) {
      print('  ${it['user_id']} | ${it['user_nick']} | ${it['broad_title']}');
    }
  }
}
