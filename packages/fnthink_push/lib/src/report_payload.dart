/// 收件端对「回传正文」的解析（T124② 片2）。
///
/// 回传消息在线上只有 `title` 与 `body` 两格：正文可能是一行纯文字，也可能是契约声明的
/// 图像形态 JSON。收件端要凭**标题**反查动作、再按那条动作的字段名把文字与图像拆开 ——
/// 字段名从契约读，这里不写第二个 `text`/`imageBase64` 字面量。
///
/// 四条纪律：
///  ① **认不出就原样显示**：标题不在回传表里、JSON 坏了、字段缺了 ⇒ `text` 回原文，
///     不抛、不编一句「照片丢了」；
///  ② **图像超过上限不渲染**：先在 base64 字符串长度上挡一次（不解码一个超大串），
///     解码后再按契约的原始字节上限挡一次；
///  ③ **不截断**：超限就是没有图像（发送端已经按同一条上限决定过要不要发）；
///  ④ `omitted` 只认契约声明的那一对值，别的写法不猜。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'contract.dart';

/// 一条回传正文拆出来的东西。
class FnthinkReportPayload {
  const FnthinkReportPayload({
    required this.text,
    this.imageBytes,
    this.imageOmitted = false,
  });

  /// 事实文字（收件端详情里那一行）。没有就是空串。
  final String text;

  /// 原始 JPEG 字节；null = 这条没有可渲染的图像。
  final Uint8List? imageBytes;

  /// 发送端明说了「图像太大、没随这条发出」。
  final bool imageOmitted;

  bool get hasImage => imageBytes != null;
}

/// 按 [title] 找到那条回传动作，再把 [body] 拆成文字／图像／超限三档。
///
/// 找不到、解析不了、形状不对 ⇒ `FnthinkReportPayload(text: body)`（原文照显示）。
FnthinkReportPayload parseFnthinkReportPayload(
  FnthinkContract contract, {
  required String title,
  required String body,
}) {
  final action = contract.l2ReportActionByTitle(title);
  if (action == null || contract.l2ReportResultKind(action) != 'image') {
    return FnthinkReportPayload(text: body);
  }
  final textField = contract.l2ReportTextField(action);
  final imageField = contract.l2ReportImageField(action);
  final omittedField = contract.l2ReportOmittedField(action);
  final omittedValue = contract.l2ReportOmittedValue(action);
  final cap = contract.l2ReportMaxImageBytes(action);
  if (textField == null ||
      imageField == null ||
      omittedField == null ||
      omittedValue == null ||
      cap == null) {
    return FnthinkReportPayload(text: body);
  }

  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return FnthinkReportPayload(text: body);
  }
  if (decoded is! Map) return FnthinkReportPayload(text: body);

  final rawText = decoded[textField];
  final text = rawText is String ? rawText.trim() : '';
  final omitted = decoded[omittedField] == omittedValue;
  final image = _decodeImage(decoded[imageField], cap);

  if (text.isEmpty && image == null && !omitted) {
    // 一个字段都对不上：这不是我们认识的形状，原样交给界面（而不是一张空白弹层）。
    return FnthinkReportPayload(text: body);
  }
  return FnthinkReportPayload(
    text: text,
    imageBytes: image,
    imageOmitted: omitted,
  );
}

Uint8List? _decodeImage(Object? raw, int cap) {
  if (raw is! String || raw.isEmpty) return null;
  final maxChars = ((cap + 2) ~/ 3) * 4;
  if (raw.length > maxChars) return null;
  try {
    final bytes = base64Decode(raw);
    if (bytes.isEmpty || bytes.length > cap) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}
