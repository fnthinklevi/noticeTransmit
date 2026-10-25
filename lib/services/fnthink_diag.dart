import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T196：Dart 侧写进 FlutterSharedPreferences 的三枚诊断读数。
///
/// 原生 `FnthinkDiag` 读的是同一组键（它那侧写死了 `flutter.` 前缀；这里写裸键，
/// shared_preferences 插件落盘时会自己加前缀）。两边任何一处改名，界面只会安静地读 0 ——
/// 所以这一对关系由 `test/architecture/fnthink_presence_guard_test.dart` 钉住。
const String kFnthinkDiagLastPollAtKey = 'fnthink_diag_last_poll_at';
const String kFnthinkDiagLastPollStatusKey = 'fnthink_diag_last_poll_status';
const String kFnthinkDiagLastStreamByteAtKey =
    'fnthink_diag_last_stream_byte_at';

/// 写一发 poll 的时刻与结论。失败只留一行 debug 日志：诊断读数坏了不许反过来影响收货。
Future<void> markFnthinkPoll({
  required int atMs,
  required String status,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kFnthinkDiagLastPollAtKey, atMs);
    await prefs.setString(kFnthinkDiagLastPollStatusKey, status);
  } catch (e) {
    debugPrint('[fnthink] poll 诊断读数没落盘：$e');
  }
}

/// 写一发 SSE 字节到达的时刻。每次心跳/唤醒都会调用一次；写盘失败只留日志。
Future<void> markFnthinkStreamByte({required int atMs}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kFnthinkDiagLastStreamByteAtKey, atMs);
  } catch (e) {
    debugPrint('[fnthink] SSE 诊断读数没落盘：$e');
  }
}
