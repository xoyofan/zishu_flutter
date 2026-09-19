import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  final reg = buildSoopRegistration();
  final browse = reg.browse!;
  final result = await browse.fetchCategories('soop');
  for (final g in result.groups) {
    print('group: ${g.name}');
    for (final item in g.items.take(12)) {
      print('  ${item.cid}  ${item.name}');
    }
    print('  ... total ${g.items.length}');
  }

}
