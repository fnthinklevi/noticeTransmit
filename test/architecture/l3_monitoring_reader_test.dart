import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T52 收尾：权限页那一格的 `monitoring`（监听开关）**从「读不到」变成真读数**之后，
/// 把这条链上三件编译器管不到的事钉住。
///
/// 背景：这一格原先在装配处传 `null`（= 界面显示「读不到这台设备的状态」）——
/// 当时是真的没有读口。现在读口是**已有**的通道方法 `isServiceRunning`
/// （Kotlin 侧返回 `isMonitoringEnabled()`，读的是原生 SharedPreferences 里那个开关）。
/// 三件事都容易在后续改动里悄悄坏掉：
///  ① 装配处再传回 `null`（界面又会说「读不到」，看着像设备问题）；
///  ② 跨语言的通道方法名只改一边（Dart 调 `isServiceRunning`，Kotlin 改名 ⇒ 静默 false）；
///  ③ 读之前不刷新（`serviceRunning` 默认 false ⇒ 把「我们没问」显示成「用户没给」）。
void main() {
  final actions = File('lib/pages/main_page_actions.dart').readAsStringSync();
  final notifService = File(
    'lib/services/notification_service.dart',
  ).readAsStringSync();
  final deviceHandler = File(
    'android/app/src/main/kotlin/com/fnthink/notice/channels/DeviceChannelHandler.kt',
  ).readAsStringSync();

  /// 装配处 `_l3GrantRows()` 的函数体（从函数名到最后一行 `}` 之前）。
  String assemblyBody() {
    final start = actions.indexOf('_l3GrantRows() async {');
    expect(start, isNot(-1), reason: '装配函数改名了 ⇒ 下面三条全在测空气');
    final end = actions.indexOf('\n  /// 打开短信/来电监听设置页', start);
    expect(end, isNot(-1), reason: '找不到函数尾 ⇒ 换个锚点，别让切片悄悄截断');
    return actions.substring(start, end);
  }

  test('① 装配处不再把 monitoring 传成 null（那是"读不到"，不是"没给"）', () {
    final body = assemblyBody();
    final m = RegExp(r'monitoring:\s*([^,\n]+),').firstMatch(body);
    expect(m, isNotNull, reason: '没传 monitoring ⇒ 那一格会显示成读不到');
    expect(
      m!.group(1)!.trim(),
      isNot('null'),
      reason: '读口已经有了（见 ②），再传 null 就是把"没问"说成"读不到"',
    );
  });

  test('② 通道方法名两边一致：Dart 调的那个名字，Kotlin 侧真有分支', () {
    final call = RegExp(
      r"invokeMethod\('(isServiceRunning)'\)",
    ).firstMatch(notifService);
    expect(call, isNotNull, reason: 'Dart 侧不再调 isServiceRunning ⇒ 这条断言要跟着改主语');
    final name = call!.group(1)!;
    expect(
      RegExp('"$name"\\s*->').hasMatch(deviceHandler),
      isTrue,
      reason:
          'Kotlin 侧没有这个分支：调用会抛 MissingPluginException 或被 catch 成 false ——'
          '而 false 会显示成「还没给这台设备授权」，两句话都不是真相',
    );
  });

  test('③ 读之前先刷新（默认 false 会被显示成"没给"）', () {
    final body = assemblyBody();
    final refresh = body.indexOf('loadServiceState()');
    final read = body.indexOf('monitoring:');
    expect(refresh, isNot(-1), reason: '没有刷新就读 ⇒ 读到的是上一次的旧值');
    expect(read, isNot(-1));
    expect(refresh < read, isTrue, reason: '刷新要在读之前：顺序反了等于读旧值，而旧值默认是 false');
  });
}
