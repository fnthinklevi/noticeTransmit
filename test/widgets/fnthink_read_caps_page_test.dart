import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/fnthink_read_caps_page.dart';
import 'package:notice_transmit/widgets/app_root.dart';

/// 「可被远程读取的内容」那一页（T124 片C）。
///
/// 钉每一行的全部判据（四行同套流程，逐行各断一遍）：
///  ① **默认关**，且关着时**不碰权限框**；
///  ② 翻到开 ⇒ 先弹系统权限框（申请恰好一次）；**答复没回来时不落开**；
///  ③ 给了权限 ⇒ 落开（持久化为 true）；被拒 ⇒ 保持关 + 说明那一句在；
///  ④ 关掉 ⇒ 立即落盘 false（不再弹框）；
///  ⑤ **一条一开**：开一项不许把另一项也落盘（两枚开关各自独立）。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool callsStored = false,
    bool locationStored = false,
    bool cameraStored = false,
    bool contactsStored = false,
    Future<bool> Function()? isCallsGranted,
    Future<bool> Function()? isLocationGranted,
    Future<bool> Function()? isCameraGranted,
    Future<bool> Function()? isContactsGranted,
    List<bool>? savedCalls,
    List<bool>? savedLocation,
    List<bool>? savedCamera,
    List<bool>? savedContacts,
    List<int>? requestedCalls,
    List<int>? requestedLocation,
    List<int>? requestedCamera,
    List<int>? requestedContacts,
  }) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkReadCapsPage(
          loadCalls: () async => callsStored,
          saveCalls: (v) async => savedCalls?.add(v),
          requestCallsPermission: () async => requestedCalls?.add(1),
          isCallsGranted: isCallsGranted ?? () async => false,
          loadLocation: () async => locationStored,
          saveLocation: (v) async => savedLocation?.add(v),
          requestLocationPermission: () async => requestedLocation?.add(1),
          isLocationGranted: isLocationGranted ?? () async => false,
          loadCamera: () async => cameraStored,
          saveCamera: (v) async => savedCamera?.add(v),
          requestCameraPermission: () async => requestedCamera?.add(1),
          isCameraGranted: isCameraGranted ?? () async => false,
          loadContacts: () async => contactsStored,
          saveContacts: (v) async => savedContacts?.add(v),
          requestContactsPermission: () async => requestedContacts?.add(1),
          isContactsGranted: isContactsGranted ?? () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool switchOf(WidgetTester tester, String id) => tester
      .widget<CupertinoSwitch>(find.byKey(ValueKey('fnthink-read-$id-switch')))
      .value;

  testWidgets('四行都在、默认全关；关着时不弹任何权限框', (tester) async {
    final requestedCalls = <int>[];
    final requestedLocation = <int>[];
    final requestedContacts = <int>[];
    await pump(
      tester,
      requestedCalls: requestedCalls,
      requestedLocation: requestedLocation,
      requestedContacts: requestedContacts,
    );
    expect(
      find.byKey(const ValueKey('fnthink-read-calls-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fnthink-read-location-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fnthink-read-camera-switch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fnthink-read-contacts-switch')),
      findsOneWidget,
    );
    expect(switchOf(tester, 'calls'), isFalse, reason: '默认必须是关');
    expect(switchOf(tester, 'location'), isFalse, reason: '默认必须是关');
    expect(switchOf(tester, 'camera'), isFalse, reason: '默认必须是关');
    expect(switchOf(tester, 'contacts'), isFalse, reason: '默认必须是关');
    expect(requestedCalls, isEmpty);
    expect(requestedLocation, isEmpty);
    expect(requestedContacts, isEmpty);
  });

  testWidgets('打开且系统已给过权限 ⇒ 不重复弹框，直接落开', (tester) async {
    final requested = <int>[];
    final saved = <bool>[];
    await pump(
      tester,
      isCallsGranted: () async => true,
      savedCalls: saved,
      requestedCalls: requested,
    );
    await tester.tap(find.byKey(const ValueKey('fnthink-read-calls-switch')));
    await tester.pumpAndSettle();
    expect(requested, isEmpty, reason: '已有权限不重复弹');
    expect(saved, [true]);
    expect(switchOf(tester, 'calls'), isTrue);
  });

  testWidgets('打开但权限没给 ⇒ 申请恰好一次；答复前不落开；答复给了才落开', (tester) async {
    final requested = <int>[];
    final saved = <bool>[];
    var granted = false;
    await pump(
      tester,
      isCallsGranted: () async => granted,
      savedCalls: saved,
      requestedCalls: requested,
    );
    await tester.tap(find.byKey(const ValueKey('fnthink-read-calls-switch')));
    await tester.pumpAndSettle();
    expect(requested.length, 1);
    expect(saved, isEmpty, reason: '答复还没回来，不许先落开');
    expect(switchOf(tester, 'calls'), isFalse, reason: '没给权限就不许画成开');

    // 用户给了权限 ⇒ 从系统框回来（resumed 那一路复核）。
    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(saved, [true]);
    expect(switchOf(tester, 'calls'), isTrue);
  });

  testWidgets('被拒 ⇒ 保持关，并说清"再点一次重试或去系统设置里打开"', (tester) async {
    final saved = <bool>[];
    await pump(tester, savedCalls: saved);
    await tester.tap(find.byKey(const ValueKey('fnthink-read-calls-switch')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FnthinkReadCapsPage)),
    );
    expect(switchOf(tester, 'calls'), isFalse);
    expect(saved, isEmpty);
    expect(
      find.byKey(const ValueKey('fnthink-read-calls-denied')),
      findsOneWidget,
    );
    expect(find.text(l10n.fnthinkReadCallsDenied), findsOneWidget);
  });

  testWidgets('关掉 ⇒ 立即落盘 false，且不再弹权限框', (tester) async {
    final requested = <int>[];
    final saved = <bool>[];
    await pump(
      tester,
      callsStored: true,
      isCallsGranted: () async => true,
      savedCalls: saved,
      requestedCalls: requested,
    );
    expect(switchOf(tester, 'calls'), isTrue, reason: '存的是开就画成开');
    await tester.tap(find.byKey(const ValueKey('fnthink-read-calls-switch')));
    await tester.pumpAndSettle();
    expect(saved, [false]);
    expect(requested, isEmpty);
    expect(switchOf(tester, 'calls'), isFalse);
  });

  testWidgets('位置那一行同套流程：给了权限才落开，且只落位置那一枚', (tester) async {
    final savedCalls = <bool>[];
    final savedLocation = <bool>[];
    final requestedLocation = <int>[];
    var granted = false;
    await pump(
      tester,
      isLocationGranted: () async => granted,
      savedCalls: savedCalls,
      savedLocation: savedLocation,
      requestedLocation: requestedLocation,
    );
    await tester.tap(
      find.byKey(const ValueKey('fnthink-read-location-switch')),
    );
    await tester.pumpAndSettle();
    expect(requestedLocation.length, 1);
    expect(savedLocation, isEmpty, reason: '答复还没回来，不许先落开');
    expect(savedCalls, isEmpty, reason: '一条一开：开位置不许碰通话记录那一枚');

    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(savedLocation, [true]);
    expect(savedCalls, isEmpty);
    expect(switchOf(tester, 'location'), isTrue);
    expect(switchOf(tester, 'calls'), isFalse, reason: '通话记录那枚还该是关的');
  });

  testWidgets('位置被拒 ⇒ 只挂位置那一条说明，不串到通话记录行底下', (tester) async {
    await pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('fnthink-read-location-switch')),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FnthinkReadCapsPage)),
    );
    expect(
      find.byKey(const ValueKey('fnthink-read-location-denied')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fnthink-read-calls-denied')),
      findsNothing,
    );
    expect(find.text(l10n.fnthinkReadLocationDenied), findsOneWidget);
    expect(find.text(l10n.fnthinkReadCallsDenied), findsNothing);
  });

  testWidgets('拍照那一行同套流程：给了权限才落开，且只落相机那一枚', (tester) async {
    final savedCamera = <bool>[];
    final savedCalls = <bool>[];
    final requestedCamera = <int>[];
    var granted = false;
    await pump(
      tester,
      isCameraGranted: () async => granted,
      savedCamera: savedCamera,
      savedCalls: savedCalls,
      requestedCamera: requestedCamera,
    );
    await tester.tap(find.byKey(const ValueKey('fnthink-read-camera-switch')));
    await tester.pumpAndSettle();
    expect(requestedCamera.length, 1);
    expect(savedCamera, isEmpty, reason: '答复还没回来，不许先落开');

    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(savedCamera, [true]);
    expect(savedCalls, isEmpty, reason: '一条一开：开相机不许碰通话记录那一枚');
    expect(switchOf(tester, 'camera'), isTrue);

    // 关掉：立即落盘 false（与另两行同一条）。
    await tester.tap(find.byKey(const ValueKey('fnthink-read-camera-switch')));
    await tester.pumpAndSettle();
    expect(savedCamera, [true, false]);
    expect(switchOf(tester, 'camera'), isFalse);
  });

  testWidgets('通讯录那一行同套流程：给了权限才落开，且只落通讯录那一枚', (tester) async {
    final savedContacts = <bool>[];
    final savedCalls = <bool>[];
    final requestedContacts = <int>[];
    var granted = false;
    await pump(
      tester,
      isContactsGranted: () async => granted,
      savedContacts: savedContacts,
      savedCalls: savedCalls,
      requestedContacts: requestedContacts,
    );
    await tester.tap(
      find.byKey(const ValueKey('fnthink-read-contacts-switch')),
    );
    await tester.pumpAndSettle();
    expect(requestedContacts.length, 1);
    expect(savedContacts, isEmpty, reason: '答复还没回来，不许先落开');
    expect(savedCalls, isEmpty, reason: '一条一开：开通讯录不许碰通话记录那一枚');

    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(savedContacts, [true]);
    expect(savedCalls, isEmpty);
    expect(switchOf(tester, 'contacts'), isTrue);
    expect(switchOf(tester, 'calls'), isFalse, reason: '通话记录那枚还该是关的');

    // 关掉：立即落盘 false（与另三行同一条）。
    await tester.tap(
      find.byKey(const ValueKey('fnthink-read-contacts-switch')),
    );
    await tester.pumpAndSettle();
    expect(savedContacts, [true, false]);
    expect(switchOf(tester, 'contacts'), isFalse);
  });
}
