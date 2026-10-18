/// 「让这台拍一张」那段正文的组装（T124 片C-3 的 `camera:snap`）。
///
/// 纯函数：输入是原生交回来的那一条
/// （`{snap: true, name, width, height, timeMillis, imageBytes}`），输出是**一条消息的正文**。
/// 与另三份回传报告同一族。
///
/// 口径：
///  - **只说事实**：时间 ＋ 尺寸 ＋ 文件名。**不写"已保存到相册"这类话** ——
///    30 以上确实是相册（MediaStore），24–28 落的是本 app 的图片目录（那个年代
///    公共相册要 WRITE_EXTERNAL_STORAGE，这一发没有、也不去要）——一句话不能两边都真。
///  - **方位中立**：不带中文（与另两份同一理由：组装在被查那台、读的人在另一台）。
///  - 形状字段缺了就空着；连文件名都没有 ⇒ 回空串（调用方读成"没成"）。
///  - **图像形态（T124②）**：契约说这一发是 image 时，正文升成 JSON ——
///    事实文字放 `textField`，JPEG 的 base64 放 `imageField`；超过契约上限
///    **不截断**（截断的照片解不开，而发的人以为发出去了），改写成
///    `omittedField: omittedValue`。字段名全部从契约读，这一份不写第二个字面量。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fnthink_push/fnthink_push.dart';

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

/// 契约声明了 image 形态时，把 [formatFnthinkPhotoReport] 那行事实文字与
/// 原生交回来的 JPEG 字节拼成一条正文（T124②）。
///
/// 四种落笔：
///  ① 契约为 text（或事实文字为空） ⇒ 原样返回文字；
///  ② image 但字节缺失／为空／契约缺项 ⇒ 退回文字（旧渲染端至少还能读）；
///  ③ 字节 ≤ `maxImageBytes` ⇒ `{"<textField>": text, "<imageField>": base64}`；
///  ④ 字节超上限 ⇒ `{"<textField>": text, "<omittedField>": "<omittedValue>"}`。
String formatFnthinkPhotoPayload(
  Map<String, Object?> snap,
  FnthinkContract contract,
  String action,
) {
  final text = formatFnthinkPhotoReport(snap);
  if (text.isEmpty) return '';
  if (contract.l2ReportResultKind(action) != 'image') return text;
  final textField = contract.l2ReportTextField(action);
  final imageField = contract.l2ReportImageField(action);
  final omittedField = contract.l2ReportOmittedField(action);
  final omittedValue = contract.l2ReportOmittedValue(action);
  final cap = contract.l2ReportMaxImageBytes(action);
  final bytes = _imageBytes(snap['imageBytes']);
  if (textField == null ||
      imageField == null ||
      omittedField == null ||
      omittedValue == null ||
      cap == null ||
      bytes == null ||
      bytes.isEmpty) {
    return text;
  }
  if (bytes.length > cap) {
    return jsonEncode({textField: text, omittedField: omittedValue});
  }
  return jsonEncode({textField: text, imageField: base64Encode(bytes)});
}

Uint8List? _imageBytes(Object? value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  return null;
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
