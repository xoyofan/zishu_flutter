import 'dart:convert';
import 'dart:io';

const ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Future<void> main() async {
  final client = HttpClient();
  var pageNo = 1;
  while (pageNo <= 4) {
    final req = await client.getUrl(Uri.parse(
      'https://sch.sooplive.co.kr/api.php?m=categoryList&szKeyword=&szOrder=view_cnt&nPageNo=$pageNo&nListCnt=120&nOffset=0&szPlatform=pc&lang=zh_CN',
    ));
    req.headers.set('User-Agent', ua);
    req.headers.set('Referer', 'https://www.sooplive.co.kr/');
    final res = await req.close().timeout(const Duration(seconds: 10));
    final list = (((jsonDecode(await res.transform(utf8.decoder).join())
                as Map)['data'] as Map)['list'] as List)
        .cast<Map>();
    for (final it in list) {
      final name = it['category_name'];
      if (name != null && name.toString().contains('포로')) {
        print('FOUND ${it['category_no']} | $name');
      }
    }
    if (list.length < 120) break;
    pageNo++;
  }
  client.close();
  print('done');
}
