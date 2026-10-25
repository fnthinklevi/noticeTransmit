import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_diag.dart';
import 'package:notice_transmit/services/fnthink_presence_scheduler.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receive_loop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T196：诊断读数只落时间/状态/原因，且 `diag` 缺格与"全 0"必须分得开。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Dart 写 poll / SSE 三枚键，原生读的是同一组（带 flutter. 前缀）', () async {
    await markFnthinkPoll(atMs: 1700000000000, status: 'ok');
    await markFnthinkStreamByte(atMs: 1700000001000);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(kFnthinkDiagLastPollAtKey), 1700000000000);
    expect(prefs.getString(kFnthinkDiagLastPollStatusKey), 'ok');
    expect(prefs.getInt(kFnthinkDiagLastStreamByteAtKey), 1700000001000);
    // 裸键名（shared_preferences 真正落盘的形状由插件加前缀；这里钉的是 Dart 侧那一半）。
    expect(kFnthinkDiagLastPollAtKey, 'fnthink_diag_last_poll_at');
    expect(kFnthinkDiagLastPollStatusKey, 'fnthink_diag_last_poll_status');
    expect(kFnthinkDiagLastStreamByteAtKey, 'fnthink_diag_last_stream_byte_at');
  });

  test('fromMap 读回 diag；没有 diag 这一格时是 null，不是全 0', () {
    final withDiag = FnthinkPresenceStatus.fromMap({
      'nextRoundAt': 1700000000000,
      'cadenceSeconds': 20,
      'diag': {
        'lastAlarmFiredAt': 1700000000100,
        'lastWorkerStartedAt': 1700000000200,
        'lastWorkerFinishedAt': 1700000000300,
        'lastWorkerResult': 'success',
        'lastPollAt': 1700000000400,
        'lastPollStatus': 'ok',
        'lastStreamByteAt': 1700000000500,
        'deviceIdle': true,
        'batteryOptimizationIgnored': false,
        'powerSaveMode': false,
        'exactAlarmAllowed': true,
      },
    });
    final diag = withDiag.diag!;
    expect(diag.lastAlarmFiredAt, 1700000000100);
    expect(diag.lastWorkerResult, 'success');
    expect(diag.lastPollStatus, 'ok');
    expect(diag.lastStreamByteAt, 1700000000500);
    expect(diag.deviceIdle, isTrue);
    expect(diag.batteryOptimizationIgnored, isFalse);
    expect(diag.exactAlarmAllowed, isTrue);

    final withoutDiag = FnthinkPresenceStatus.fromMap({
      'nextRoundAt': 1700000000000,
      'cadenceSeconds': 20,
    });
    expect(
      withoutDiag.diag,
      isNull,
      reason: '旧原生没有 diag 格 ⇒ 页面不画这一块；把它读成全 0 就是伪造"还没有记录"',
    );
  });

  test('poll 结论压缩：成功不带原因，失败把原因带上', () {
    expect(
      fnthinkPollDiagStatus(
        const FnthinkLoopReport(
          status: FnthinkPollStatus.ok,
          nextDelay: Duration(seconds: 20),
        ),
      ),
      'ok',
    );
    expect(
      fnthinkPollDiagStatus(
        const FnthinkLoopReport(
          status: FnthinkPollStatus.failed,
          reason: 'transport',
          nextDelay: Duration(seconds: 20),
        ),
      ),
      'failed:transport',
    );
  });
}
