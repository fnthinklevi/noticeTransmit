import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T124②：画面字节从原生交到 Dart 的那条线，两端各只写一次键名。
///
/// 行为用例只能证明「拿一个带 imageBytes 的 map 进来，payload 里有图」——
/// 它证明不了原生真的写了那个键（写错成 `image` 时，Dart 静默退回纯文字，
/// 用例仍然绿：照片永远发不出去，而两边都没有红）。
/// 这一页钉的就是那一维：键名、执行器调用点、以及「上限只有一个作者」。
void main() {
  final root = projectRoot();
  final kt = stripComments(
    File(
      '$root/android/app/src/main/kotlin/com/fnthink/notice/CameraSnap.kt',
    ).readAsStringSync(),
  );
  final report = stripComments(
    librarySource(root, 'lib/services/fnthink_photo_report.dart'),
  );
  final locator = stripComments(
    librarySource(root, 'lib/di/service_locator.dart'),
  );

  test('原生写出的键与 Dart 读的键逐字相同', () {
    expect(
      kt,
      contains('"imageBytes" to jpeg'),
      reason: 'CameraSnap 成功那一格没把 JPEG 字节交出来 —— 照片回传会静默降级成纯文字',
    );
    expect(report, contains("snap['imageBytes']"), reason: '载荷组装读的不是原生写的那个键');
  });

  test('执行器走的是图像载荷组装，不是只拼文字那条', () {
    expect(
      locator,
      contains("formatFnthinkPhotoPayload(snap, contract, 'camera:snap')"),
      reason: '接线一旦退回 formatFnthinkPhotoReport，图像分支永远执行不到',
    );
    expect(
      locator,
      isNot(contains('formatFnthinkPhotoReport(snap)')),
      reason: '两处都在拼正文时，图像分支就多了一个绕过去的入口',
    );
  });

  test('上限只有一个作者：原生不写那个数，Dart 从契约读', () {
    expect(
      kt,
      isNot(contains('32768')),
      reason: '原生写死上限后，契约调大调小都不会生效（或反过来在边界上多丢一张）',
    );
    expect(
      report,
      contains('l2ReportMaxImageBytes(action)'),
      reason: '载荷组装自己写上限就是第二份真值',
    );
  });
}
