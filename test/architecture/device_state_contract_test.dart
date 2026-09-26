import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/device_state_service.dart';

import '../support/source_guards.dart';

/// T24：亮度 / 网络触发源的跨端与生命周期契约。
///
/// 这一批改的是一条**新链路**（监听 → 采集 → 判定 → 出站），而新链路最容易留的三种洞：
/// ① 类型字符串两端各写一份，改名后静默不触发；② 监听只注册不注销（系统一直持有 Service）；
/// ③ 页面能配、原生不认识（任务书原文点过这条）。三种都不会崩溃，全都只表现为"不响"。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  String kt(String name) => stripComments(
    read('android/app/src/main/kotlin/com/fnthink/notice/$name'),
  );

  group('类型与键名两端同源', () {
    /// 从 Kotlin 源码里取 `val NAME = setOf("a", "b", …)` 的字面量集合。
    Set<String> kotlinSet(String src, String name) {
      final start = src.indexOf('val $name = setOf(');
      expect(
        start,
        greaterThanOrEqualTo(0),
        reason: '原生 $name 不见了/改名 ⇒ 本守卫要重新指向（不许空转）',
      );
      final body = src.substring(start, src.indexOf(')', start));
      // 剥注释后仍需剔掉行尾注释：`"a", // 说明` 里的中文不该被当成类型名
      return RegExp(
        r'"([a-z_]+)"',
      ).allMatches(body).map((m) => m.group(1)!).toSet();
    }

    test('Dart 的四种触发类型 == 原生 DEVICE_STATE_RULE_TYPES', () {
      final engine = kt('NotificationEngine.kt');
      // 原生那侧 DEVICE_STATE 是**两族的并集**（不是再抄一份字面量）⇒ 这里也按并集比对，
      // 并要求"并集"这条事实本身还在：改成第三份字面量清单就会与两个子集各自漂移。
      final brightness = kotlinSet(engine, 'BRIGHTNESS_RULE_TYPES');
      final network = kotlinSet(engine, 'NETWORK_RULE_TYPES');
      expect(
        engine,
        contains(
          'val DEVICE_STATE_RULE_TYPES = BRIGHTNESS_RULE_TYPES + NETWORK_RULE_TYPES',
        ),
        reason: '设备状态族不再是两族之并 ⇒ 有人开始手抄第三份类型清单',
      );
      expect(
        DeviceStateService.deviceStateRuleTypes.toSet(),
        brightness.union(network),
        reason:
            '两端类型集合不一致不会有任何编译期报错，代价是"界面上能配、原生永远不触发"'
            '（${brightness.union(network)} vs ${DeviceStateService.deviceStateRuleTypes}）',
      );
      expect(
        DeviceStateService.brightnessTypes.toSet(),
        brightness,
        reason: '亮度子集不一致 ⇒ 页面会显示滑块、引擎却按网络分支判定',
      );
      expect(network, {'network_connected', 'network_disconnected'});
    });

    test('镜像键两端只差 SharedPreferences 那层 flutter. 前缀', () {
      final cm = kt('ConfigManager.kt');
      final svc = stripComments(read('lib/services/device_state_service.dart'));
      expect(cm, contains('"flutter.device_state_rules"'));
      expect(svc, contains("prefsKey: 'device_state_rules'"));
      expect(cm, contains('"flutter.device_state_notify_enabled"'));
      expect(svc, contains("'device_state_notify_enabled'"));
    });

    test('codec 注册了这一族的缺省形状（否则归一会退回电量族的值）', () {
      final codec = stripComments(read('lib/services/engine_rule_codec.dart'));
      expect(codec, contains("familyDeviceState = 'device_state'"));
      expect(
        codec,
        contains("familyDeviceState: 'brightness_below'"),
        reason:
            '族缺省类型没登记 ⇒ normalize() 会把设备态规则补成 level_below，'
            '界面上看着正常，引擎却按电量规则去比对阈值',
      );
      expect(
        codec,
        contains('familyDeviceState: 20'),
        reason: '缺 value 时的族默认值没登记（同上：凭空造一个用户没配的阈值）',
      );
    });
  });

  group('监听的生命周期：成对、幂等、必撤', () {
    test('两个 watcher 都有 start 与 stop，且 stop 在 onDestroy 里', () {
      final svc = stripComments(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt',
        ),
      );
      final start = svc.indexOf('private fun startDeviceStateWatchers()');
      final stop = svc.indexOf('private fun stopDeviceStateWatchers()');
      expect(start, greaterThan(0), reason: '启动函数不见了');
      expect(stop, greaterThan(0), reason: '停止函数不见了');
      final startBody = svc.substring(start, svc.indexOf('\n    }', start));
      final stopBody = svc.substring(stop, svc.indexOf('\n    }', stop));
      // 两个 watcher 都必须"建 + 撤"成对出现：start 里是构造，stop 里是对应变量的 stop()。
      for (final (type, field) in const [
        ('BrightnessWatcher', 'brightnessWatcher'),
        ('NetworkWatcher', 'networkWatcher'),
      ]) {
        expect(
          startBody.contains(' = $type(') &&
              stopBody.contains('$field?.stop()'),
          isTrue,
          reason:
              '$type 只在一侧出现 ⇒ 注册了没人撤（系统持有回调对象就等于持有整个 Service，'
              '本仓库为这条付过学费）',
        );
      }
      final destroy = svc.substring(svc.indexOf('override fun onDestroy()'));
      expect(
        destroy.substring(0, destroy.indexOf('\n    }')),
        contains('stopDeviceStateWatchers()'),
        reason: 'onDestroy 不撤监听 ⇒ "只注册不注销"那条老缺陷在新代码上重演',
      );
      // 幂等：两处都必须"已经有了就早退"（轮询与广播都会重复调到 start）。
      expect(
        startBody.contains('if (brightnessWatcher == null)') &&
            startBody.contains('if (networkWatcher == null)'),
        isTrue,
        reason: 'start 不判重就是每次调用都新注册一个 observer ⇒ 回调翻倍、同一事件判定两遍',
      );
    });

    test('RetryQueue 的网络回调留了引用并且服务销毁时撤掉', () {
      final rq = stripComments(
        read('android/app/src/main/kotlin/com/fnthink/notice/RetryQueue.kt'),
      );
      expect(
        rq.contains('fun stopWatching()'),
        isTrue,
        reason: '匿名对象直接交给系统 ⇒ 进程内再无句柄，撤不掉',
      );
      expect(
        RegExp(r'networkCallback = (callback|null|object)').hasMatch(rq),
        isTrue,
        reason: '注册后没留住引用（stopWatching 就成了空函数）',
      );
      final svc = stripComments(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt',
        ),
      );
      expect(
        svc.substring(svc.indexOf('override fun onDestroy()')),
        contains('RetryQueue.stopWatching()'),
      );
    });
  });

  group('设备态告警的接缝', () {
    test('触发源的回调只做"再采一次 + 走同一个出站口"', () {
      final svc = stripComments(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt',
        ),
      );
      final start = svc.indexOf('private fun onDeviceStateChanged()');
      expect(start, greaterThan(0));
      final body = svc.substring(start, svc.indexOf('\n    }', start));
      expect(
        body,
        contains('batteryMonitor.checkBatteryAndNotify()'),
        reason: '自己算阈值 = 判据第二份（T19/T21 清的就是这个）',
      );
      expect(
        body,
        contains('dispatchDeviceAlert(info)'),
        reason: '绕过唯一出站口 = T23 的约束开关对这一条路不管用',
      );
      expect(
        body,
        contains('serviceScope.launch'),
        reason: '监听回调在主线程；AppChannelSender 里有 runBlocking + 同步 HTTP ⇒ ANR',
      );
    });

    test('页面不许自己实现判据，也不许绕过删除确认', () {
      final page = stripComments(read('lib/pages/device_state_page.dart'));
      expect(
        page.contains('NotificationEngine') ||
            page.contains('threshold >=') ||
            page.contains('< rule'),
        isFalse,
        reason: 'Dart 页面里出现比较 = 判据抄了第二份',
      );
      expect(
        page,
        contains('IosDialogActions.askConfirm'),
        reason: 'T06：删除必须二次确认，这一族的阈值是拖滑块调出来的',
      );
      expect(page, contains('CardActionSheet.show'));
      expect(
        page,
        contains('_service.deleteRule(id)'),
        reason: '确认之后才真删（删除的调用点只该有这一处）',
      );
      // 复制与新建设都要**现造** id（沿用原 id 会让 update/delete 一次命中两条）。
      // 只数前缀：dart format 会把长行折开，按 `id': 'xxx` 整串匹配会静默失配。
      expect(
        RegExp("'device_rule_").allMatches(page).length,
        greaterThanOrEqualTo(2),
        reason: '只有一处现造 id ⇒ 复制规则沿用了原 id，改一条会同时改中两条',
      );
    });
  });
}
