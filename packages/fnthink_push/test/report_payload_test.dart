import 'dart:convert';
import 'dart:typed_data';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// T124② 片2：收件端把一条回传正文拆成文字／图像／超限。
///
/// 这一页钉的是「收件端凭什么认得那条回传」—— 标题反查动作、字段名从契约读、
/// 认不出就原样显示。渲染那一半在 App 的 widget 用例里，不在这里。
void main() {
  late FnthinkContract c;
  setUp(() => c = FnthinkContract.readFile());

  FnthinkContract edited(List<String> path, Object? value) {
    final root = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
    var node = root;
    for (final key in path.take(path.length - 1)) {
      node = node[key] as Map<String, Object?>;
    }
    node[path.last] = value;
    return FnthinkContract.parse(jsonEncode(root));
  }

  FnthinkContract photoContract([Map<String, Object?> patch = const {}]) {
    final root = jsonDecode(jsonEncode(c.raw)) as Map<String, Object?>;
    final caps = root['capabilities'] as Map<String, Object?>;
    final l2 = caps['l2'] as Map<String, Object?>;
    final reports = l2['reports'] as Map<String, Object?>;
    (reports['camera:snap'] as Map<String, Object?>).addAll(patch);
    return FnthinkContract.parse(jsonEncode(root));
  }

  FnthinkReportPayload parse(String body, {String title = 'camera-snap'}) =>
      parseFnthinkReportPayload(c, title: title, body: body);

  test('真契约：按标题反查得到动作名；不认识的回 null（不猜）', () {
    expect(c.l2ReportActionByTitle('camera-snap'), 'camera:snap');
    expect(c.l2ReportActionByTitle('notif-report'), 'notifications:report');
    expect(c.l2ReportActionByTitle('nope'), isNull);
    expect(c.l2ReportActionByTitle(''), isNull);
  });

  test('图像形态：文字与 JPEG 字节都拆得出来', () {
    final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
    final payload = parse(
      jsonEncode({
        'text': '2026-10-18 12:00 640x480 NT_x.jpg',
        'imageBase64': base64Encode(bytes),
      }),
    );
    expect(payload.text, contains('NT_x.jpg'));
    expect(payload.imageBytes, bytes);
    expect(payload.imageOmitted, isFalse);
  });

  test('字段名从契约读：契约改名 ⇒ 解析跟着改', () {
    final contract = photoContract({
      'textField': 'caption',
      'imageField': 'photo',
      'omittedField': 'photoSkipped',
      'omittedValue': 'oversize',
    });
    final bytes = <int>[1, 2, 3];
    final payload = parseFnthinkReportPayload(
      contract,
      title: 'camera-snap',
      body: jsonEncode({'caption': '一行事实', 'photo': base64Encode(bytes)}),
    );
    expect(payload.text, '一行事实');
    expect(payload.imageBytes, bytes);
  });

  test('超限那一对：发送端说太大 ⇒ 只回那句话，没有图像', () {
    final payload = parse(
      jsonEncode({
        'text': '2026-10-18 12:00 NT_x.jpg',
        'imageOmitted': 'too-large',
      }),
    );
    expect(payload.imageOmitted, isTrue);
    expect(payload.hasImage, isFalse);
    expect(payload.text, contains('NT_x.jpg'));
    // 取值必须逐字等于契约声明的那一枚：写错了就不认（不猜它是「太大」）
    final wrong = parse(jsonEncode({'text': 'x', 'imageOmitted': 'too big'}));
    expect(wrong.imageOmitted, isFalse);
  });

  test('标题不是图像回传 / 不在回传表里 ⇒ 正文原样显示', () {
    final body = jsonEncode({'text': 'x', 'imageBase64': 'AQID'});
    expect(parse(body, title: 'notif-report').text, body);
    expect(parse(body, title: 'no-such-title').text, body);
  });

  test('不是 JSON、或 JSON 里一个字段都对不上 ⇒ 正文原样显示', () {
    expect(parse('温度 63 度').text, '温度 63 度');
    final unknown = jsonEncode({'foo': 'bar'});
    expect(parse(unknown).text, unknown);
  });

  test('base64 坏了 ⇒ 文字保留、图像不渲染（不抛）', () {
    final payload = parse(
      jsonEncode({'text': '一行事实', 'imageBase64': '这不是base64'}),
    );
    expect(payload.text, '一行事实');
    expect(payload.hasImage, isFalse);
  });

  test('base64 字符串超过上限 ⇒ 不解码、直接不渲染', () {
    final cap = c.l2ReportMaxImageBytes('camera:snap')!;
    final maxChars = ((cap + 2) ~/ 3) * 4;
    final payload = parse(
      jsonEncode({'text': '一行事实', 'imageBase64': 'A' * (maxChars + 4)}),
    );
    expect(payload.text, '一行事实');
    expect(payload.hasImage, isFalse);
  });

  test('解码后的原始字节超过上限 ⇒ 不渲染（上限是字节，不是 base64 长度）', () {
    final cap = c.l2ReportMaxImageBytes('camera:snap')!;
    final payload = parse(
      jsonEncode({
        'text': '一行事实',
        'imageBase64': base64Encode(List<int>.filled(cap + 1, 7)),
      }),
    );
    expect(payload.text, '一行事实');
    expect(payload.hasImage, isFalse);
  });

  test('空的 imageBase64 ⇒ 没有图像，文字还在', () {
    final payload = parse(jsonEncode({'text': '一行事实', 'imageBase64': ''}));
    expect(payload.text, '一行事实');
    expect(payload.hasImage, isFalse);
  });

  test('契约把标题改名 ⇒ 收件端按新标题也反查得到', () {
    final contract = edited([
      'capabilities',
      'l2',
      'reports',
      'camera:snap',
      'title',
    ], 'photo-report');
    final bytes = <int>[9, 8, 7];
    final payload = parseFnthinkReportPayload(
      contract,
      title: 'photo-report',
      body: jsonEncode({'text': 'x', 'imageBase64': base64Encode(bytes)}),
    );
    expect(payload.imageBytes, bytes);
  });
}
