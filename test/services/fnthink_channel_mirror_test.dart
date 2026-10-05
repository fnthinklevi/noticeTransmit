import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/services/fnthink_channel_mirror.dart';
import 'package:notice_transmit/services/fnthink_fanout_entrypoint.dart';

/// T94 片4：跨端镜像与后台排队的**跨语言契约**。
///
/// 这一族坏起来全是静默的：镜像写坏 ⇒ 原生读到空表 ⇒ 不转；解析写坏 ⇒ 那一轮空跑。
/// 两边各改一侧不会有任何编译期报错，所以把字段名与取值都钉在这里，
/// 再由 `FnthinkFanoutQueueTest`（原生侧）钉另一半 —— 同一串出现在两个文件里才算数。
void main() {
  FnthinkChannel ch({
    String id = 'c1',
    String name = '通道',
    String target = 'ABCDEFGH12345678',
    FnthinkChannelTarget kind = FnthinkChannelTarget.device,
    bool enabled = true,
    String role = 'primary',
  }) {
    return FnthinkChannel(
      id: id,
      name: name,
      target: target,
      targetKind: kind,
      enabled: enabled,
      role: role,
      createdAt: 1,
      updatedAt: 1,
    );
  }

  List<Map<String, Object?>> decode(String raw) =>
      (jsonDecode(raw) as List).cast<Map<String, Object?>>();

  group('镜像正文', () {
    test('只放启用中的通道', () {
      final rows = decode(
        encodeFnthinkChannelMirror([ch(id: 'a'), ch(id: 'b', enabled: false)]),
      );
      expect(rows.map((r) => r['id']), ['a']);
    });

    test('字段名与原生那一侧同形（跨语言字符串契约）', () {
      final row = decode(encodeFnthinkChannelMirror([ch()])).single;
      expect(
        row.keys.toSet(),
        {'id', 'name', 'target_kind', 'target', 'role'},
        reason: '原生 ConfigManager.getFnthinkChannelConfigs 按这五个名字读',
      );
      expect(row['target_kind'], 'device');
    });

    test('webhook 目标那一列落的是 webhook', () {
      final row = decode(
        encodeFnthinkChannelMirror([
          ch(
            kind: FnthinkChannelTarget.webhook,
            target: 'https://example.com/hook',
          ),
        ]),
      ).single;
      expect(row['target_kind'], 'webhook');
    });

    test('角色归一后落盘（认不出的词不许原样过去）', () {
      final row = decode(
        encodeFnthinkChannelMirror([ch(role: 'TERTIARY')]),
      ).single;
      expect(row['role'], 'primary');
      expect(
        decode(encodeFnthinkChannelMirror([ch(role: 'Backup')])).single['role'],
        'backup',
      );
    });

    test('一条都没有 ⇒ 空数组而不是 null', () {
      expect(encodeFnthinkChannelMirror(const []), '[]');
      expect(encodeFnthinkChannelMirror([ch(enabled: false)]), '[]');
    });

    test('正文里不得出现停用的通道（原生那一侧已经滤过，别让它有机会看到）', () {
      final raw = encodeFnthinkChannelMirror([
        ch(id: 'keep'),
        ch(id: 'drop', enabled: false),
      ]);
      expect(raw.contains('drop'), isFalse);
    });
  });

  group('待发批次解析（原生队列那一侧的形状）', () {
    test('一条待发项交出全部目标地址码', () {
      final items = parseFanoutBatch(
        jsonEncode([
          {
            'id': 'n1',
            'title': '标题',
            'content': '正文',
            'appName': '应用',
            'targets': [
              {'channel_id': 'c1', 'target_kind': 'device', 'target': 'AAA'},
              {'channel_id': 'c2', 'target_kind': 'device', 'target': 'BBB'},
            ],
          },
        ]),
      );
      expect(items, hasLength(1));
      expect(items.single.id, 'n1');
      expect(items.single.title, '标题');
      expect(items.single.text, '正文');
      expect(items.single.targets, ['AAA', 'BBB']);
    });

    test('坏 JSON / 不是数组 ⇒ 空（不抛）', () {
      expect(parseFanoutBatch('not json'), isEmpty);
      expect(parseFanoutBatch('{"a":1}'), isEmpty);
      expect(parseFanoutBatch('[]'), isEmpty);
    });

    test('一条读不懂的项被跳过，其余照发', () {
      final items = parseFanoutBatch(
        jsonEncode([
          '字符串',
          {'id': 'no-targets'},
          {
            'id': 'ok',
            'targets': [
              {'target': ''},
              {'target': '   '},
              {'target': 'GOOD'},
            ],
          },
        ]),
      );
      expect(items.map((i) => i.id), ['ok']);
      expect(items.single.targets, ['GOOD']);
    });

    test('缺字段不炸（原生那一侧可能换版本）', () {
      final items = parseFanoutBatch(
        jsonEncode([
          {
            'targets': ['不是对象'],
          },
          {
            'targets': [null],
          },
          {
            'id': 1,
            'title': null,
            'content': 5,
            'targets': [
              {'target': 'X'},
            ],
          },
        ]),
      );
      expect(items.single.id, '1');
      // 缺字段落空串而不是 "null"：后台那一轮随后拿它当标题/正文用，
      // 落 "null" 的话对方会收到一条正文写着 null 的通知。
      expect(items.single.title, isEmpty);
      expect(items.single.text, '5');
      expect(items.single.appName, isEmpty);
    });

    test('待发键名与原生那一侧同形（原生写 flutter. 前缀，Dart 读去掉前缀的）', () {
      expect(kFnthinkFanoutPendingKey, 'fnthink_fanout_pending');
      expect(kFnthinkFanoutHandleKey, 'fnthink_fanout_handle');
      expect(
        kFnthinkFanoutChannel,
        'com.fnthink.notice/fanout',
        reason: '与 FnthinkFanoutWorker.FANOUT_CHANNEL 同串；不同串 = fanoutDone 送不出去',
      );
    });
  });
}
