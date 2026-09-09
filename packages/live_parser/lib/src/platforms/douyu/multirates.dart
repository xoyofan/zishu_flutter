/// 画质档位映射:保持 getH5PlayV1 multirates 的返回顺序与原名,不补档、不重排。
library;

import '../../models/models.dart';
import 'play_api.dart';

List<QualityOption> douyuAvailableQualities(List<DouyuMultirate> multirates) => [
  for (final item in multirates)
    QualityOption(
      name: item.name.isEmpty ? '档${item.rate}' : item.name,
      rate: item.rate,
    ),
];
