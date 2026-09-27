import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 通知引擎三族设置页（电量 / 温度 / 设备状态）的版式契约。
///
/// 三条反馈之一是"这三页看着像三个产品"，修法是抽一份共用组件（`widgets/engine_page_sections.dart`）。
/// 只测"某一页有某个标题"守不住这件事 —— 下一次有人图省事在自己的页里再写一份
/// `_buildGroup`，页面照样绿，副本照样长出来。所以这里钉的是**结构**：
/// 1. 三页都用共用的顶部读数与分区组件；
/// 2. 三页都不许再定义自己的那套版式 builder（副本一出现就红）；
/// 3. 顶部读数只走 T17 那一次 `getDeviceSnapshot`，且"读不到"必须明说，不许画 0；
/// 4. 网络枚举的口语名只有一份（快照页与告警页不能各翻译一遍）。
void main() {
  final root = projectRoot();
  String code(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  const pages = [
    'lib/pages/battery_page.dart',
    'lib/pages/temperature_page.dart',
    'lib/pages/device_state_page.dart',
  ];
  // 顶部读数是这次新加的两页（电量页本来就有）
  const readoutPages = [
    'lib/pages/temperature_page.dart',
    'lib/pages/device_state_page.dart',
  ];

  group('三页共用一份版式', () {
    for (final rel in pages) {
      test('$rel 用的是共用组件', () {
        final src = code(rel);
        expect(
          src.contains("import '../widgets/engine_page_sections.dart'"),
          isTrue,
          reason: '没引入共用组件 = 这一页的版式是另一份实现',
        );
        expect(
          src,
          contains('EngineReadoutHeader('),
          reason: '顶部大读数区必须来自共用组件（电量页以前那段 Center+Column 就是它）',
        );
        expect(src, contains('EngineSection('), reason: '分区标题与卡片分组必须来自共用组件');
      });

      test('$rel 不许再长出第二份版式 builder', () {
        final src = code(rel);
        for (final dead in const [
          'Widget _buildSectionHeader(',
          'Widget _buildGroup(',
          'Widget _buildDivider(',
          'Widget _buildSwitchRow(',
          'class _DescRow',
        ]) {
          expect(
            src,
            isNot(contains(dead)),
            reason:
                '「$dead」是抽组件之前各页自己写的版式件；在页里再写一份，'
                '下一次改字号就只会改到一页（这正是这次要修的病）',
          );
        }
      });
    }
  });

  group('顶部读数走快照、读不到要明说', () {
    test('温度页与设备状态页都走 getDeviceSnapshot，不各开一枚原生方法', () {
      for (final rel in readoutPages) {
        final src = code(rel);
        expect(
          src.contains('getDeviceSnapshot()'),
          isTrue,
          reason: '$rel 的实时读数必须来自 T17 那一次调用（逐项单独读会闪、也会长出新的通道方法）',
        );
        expect(
          src,
          isNot(contains('AppChannels.notification.invokeMethod')),
          reason: '页面不碰通道：读数经由 DeviceInfoService，方法总数只降不升（93）',
        );
      }
    });

    test('读不到时显示「这台设备读不到」，不许拿 0 顶上', () {
      for (final rel in readoutPages) {
        expect(
          code(rel).contains('l10n.unreadableField'),
          isTrue,
          reason: '$rel 的读数缺字段时必须明说读不到 —— 0℃/0% 会被当成真实读数',
        );
      }
    });
  });

  group('网络枚举只有一份口语名', () {
    test('快照页与设备状态告警页共用 engineNetworkLabel', () {
      for (final rel in const [
        'lib/pages/device_snapshot_page.dart',
        'lib/pages/device_state_page.dart',
      ]) {
        final src = code(rel);
        expect(
          src.contains('engineNetworkLabel('),
          isTrue,
          reason: '$rel 自己翻译枚举的话，两页就会一个说 VPN 一个说"其他"',
        );
        expect(src, isNot(contains('_networkLabel(')), reason: '私有副本不得复活');
      }
    });
  });

  test('共用组件自己不许反过来依赖页面（防成环）', () {
    final src = code('lib/widgets/engine_page_sections.dart');
    expect(src, isNot(contains("import '../pages/")));
    expect(
      src,
      isNot(contains('AppChannels')),
      reason: '版式组件只排版式：碰通道就会把"页面不裸调通道"那条棘轮绕过去',
    );
  });
}
