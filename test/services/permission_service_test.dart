import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/permission_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';

/// 应用列表权限的三态解析（㊸）。
///
/// 背景：真机实测（MEIZU 21）系统权限历史显示「读取应用列表」已拒绝，
/// 应用内权限页却显示"已授予"。根因是原生用布尔承载状态、并在拿不到
/// AppOps 读数时 `?: return true`。现在跨端传 `granted|denied|unknown`，
/// 本文件锁住"只有 granted 才算已授予"这条线。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = AppChannels.notification;
  late List<MethodCall> calls;

  /// 按方法名回值。⚠ 不能对所有方法回同一个值：`checkAllPermissions` 里其它权限走
  /// `as bool?`，回一个 String 会抛 TypeError 被服务的 try/catch 吞掉，
  /// 于是断言看到的是"状态没更新"而不是"解析错"（本文件第一版就踩了这个坑）。
  void mockWith(
    Object? Function(MethodCall call) handler, {
    Object? appListState = 'unknown',
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getAppListPermissionState') return appListState;
          return handler(call);
        });
  }

  setUp(() => calls = []);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PermissionService – 应用列表权限三态', () {
    test('granted → appListGranted 为真', () async {
      mockWith((_) => true, appListState: 'granted');
      final service = PermissionService();
      await service.checkAllPermissions();
      expect(service.appListPermission, AppListPermission.granted);
      expect(service.appListGranted, isTrue);
    });

    test('denied → 未授予', () async {
      mockWith((_) => true, appListState: 'denied');
      final service = PermissionService();
      await service.checkAllPermissions();
      expect(service.appListPermission, AppListPermission.denied);
      expect(service.appListGranted, isFalse);
    });

    test('unknown → 不得显示为已授予（旧实现说谎的那一格）', () async {
      mockWith((_) => true, appListState: 'unknown');
      final service = PermissionService();
      await service.checkAllPermissions();
      expect(service.appListPermission, AppListPermission.unknown);
      expect(
        service.appListGranted,
        isFalse,
        reason: '系统不给明确状态 ≠ 已授予；权限页必须显示"不提供明确状态"',
      );
    });

    test('原生返回 null（旧版/异常）→ 退回 unknown，不默认放行', () async {
      mockWith((_) => true, appListState: null);
      final service = PermissionService();
      await service.checkAllPermissions();
      expect(service.appListPermission, AppListPermission.unknown);
      expect(service.appListGranted, isFalse);
    });

    test('跨端方法名是 getAppListPermissionState，旧的布尔方法已消失', () async {
      mockWith((_) => true, appListState: 'granted');
      await PermissionService().checkAllPermissions();
      expect(calls.map((c) => c.method), contains('getAppListPermissionState'));
      expect(
        calls.map((c) => c.method),
        isNot(contains('isAppListPermissionGranted')),
        reason: '布尔契约把"不知道"压成"已授予"，不得复活',
      );
    });
  });

  group('AppListPermission.fromWire – 未知值一律 unknown', () {
    test('大小写不敏感，垃圾值不放行', () {
      expect(AppListPermission.fromWire('granted'), AppListPermission.granted);
      expect(AppListPermission.fromWire('GRANTED'), AppListPermission.granted);
      expect(AppListPermission.fromWire('denied'), AppListPermission.denied);
      expect(AppListPermission.fromWire(null), AppListPermission.unknown);
      expect(AppListPermission.fromWire(''), AppListPermission.unknown);
      expect(AppListPermission.fromWire('yes'), AppListPermission.unknown);
    });
  });
}
