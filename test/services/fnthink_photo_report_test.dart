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
}
