import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_remote_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 远程执行 片3b：延时窗口与总开关那一层（**范围与生效值都从契约来**）。
///
/// 这一组钉的是四件：
///  ① 默认关（升级不许悄悄替用户把"别人能让我做事"打开）；
///  ② 没选过就用契约 default，选过就用选的 —— 两者在界面上要分开说；
///  ③ 越界**抛**不悄悄夹（"界面写 60、实际按 10 跑"是用户看不出来的那类错）；
///  ④ 读的时候也校验（备份恢复会把 prefs 原样灌回来）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  late FnthinkRemoteSettings settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = FnthinkRemoteSettings(contract: contract);
  });

  group('总开关', () {
    test('默认关（从没存过就是关）', () async {
      expect(await settings.enabled, isFalse);
    });

    test('写进去之后读回来是同一个值', () async {
      await settings.setEnabled(true);
      expect(await settings.enabled, isTrue);
      await settings.setEnabled(false);
      expect(await settings.enabled, isFalse);
    });

    test('键不与幻念推送的接收开关共用（关远程执行不该连带关接收）', () {
      expect(
        FnthinkRemoteSettings.keyEnabled,
        isNot('fnthink.receive_enabled'),
      );
    });
  });

  group('延时窗口：范围来自契约', () {
    test('范围与契约逐项一致（不写死 0–60）', () {
      expect(
        settings.delaySecondsRange.min,
        contract.remoteExecutionDelayMinSeconds,
      );
      expect(
        settings.delaySecondsRange.max,
        contract.remoteExecutionDelayMaxSeconds,
      );
    });

    test('没选过时用契约给的默认档', () async {
      expect(await settings.delaySeconds, isNull);
      expect(
        await settings.effectiveDelaySeconds(),
        contract.remoteExecutionDelayDefaultSeconds,
      );
    });

    test('维护者定的是默认 10s、最长 60s、最短 0s', () {
      // 这一条把"契约里那三个数"本身钉住（2026-10-03 定稿）。
      expect(contract.remoteExecutionDelayDefaultSeconds, 10);
      expect(contract.remoteExecutionDelayMinSeconds, 0);
      expect(contract.remoteExecutionDelayMaxSeconds, 60);
      expect(contract.remoteExecutionOnTimeout, 'execute');
      expect(contract.remoteExecutionPresenceAffectsTiming, isFalse);
    });

    test('选了之后生效的就是选的那一档', () async {
      await settings.setDelaySeconds(30);
      expect(await settings.delaySeconds, 30);
      expect(await settings.effectiveDelaySeconds(), 30);
    });

    test('抹掉选择 = 回到"从没选过"，契约默认重新生效', () async {
      await settings.setDelaySeconds(45);
      await settings.clearDelaySeconds();
      expect(await settings.delaySeconds, isNull);
      expect(
        await settings.effectiveDelaySeconds(),
        contract.remoteExecutionDelayDefaultSeconds,
      );
    });

    test('0 秒是合法的一档（等于关掉延时）', () async {
      await settings.setDelaySeconds(0);
      expect(await settings.delaySeconds, 0);
      expect(await settings.effectiveDelaySeconds(), 0);
    });
  });

  group('越界：抛，不悄悄夹', () {
    test('写 61（超出上限）抛，且一个字节都不写', () async {
      await expectLater(
        settings.setDelaySeconds(61),
        throwsA(isA<FnthinkRemoteSettingsInvalid>()),
      );
      expect(await settings.delaySeconds, isNull, reason: '越界那一次不许落盘');
    });

    test('写 -1 抛', () async {
      await expectLater(
        settings.setDelaySeconds(-1),
        throwsA(isA<FnthinkRemoteSettingsInvalid>()),
      );
      expect(await settings.delaySeconds, isNull);
    });

    test('读的时候也校验（备份恢复灌回来的坏值当没选过但要报出来）', () async {
      SharedPreferences.setMockInitialValues({
        FnthinkRemoteSettings.keyDelaySeconds: 600,
      });
      await expectLater(
        settings.delaySeconds,
        throwsA(isA<FnthinkRemoteSettingsInvalid>()),
      );
      // 那一格仍然要能被改回来，所以读口按"没选过"处理并把问题报出来。
      final read = await settings.delaySetting();
      expect(read.problem, isNotNull);
      expect(read.chosen, isNull);
      expect(read.effective, contract.remoteExecutionDelayDefaultSeconds);
      await settings.setDelaySeconds(20);
      expect((await settings.delaySetting()).problem, isNull);
    });
  });

  group('一次读齐那一格', () {
    test('四个值一起给（页面不自己拼）', () async {
      await settings.setDelaySeconds(20);
      final read = await settings.delaySetting();
      expect(read.range.min, contract.remoteExecutionDelayMinSeconds);
      expect(read.range.max, contract.remoteExecutionDelayMaxSeconds);
      expect(read.chosen, 20);
      expect(read.effective, 20);
      expect(read.problem, isNull);
    });

    test('"用户选的"与"协议默认"是两种来源（界面上要分开说）', () async {
      final never = await settings.delaySetting();
      expect(never.chosen, isNull);
      expect(never.effective, contract.remoteExecutionDelayDefaultSeconds);
      await settings.setDelaySeconds(
        contract.remoteExecutionDelayDefaultSeconds,
      );
      final picked = await settings.delaySetting();
      expect(
        picked.chosen,
        contract.remoteExecutionDelayDefaultSeconds,
        reason: '选了恰好等于默认的那一档，仍然是"用户选过"',
      );
    });

    test('契约缺 min/max 时抛（不补默认值：界面上那根滑杆的两端会无处可取）', () {
      final broken = FnthinkContract({
        ...contract.raw,
        'capabilities': {
          ...(contract.raw['capabilities']! as Map<String, Object?>),
          'remoteExecution': {
            ...(contract.raw['capabilities']!
                    as Map<String, Object?>)['remoteExecution']!
                as Map<String, Object?>,
            'delay': {'defaultSeconds': 10},
          },
        },
      });
      expect(
        () => FnthinkRemoteSettings(contract: broken).delaySecondsRange,
        throwsA(isA<FnthinkRemoteSettingsInvalid>()),
      );
    });
  });
}
