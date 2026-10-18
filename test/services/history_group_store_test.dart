import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/history_group_store.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// T147②：组映射只住在 Dart prefs（零迁移）。这里钉的是**存/读的形状**，
/// 以及「同一成员换组要从旧组移走」—— 延迟队列改点重排会走到那一格。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Map<String, dynamic> member(String id) => <String, dynamic>{
    'id': id,
    'appName': '应用A',
    'title': '标题 $id',
    'postTime': 111,
  };

  test('merge 组：时间从 id 读，成员去重、按顺序保留', () async {
    final store = HistoryGroupStore();
    await store.noteMember(
      groupId: 'com.a:merge:1500',
      kind: 'merge',
      record: member('n1'),
    );
    await store.noteMember(
      groupId: 'com.a:merge:1500',
      kind: 'merge',
      record: member('n2'),
    );
    await store.noteMember(
      groupId: 'com.a:merge:1500',
      kind: 'merge',
      record: member('n1'),
    );
    final groups = await store.list();
    expect(groups, hasLength(1));
    expect(groups.single.id, 'com.a:merge:1500');
    expect(groups.single.kind, 'merge');
    expect(groups.single.at, 1500);
    expect(groups.single.memberIds, ['n1', 'n2']);
  });

  test('同一成员换组（延迟改点重排）⇒ 从旧组移走', () async {
    final store = HistoryGroupStore();
    await store.noteMember(
      groupId: 'delay:1000',
      kind: 'delay',
      record: member('n1'),
    );
    await store.noteMember(
      groupId: 'delay:2000',
      kind: 'delay',
      record: member('n1'),
    );
    final groups = await store.list();
    expect(groups, hasLength(2));
    final at1000 = groups.firstWhere((g) => g.id == 'delay:1000');
    final at2000 = groups.firstWhere((g) => g.id == 'delay:2000');
    expect(at1000.memberIds, isEmpty);
    expect(at2000.memberIds, ['n1']);
  });

  test('认不出的 kind / 空 id 不记；组时间解析认两种 id', () async {
    final store = HistoryGroupStore();
    await store.noteMember(groupId: '', kind: 'merge', record: member('n1'));
    await store.noteMember(
      groupId: 'g:merge:1',
      kind: 'unknown',
      record: member('n1'),
    );
    expect(await store.list(), isEmpty);
    expect(HistoryGroupStore.groupTime('com.a:merge:123'), 123);
    expect(HistoryGroupStore.groupTime('com.a|张三:merge:456'), 456);
    expect(HistoryGroupStore.groupTime('delay:789'), 789);
    expect(HistoryGroupStore.groupTime('nope'), isNull);
  });

  test('坏 JSON ⇒ 按没有组行处理，不抛', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      HistoryGroupStore.prefsKey: '{not json',
    });
    expect(await HistoryGroupStore().list(), isEmpty);
  });

  test('组按时间倒序；超过 maxGroups 时裁最旧', () async {
    final store = HistoryGroupStore();
    for (var i = 1; i <= HistoryGroupStore.maxGroups + 1; i++) {
      await store.noteMember(
        groupId: 'delay:${i * 1000}',
        kind: 'delay',
        record: member('n$i'),
      );
    }
    final groups = await store.list();
    expect(groups, hasLength(HistoryGroupStore.maxGroups));
    expect(groups.first.at, greaterThan(groups.last.at));
    expect(groups.any((g) => g.id == 'delay:1000'), isFalse);
  });

  test('存进去的形状是 JSON 列表（不是某一条的私有格式）', () async {
    await HistoryGroupStore().noteMember(
      groupId: 'delay:42',
      kind: 'delay',
      record: member('n1'),
    );
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(prefs.getString(HistoryGroupStore.prefsKey)!);
    expect(decoded, isA<List>());
    expect((decoded as List).single, containsPair('id', 'delay:42'));
  });

  test('广播里带组字段的那一条，addRecord 会记映射（接线本身可观察）', () async {
    final service = NotificationService();
    try {
      service.addRecord(<String, dynamic>{
        'id': 'n1',
        'title': '标题',
        'content': '正文',
        'packageName': 'com.a',
        'appName': '应用A',
        'postTime': 1000,
        'time': '2026-10-18 12:00',
        'type': 'normal',
        'historyGroupId': 'com.a:merge:1500',
        'historyGroupKind': 'merge',
      });
    } catch (_) {
      // addRecord 的通道快照在纯单测里可能缺依赖；映射写在它之前，照查。
    }
    await Future<void>.delayed(Duration.zero);
    final groups = await HistoryGroupStore().list();
    expect(
      groups.single.memberIds,
      contains('n1'),
      reason: 'addRecord 没把广播里的 historyGroupId 交给组映射 ⇒ 组行永远不出现',
    );
  });
}
