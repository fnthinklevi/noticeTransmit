import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// P1-1：「长锁屏 / 弱网 / 低内存 / 进程被杀」四类场景的发版回归闸门守卫。
///
/// 为什么闸门本身也要有守卫：本仓库撞过两次「闸门其实不存在」——发版脚本调用的脚本
/// 只躺在本地目录里、以及失败被 `set +e`/`|| true` 吞掉。四类场景都是长跑步骤，
/// 一旦被注释掉或改成静默跳过，报告里看起来仍然是绿的。
void main() {
  final root = projectRoot();
  String read(String rel) => File('$root/$rel').readAsStringSync();
  String readSh(String rel) =>
      stripShellComments(read(rel)).replaceAll('\r\n', '\n');

  group('发版脚本必须挂上稳定性矩阵', () {
    test('release_local.sh 在模拟器全功能闸门之后调用 release_matrix.sh，红不吞', () {
      final src = readSh('.github/scripts/release_local.sh');
      final gate = src.indexOf('bash .github/scripts/release_emulator.sh');
      final matrix = src.indexOf('bash .github/scripts/release_matrix.sh');
      expect(gate, greaterThan(0), reason: '全功能点击闸门被摘掉了');
      expect(matrix, greaterThan(gate), reason: '稳定性矩阵没有接在阶段 6 之后');
      expect(
        RegExp(
          r'bash \.github/scripts/release_matrix\.sh.*?\n.*?ok .*?\n.*?fail ',
          dotAll: true,
        ).hasMatch(src),
        isTrue,
        reason: '矩阵结果没有 ok/fail 两个分支 ⇒ 可能出现「红了但发版继续」',
      );
      expect(
        src.contains('docs/release_regression_matrix.md'),
        isTrue,
        reason: '红的时候必须指向人工项清单，否则只看到一行矩阵失败',
      );
    });

    test('矩阵脚本只允许跑在模拟器上，且由 EXIT trap 收尾', () {
      final src = readSh('.github/scripts/release_matrix.sh');
      expect(
        RegExp(r'emulator-\*\)\s*:').hasMatch(src),
        isTrue,
        reason: '缺少「设备必须是 emulator-*」的判定 = 有误删真机数据的风险',
      );
      expect(
        src.contains('目标设备不是模拟器'),
        isTrue,
        reason: '真机分支必须显式失败，不能在真机上装/卸应用',
      );
      expect(
        RegExp(
          r'^trap\s+cleanup_emulator\s+EXIT',
          multiLine: true,
        ).hasMatch(src),
        isTrue,
        reason: '只在末尾关闭模拟器 ⇒ 失败/中断路径会把模拟器留在后台',
      );
      expect(
        RegExp(r'emu kill').allMatches(src).length,
        1,
        reason: '关闭动作只允许一处，且必须在 trap 里',
      );
    });
  });

  group('四类场景都必须留下可执行的步骤（不是只写在注释里）', () {
    final src = readSh('.github/scripts/release_matrix.sh');

    test('进程被杀：am kill，必要时 force-stop 兜底', () {
      expect(src.contains('am kill'), isTrue);
      expect(
        src.contains('am force-stop'),
        isTrue,
        reason: '前台服务保护下 am kill 杀不掉，必须能兜底',
      );
      expect(src.contains('进程被杀-重新打开'), isTrue);
    });

    test('低内存：真的发 RUNNING_CRITICAL，且失败不许静默', () {
      expect(src.contains('am send-trim-memory'), isTrue);
      expect(src.contains('RUNNING_CRITICAL'), isTrue);
      expect(
        RegExp(r'am send-trim-memory.*?\n[\s\S]{0,400}?fail ').hasMatch(src),
        isTrue,
        reason: '裁剪命令失败必须判红，不能当成「测过了」',
      );
    });

    test('弱网：优先模拟器限速，限不了时退回断网并验证 ping', () {
      expect(src.contains('network delay gprs'), isTrue);
      expect(src.contains('network speed gsm'), isTrue);
      expect(src.contains('svc wifi disable'), isTrue);
      expect(
        src.contains('ping -c 1'),
        isTrue,
        reason: '不验证是否真断网，「断网」可能只是关了个开关',
      );
      expect(
        src.contains('弱网：模拟器无法切断默认网络'),
        isTrue,
        reason: '模拟器断不了网时必须显式 SKIP 并指向真机人工项',
      );
    });

    test('长锁屏：真的熄屏并保持，时长可调', () {
      expect(src.contains('KEYCODE_POWER'), isTrue);
      expect(src.contains('MATRIX_LOCK_SECONDS'), isTrue);
      expect(src.contains('dismiss-keyguard'), isTrue);
      expect(src.contains('长锁屏-唤醒'), isTrue);
    });

    test('没跑成（SKIP）默认判红，不许把「没跑」当成「通过」', () {
      expect(src.contains('MATRIX_ALLOW_SKIP'), isTrue);
      expect(
        RegExp(r'SKIP.*?"\s-gt\s+0[\s\S]{0,600}?exit 1').hasMatch(src),
        isTrue,
        reason: 'SKIP 默认必须让脚本非 0 退出；否则环境限制会静默变成绿灯',
      );
    });
  });

  test('矩阵文档写清四类场景与人工项', () {
    final doc = read('docs/release_regression_matrix.md');
    for (final keyword in const ['长锁屏', '弱网', '低内存', '进程被杀']) {
      expect(doc.contains(keyword), isTrue, reason: '文档缺场景「$keyword」');
    }
    expect(doc.contains('≥8 小时'), isTrue, reason: '过夜锁屏必须明确写成人工项');
    expect(doc.contains('覆盖安装升级'), isTrue, reason: '迁移备份的验证方式没有写进矩阵');
  });
}
