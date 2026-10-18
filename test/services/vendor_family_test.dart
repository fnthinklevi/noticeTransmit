import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/permission_service.dart';
import 'package:notice_transmit/services/vendor_family.dart';

/// T140 (b) ②「自启动引导补齐」的判据：厂商分流表**只有一张**，而"这一台跳不跳"由它说了算。
///
/// 立这一片的原因是一条实测到的分裂（三份表：L3 派发、权限页、小组件引导页）：
/// 荣耀／红米／真我／一加／iQOO 那几台在权限页**能跳**，而 L3 的 `autostart` 那一发
/// 落进"都对不上"那一支 ⇒ **一个通道调用都不发**。这一族又读不到状态，
/// 所以那台机器上唯一可见的事实就是"点了没反应"，而审计日志里没有这一条。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('分流表（唯一作者）', () {
    test('各家变体都认得：红米／MI 8 算小米，荣耀算华为，iQOO 算 vivo，真我与一加算 oppo', () {
      for (final raw in ['Xiaomi', 'XIAOMI Inc.', 'Redmi K40', 'MI 8']) {
        expect(
          fnthinkVendorFamilyOf(raw),
          FnthinkVendorFamily.xiaomi,
          reason: raw,
        );
      }
      expect(fnthinkVendorFamilyOf('HUAWEI'), FnthinkVendorFamily.huawei);
      expect(fnthinkVendorFamilyOf('HONOR'), FnthinkVendorFamily.huawei);
      expect(fnthinkVendorFamilyOf('realme'), FnthinkVendorFamily.oppo);
      expect(fnthinkVendorFamilyOf('OnePlus'), FnthinkVendorFamily.oppo);
      expect(fnthinkVendorFamilyOf('iQOO 9'), FnthinkVendorFamily.vivo);
      expect(fnthinkVendorFamilyOf('MEIZU 21'), FnthinkVendorFamily.meizu);
      expect(fnthinkVendorFamilyOf('SAMSUNG'), FnthinkVendorFamily.samsung);
    });

    test('原生／认不出／空串是同一档（通用文字引导、不给跳），不是"没识别所以什么都不做"', () {
      for (final raw in [
        'Google',
        'AOSP Android 15',
        '',
        'TotallyUnknownBrand',
      ]) {
        expect(
          fnthinkVendorFamilyOf(raw),
          FnthinkVendorFamily.stock,
          reason: "'$raw'",
        );
      }
    });

    test('一条串命中两家时只有一个答案：优先级是**表里**的顺序，不是输入里的顺序', () {
      expect(fnthinkVendorFamilyOf('huawei vivo'), FnthinkVendorFamily.huawei);
      // 反过来的输入串必须给同一个答案：否则"这一台算哪一家"就有两本账
      expect(fnthinkVendorFamilyOf('vivo huawei'), FnthinkVendorFamily.huawei);
    });
  });

  group('可跳名单与真发的那一发', () {
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppChannels.notification, (call) async {
            calls.add(call.method);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppChannels.notification, null);
    });

    test('五族各有对应那一发；三星与原生是 null（那是真话，不是漏了一格）', () {
      final jumps = {
        FnthinkVendorFamily.xiaomi: 'requestXiaomiAutoStart',
        FnthinkVendorFamily.meizu: 'requestMeizuBackground',
        FnthinkVendorFamily.huawei: 'requestHuaweiLaunch',
        FnthinkVendorFamily.oppo: 'requestOppoBackground',
        FnthinkVendorFamily.vivo: 'requestVivoBackground',
      };
      for (final entry in jumps.entries) {
        expect(
          fnthinkAutostartJumpFor(entry.key),
          isNotNull,
          reason: '${entry.key} 必须给得出那一发',
        );
      }
      expect(
        fnthinkAutostartJumpFor(FnthinkVendorFamily.samsung),
        isNull,
        reason: '三星没有可跳的入口名：猜一个就是把用户送进别家的页面',
      );
      expect(fnthinkAutostartJumpFor(FnthinkVendorFamily.stock), isNull);
    });

    test('荣耀那台真的发出 requestHuaweiLaunch（合并前三张表时这一发是零调用）', () async {
      await fnthinkRequestVendorAutoStart(
        manufacturer: 'HONOR 90',
        permissions: PermissionService(),
      );
      expect(calls, ['requestHuaweiLaunch']);
    });

    test('红米那台发出小米那一发（同一个变体缺口，另一家）', () async {
      await fnthinkRequestVendorAutoStart(
        manufacturer: 'Redmi K70',
        permissions: PermissionService(),
      );
      expect(calls, ['requestXiaomiAutoStart']);
    });

    test('三星那台一个通道调用都不发（不许把用户送进别家的自启动页）', () async {
      // 用 `samsung` 这个真值而不是型号串：型号串（SM-S9210）里并不含厂商名，
      // 拿它测会"因为认不出所以不发"而通过 —— 那不是这一条要钉的形状。
      await fnthinkRequestVendorAutoStart(
        manufacturer: 'samsung',
        permissions: PermissionService(),
      );
      expect(calls, isEmpty);
    });
  });
}
