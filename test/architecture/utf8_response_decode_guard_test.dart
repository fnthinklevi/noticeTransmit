import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T85(a)：HTTP 响应体的解码方式必须钉死在 UTF-8 上（`response.body` 这条路一律不许再有）。
///
/// 为什么这条必须靠守卫而不是靠用例：`package:http` 的 `.body` 按 content-type 的 charset 解，
/// 而**没有 charset 时 `text/*` 与干脆没有 content-type 的响应用 latin-1**（`application/json`
/// 那一档它已经按 UTF-8 —— 这三条都是本机实测出来的，不是"听说 .body 是 latin-1"）。
/// 线上此刻服务端带 `charset=utf-8`，所以今天是好的；坏的时刻是**反代/CDN/WAF 把类型改成
/// `text/plain` 或整段吃掉 content-type** 那一刻 —— UTF-8 的中文会被"解成功"成 mojibake，
/// 然后被当成真内容落进收件表、上通知栏、显示到更新弹窗（那种坏不报错，只有用户看得见）。
/// 所以判据钉在写法上：
///  - 读体只许 `utf8.decode(response.bodyBytes, allowMalformed: false)`；
///  - `allowMalformed: true` 不许出现 —— 那是把"抛错"换回"静默替换成 U+FFFD"，
///    而静默替换正是这次乱码的形状。
void main() {
  final root = projectRoot();

  String code(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  final libFiles = Directory('$root/lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  group('响应体解码（T85a）', () {
    test('全 lib 不许再用 response.body（正向锚：一个文件都没扫到就该红）', () {
      expect(libFiles.length, greaterThan(50));
      final offender = RegExp(r'\b(response|res|resp)\.body\b');
      for (final f in libFiles) {
        final src = stripComments(f.readAsStringSync());
        expect(
          offender.hasMatch(src),
          isFalse,
          reason:
              '${f.path} 用 `.body` 读响应体 ⇒ 一旦这一发的 content-type 是 text/* 或干脆没有'
              '（反代/CDN 改写的常见结果），中文就被按 latin-1 "解成功"成 mojibake 当真内容用出去',
        );
      }
    });

    test('三处读体各在自己那份文件里走严格 UTF-8', () {
      // 逐文件点名，而不是"全仓数一次"：少改一处时要知道少的是哪一处
      //（这三处的失败后果完全不同：幻念那一发坏的是收件正文，更新那两处坏的是弹窗文案）。
      const sites = [
        'lib/services/fnthink_receiver_service.dart',
        'lib/update_manager.dart',
      ];
      for (final rel in sites) {
        final src = code(rel);
        expect(
          src,
          contains('utf8.decode('),
          reason: '$rel 不再严格解码 ⇒ 坏字节会被静默处理或直接当合法文本',
        );
        expect(
          src,
          contains('response.bodyBytes'),
          reason: '$rel 要从字节那一路读，`.body` 那条按 charset 走、缺省 latin-1',
        );
        expect(
          src,
          contains('allowMalformed: false'),
          reason: '$rel 少了这个参数就是允许静默替换（U+FFFD）—— 那正是乱码的形状',
        );
      }
      // update_manager 有两处（API 与静态 version.json），都得在
      expect(
        RegExp('allowMalformed: false').allMatches(code(sites[1])).length,
        greaterThanOrEqualTo(2),
        reason: '静态 version.json 那一发漏掉时，changelog 里的中文还是走 latin-1 那条路',
      );
    });

    test('全 lib 不许出现 allowMalformed: true（那是把抛错换回静默替换）', () {
      for (final f in libFiles) {
        expect(
          stripComments(f.readAsStringSync()),
          isNot(contains('allowMalformed: true')),
          reason: '${f.path} 允许畸形字节 ⇒ 坏的那条通知会以"看起来正常"的样子显示出来',
        );
      }
    });
  });
}
