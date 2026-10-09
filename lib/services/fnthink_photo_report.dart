/// 「让这台拍一张」那段正文的组装（T124 片C-3 的 `camera:snap`）。
///
/// 纯函数：输入是原生交回来的那一条
/// （`{snap: true, name, width, height, timeMillis}`），输出是**一条消息的正文**。
/// 与另三份回传报告同一族。
///
/// 口径：
///  - **只说事实**：时间 ＋ 尺寸 ＋ 文件名。**不写"已保存到相册"这类话** ——
///    30 以上确实是相册（MediaStore），24–28 落的是本 app 的图片目录（那个年代
///    公共相册要 WRITE_EXTERNAL_STORAGE，这一发没有、也不去要）——一句话不能两边都真。
///  - **方位中立**：不带中文（与另两份同一理由：组装在被查那台、读的人在另一台）。
///  - 形状字段缺了就空着；连文件名都没有 ⇒ 回空串（调用方读成"没成"）。
library;

/// [snap] 必须带 `name`（没有名字的成功没有意义）；缺了回空串。
///
/// 输出形如：`2026-10-10 09:31 640x480 NT_20261010_093100.jpg`
String formatFnthinkPhotoReport(Map<String, Object?> snap) {
  final name = '${snap['name'] ?? ''}'.trim();
  if (name.isEmpty) return '';
  final parts = <String>[];
  final stamp = _stamp(snap['timeMillis']);
  if (stamp.isNotEmpty) parts.add(stamp);
  final size = _size(snap['width'], snap['height']);
  if (size.isNotEmpty) parts.add(size);
  parts.add(name);
  return parts.join(' ');
}

String _size(Object? w, Object? h) {
  if (w is num && h is num && w > 0 && h > 0) {
    return '${w.round()}x${h.round()}';
  }
  return '';
}

String _stamp(Object? millis) {
  if (millis is! int || millis <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
