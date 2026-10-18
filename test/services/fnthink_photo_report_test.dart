import 'dart:convert';
import 'dart:typed_data';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_photo_report.dart';

/// 「让这台拍一张」那段正文的组装（T124 片C-3 的 `camera:snap`）。
///
/// 钉四件：
///  ① 时间 ＋ 尺寸 ＋ 文件名三件都在（尺寸缺了不编）；
///  ② **不写"已保存到相册"这类话** —— 29+ 是相册、24–28 是本 app 图片目录，
///     一句话不能两边都真（措辞怎么漂，这一条就怎么红）；
///  ③ 方位中立（不带中文）；
///  ④ 没有文件名 ⇒ 空串（调用方读成"没成"，不拿"拍成功了"的空话冒充）。
void main() {
  group('拍照回传正文', () {
    test('时间 + 尺寸 + 文件名三件都在', () {
      final text = formatFnthinkPhotoReport({
        'snap': true,
        'name': 'NT_20261010_093100.jpg',
        'width': 640,
        'height': 480,
        'timeMillis': 1752205200000,
      });
      expect(text, contains('NT_20261010_093100.jpg'));
      expect(text, contains('640x480'));
      expect(RegExp(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}').hasMatch(text), isTrue);
    });

    test('不写"已保存到相册"这类话（29+ 是相册、24–28 是本 app 图片目录）', () {
      final text = formatFnthinkPhotoReport({
        'snap': true,
        'name': 'NT_x.jpg',
        'width': 640,
        'height': 480,
        'timeMillis': 1752205200000,
      });
      for (final word in [
        '\u76f8\u518c',
        '\u5df2\u4fdd\u5b58',
        '\u56fe\u5e93',
      ]) {
        expect(text, isNot(contains(word)), reason: '正文里不许出现「$word」');
      }
    });

    test('方位中立：这段正文里一个汉字都不带', () {
      final text = formatFnthinkPhotoReport({
        'name': 'NT_x.jpg',
        'width': 640,
        'height': 480,
        'timeMillis': 1752205200000,
      });
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(text), isFalse);
    });

    test('尺寸/时间缺了各自空着；文件名缺了 ⇒ 空串', () {
      expect(formatFnthinkPhotoReport(const {'name': 'NT_x.jpg'}), 'NT_x.jpg');
      expect(formatFnthinkPhotoReport(const {}), '');
      expect(formatFnthinkPhotoReport(const {'name': '   '}), '');
      // ⚠ 名空但尺寸/时间都在：也要空串 —— 没有指代的一串时间尺寸不是一条成功的读数
      //   （这一口是那条  守卫唯一可观察的形状；不喂它 = 守卫是摆设）。
      expect(
        formatFnthinkPhotoReport(const {
          'name': '  ',
          'width': 640,
          'height': 480,
          'timeMillis': 1752205200000,
        }),
        '',
      );
      // 尺寸是半个（宽有高没有）也不编：写一个假的宽高比"没有"更容易被读错
      expect(
        formatFnthinkPhotoReport(const {'name': 'N.jpg', 'width': 640}),
        'N.jpg',
      );
    });
  });

  group('拍照回传的图像形态（T124②）', () {
    const name = 'NT_20261010_093100.jpg';

    /// 只把 `camera:snap` 那一格改掉、其余原样 —— 红的只可能是被改的那一维。
    FnthinkContract photoContract([Map<String, Object?> patch = const {}]) {
      final root =
          jsonDecode(jsonEncode(FnthinkContract.readFile().raw))
              as Map<String, dynamic>;
      final spec =
          root['capabilities']['l2']['reports']['camera:snap']
              as Map<String, dynamic>;
      spec.addAll(patch);
      return FnthinkContract.parse(jsonEncode(root));
    }

    Map<String, Object?> snapWith(List<int>? bytes) => {
      'snap': true,
      'name': name,
      'width': 640,
      'height': 480,
      'timeMillis': 1752205200000,
      if (bytes != null) 'imageBytes': Uint8List.fromList(bytes),
    };

    test('契约说 image ⇒ 正文是 JSON：事实文字 + base64（字段名从契约来）', () {
      final contract = photoContract();
      final bytes = [0xFF, 0xD8, 0xFF, 0xD9];
      final payload = formatFnthinkPhotoPayload(
        snapWith(bytes),
        contract,
        'camera:snap',
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      expect(map.keys, unorderedEquals(['text', 'imageBase64']));
      expect(map['text'], contains(name));
      expect(base64Decode(map['imageBase64'] as String), bytes);
      expect(contract.l2ReportImageMime('camera:snap'), 'image/jpeg');
    });

    test('字段名不是写死的：契约改名 ⇒ payload 跟着改', () {
      final contract = photoContract(const {
        'textField': 'caption',
        'imageField': 'photo',
        'omittedField': 'photoSkipped',
      });
      final payload = formatFnthinkPhotoPayload(
        snapWith([1, 2, 3]),
        contract,
        'camera:snap',
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      expect(map.keys, unorderedEquals(['caption', 'photo']));
      expect(map['caption'], contains(name));
    });

    test('恰好在上限上 ⇒ 还是带图（上限是「≤」）', () {
      final contract = photoContract();
      final cap = contract.l2ReportMaxImageBytes('camera:snap')!;
      final payload = formatFnthinkPhotoPayload(
        snapWith(List<int>.filled(cap, 7)),
        contract,
        'camera:snap',
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      expect((map['imageBase64'] as String).isNotEmpty, isTrue);
    });

    test('超过上限 ⇒ 不截断：没有图像，只有契约声明的那一对', () {
      final contract = photoContract();
      final cap = contract.l2ReportMaxImageBytes('camera:snap')!;
      final payload = formatFnthinkPhotoPayload(
        snapWith(List<int>.filled(cap + 1, 7)),
        contract,
        'camera:snap',
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      expect(map.containsKey('imageBase64'), isFalse);
      expect(map['imageOmitted'], 'too-large');
      expect(map['text'], contains(name));
      // 截断的照片解不开、而发的人以为发出去了 —— 这一发宁可说"太大"
      expect(map.values.any((v) => v is String && v.length > cap), isFalse);
    });

    test('超限那一对与上限也从契约读：改上限/改取值 ⇒ 跟着变', () {
      final contract = photoContract(const {
        'maxImageBytes': 8,
        'omittedField': 'skipped',
        'omittedValue': 'nope',
      });
      final over =
          jsonDecode(
                formatFnthinkPhotoPayload(
                  snapWith(List<int>.filled(9, 1)),
                  contract,
                  'camera:snap',
                ),
              )
              as Map<String, dynamic>;
      expect(over['skipped'], 'nope');
      expect(over.containsKey('imageBase64'), isFalse);
      final ok =
          jsonDecode(
                formatFnthinkPhotoPayload(
                  snapWith(List<int>.filled(8, 1)),
                  contract,
                  'camera:snap',
                ),
              )
              as Map<String, dynamic>;
      expect(ok.containsKey('imageBase64'), isTrue);
    });

    test('字节缺失或为空 ⇒ 退回纯文字（旧渲染端至少还能读）', () {
      final contract = photoContract();
      for (final bytes in [null, const <int>[]]) {
        final text = formatFnthinkPhotoPayload(
          snapWith(bytes),
          contract,
          'camera:snap',
        );
        expect(text, contains(name));
        expect(text.startsWith('{'), isFalse);
      }
    });

    test('契约不是 image 的动作 ⇒ 即便带了字节也只回文字', () {
      final text = formatFnthinkPhotoPayload(
        snapWith([1, 2, 3]),
        photoContract(),
        'notifications:report',
      );
      expect(text, contains(name));
      expect(text.startsWith('{'), isFalse);
    });
  });
}
