import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// shared_preferences_android 的 JNI 读路回退闸（真机 2026-11-08）。
///
/// 2.5.x 把 legacy 读路换成 JNI，其类型转换表只认 Long/Double/String/Boolean/
/// 数组/List/Map，**不认 Integer/Float**；而原生往 FlutterSharedPreferences 写过
/// putInt（FnthinkLiveMode / ChannelAvailability），存量设备文件里就有 `<int>`。
/// 于是 getAll 抛 ArgumentError(JObject)，全应用 SharedPreferences.getInstance()
/// 失败：首页"页面初始化失败"、同意版本读不到每次弹隐私政策、监听开关读不到
/// 界面落回"已停止"而原生服务照跑。上游截至 2.5.4（2026-10-27）无修复。
/// 2.4.x 读路走 pigeon method channel，标准 codec 天然认 Integer/Float。
///
/// 抬回 2.5.x 的前提（两条任一，且要连存量设备一起验）：上游 readValue 补
/// Integer/Float；或原生长整型化＋进程启动处的一次性存量迁移。
/// 理由与退出条款写在 pubspec.yaml 的 override 注释里，这里钉它不被静默拿走。
void main() {
  final root = projectRoot();

  test(
    'shared_preferences_android 解析结果停在 2.4.x（2.5.x JNI 读路不认 Integer/Float）',
    () {
      final lock = File('$root/pubspec.lock').readAsStringSync();
      final version = _lockedVersion(lock, 'shared_preferences_android');
      expect(
        version,
        isNotNull,
        reason: 'pubspec.lock 里找不到 shared_preferences_android',
      );
      expect(
        version,
        startsWith('2.4.'),
        reason:
            '2.5.x 的 JNI getAll 遇 Integer 抛 ArgumentError(JObject)，'
            '存量设备 prefs 里就有原生 putInt 落下的 <int>；抬版本前先清原生写侧或等上游修复',
      );
    },
  );

  test('pubspec 显式 override 钉住 shared_preferences_android 2.4.28', () {
    final pubspec = File('$root/pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('shared_preferences_android: 2.4.28'),
      reason:
          '主依赖 shared_preferences ^2.5.6 会把 android 实现解析到 2.5.4；'
          '没有这条 override，读路就回到不认 Integer 的 JNI 那条',
    );
  });
}

/// 取 lock 里某个包的 version 字段（只扫该包自己的缩进块）。
String? _lockedVersion(String lock, String package) {
  final lines = lock.replaceAll('\r\n', '\n').split('\n');
  final start = lines.indexOf('  $package:');
  if (start < 0) return null;
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('  ') && !line.startsWith('    ')) break;
    final m = RegExp(r'^    version: "([^"]+)"').firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}
