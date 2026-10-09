/// 「读本机最近一次定位」那段正文的组装（T124 片C 的 `location:get`）。
///
/// 纯函数：输入是原生交回来的一条定位
/// （`{lat, lon, accuracyMeters, provider, timeMillis}`），输出是**一条消息的正文**。
/// 与另两份回传报告同一族：形状与读口分开，两边各自可测。
///
/// 口径：
///  - **方位中立**：坐标六位小数 ＋ 精度（米）＋ 来源 ＋ 时间，**不带一种语言的词** ——
///    这段正文组装在"被查那台"上、读的人在另一台（与通话记录的 ↙／↗ 同一理由）；
///  - **缺失不编**：某一格取不到就那一格空着（不写"刚刚""附近"这类猜出来的话）；
///  - **不做批量截断**：这一条**只有一条**，没有"另有 N 条"可言；读不到由 reason 说
///    （`location-unavailable`），不在这里拿一个空串冒充。
library;

/// [fix] 必须至少有 lat/lon（调用方保证）；两者都没有时回空串（调用方读成"没成"）。
///
/// 输出形如：`31.230416,121.473701 ±25m gps 07-12 09:31`
String formatFnthinkLocationReport(Map<String, Object?> fix) {
  final lat = _coord(fix['lat']);
  final lon = _coord(fix['lon']);
  if (lat.isEmpty || lon.isEmpty) return '';
  final parts = <String>['$lat,$lon'];
  final accuracy = _accuracy(fix['accuracyMeters']);
  if (accuracy.isNotEmpty) parts.add(accuracy);
  final provider = _cut('${fix['provider'] ?? ''}'.trim(), 16);
  if (provider.isNotEmpty) parts.add(provider);
  final stamp = _stamp(fix['timeMillis']);
  if (stamp.isNotEmpty) parts.add(stamp);
  return parts.join(' ');
}

/// 六位小数（把"够不够精度"写死在这里，而不是让每个读的人各自四舍五入）。
String _coord(Object? v) {
  if (v is num) return v.toStringAsFixed(6);
  return '';
}

/// `±25m`；精度取不到或非正就空着。
String _accuracy(Object? v) {
  if (v is num && v > 0) return '±${v.round()}m';
  return '';
}

String _cut(String s, int cap) {
  if (s.length <= cap) return s;
  return '${s.substring(0, cap)}…';
}

String _stamp(Object? millis) {
  if (millis is! int || millis <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
