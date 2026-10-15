import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T153 片1：远程触发筛选页「派生而不复用」的静态守卫。
///
/// 背景（维护者 2026-10-15 拍板 Q1=b）：远程执行设置页的「可触发的应用」原先直接复用
/// `AppFilterPage`，于是用户点进去读到的是「通知应用 / 不通知应用 · 这些应用的通知会被推送」
/// —— 整页在说通知转发，而真实语义是「哪些应用的通知正文能触发本机远程指令」。
/// 修法是**派生一枚专用页**，`AppFilterPage` 一个字节不动。
///
/// 派生这条路自己有两个失败形状，静态那半都在这儿钉：
///  ① **派生页又复用回 `AppFilterPage`**：传参数绕过文案判据，屏上看起来一切正常
///     （因为参数恰好让文案变了对）—— 那是把"改通知文案顺手改掉触发文案"的风险原样复活；
///  ② **顺手改 `AppFilterPage`**：把那一页的文案也改成触发语义 ⇒ 通知筛选项自己说错话。
///     通知筛选是**另一个功能**（`main_page_actions._openAppFilterPage`），它的文案本就该说通知。
///
/// 运行期那半（五处文案在屏上确实是触发语义）在
/// `test/widgets/remote_trigger_filter_page_test.dart`。
void main() {
  final root = projectRoot();

  String src(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  final derived = src('lib/pages/remote_trigger_filter_page.dart');
  final original = src('lib/pages/app_filter_page.dart');
  final caller = src('lib/pages/remote_credential_settings_page.dart');

  test('① 派生页不复用回 AppFilterPage（派生而不是传参绕过）', () {
    expect(
      derived,
      isNot(contains('AppFilterPage')),
      reason:
          '派生页里出现 AppFilterPage ⇒ 它是被传参数复用回去的，'
          '而"改通知文案顺手改掉触发文案"这个风险正是派生要消灭的东西',
    );
  });

  test('② 派生页确实定义了 RemoteTriggerFilterPage（不是空壳转发）', () {
    expect(
      derived,
      contains('class RemoteTriggerFilterPage extends StatefulWidget'),
      reason: '没有这个类 ⇒ 调用方指向的那一页不存在（编译期就会红，这里防的是被删剩空文件）',
    );
    // 它是**有状态**的实现：派生页自带清单加载 / 权限 / 分组，不是 `=> AppFilterPage(...)` 转发
    expect(
      derived,
      contains('class _RemoteTriggerFilterPageState extends State'),
    );
  });

  test('③ 调用方指向派生页，不再指向 AppFilterPage', () {
    expect(caller, contains('RemoteTriggerFilterPage('));
    // 调用方那一行不许还留着 AppFilterPage( —— 那说明改了一半（页面在、没人用）
    expect(
      caller,
      isNot(contains('AppFilterPage(')),
      reason: '调用方仍在建 AppFilterPage ⇒ 新写的那一页没有任何入口，病灶原样存在',
    );
  });

  test('④ AppFilterPage 的通知文案一个都没被改成触发语义', () {
    // 那一页的两枚模式 chip 仍说"通知应用 / 不通知应用"：通知筛选项就该说通知。
    // 判据取 ARB 键名而不是中文串（中文串会被翻译流程改，键名不会）。
    expect(original, contains('filterNotifyApps'));
    expect(original, contains('filterBlockApps'));
    expect(original, contains('appFilterAllowModeInfo'));
    expect(original, contains('appFilterBlockModeInfo'));
    // 反向：那一页不许出现触发语义的新键（出现即说明有人把两套文案并成了一套）
    expect(original, isNot(contains('remoteTriggerAllow')));
    expect(original, isNot(contains('remoteTriggerBlock')));
    expect(original, isNot(contains('remoteTriggerFilterTitle')));
  });

  test('⑤ 派生页的返回契约与 AppFilterPage 逐字相同（换页不换数据形状）', () {
    // 调用方那三行解析读的是 'mode' + 'packages' 两个键；两页必须给出同一套键，
    // 否则"写进去的形状"与"判定读出来的形状"分成两套。
    for (final s in [derived, original]) {
      expect(s, contains("'mode'"));
      expect(s, contains("'packages'"));
    }
  });

  test('⑥ 派生页不复用 enabled_packages 那条数据键（页派生、表也派生）', () {
    // 触发名单写 FnthinkRemoteSettings 自己的三份键（localTriggerFilter），
    // 不碰 enabled_packages —— 那一份的语义是「要转发的应用」。
    // 派生页本身不碰存储（它只回 mode+packages），所以这里断的是"页里不出现那个键名"。
    expect(derived, isNot(contains('enabled_packages')));
    expect(derived, isNot(contains('saveAppFilter')));
  });

  test('⑦ 派生页不用裸 TextButton（不继承原页那一枚的形状）', () {
    // 原页 `:298` 那枚「完成」是裸 TextButton（T153 片6 要清的那一族）。
    // 新写的一页**不继承**它：直接走公共件。
    final raw = RegExp(r'(^|[^A-Za-z0-9_])TextButton\(');
    expect(
      raw.hasMatch(derived),
      isFalse,
      reason: '派生页长出一枚裸 TextButton ⇒ 原页那一枚的形状被继承过来了',
    );
    // 而且那一枚确实在场（走的是公共件）
    expect(derived, contains('FnthinkInlineAction'));
  });

  test('⑧ 派生页的应用清单读取入口与原页同一个服务（缓存/ROM 判据只有一份）', () {
    // 与语义无关的部分（权限链路、缓存、force、分组排序）逐字相同；
    // 凡是要说出"这是什么"的地方才换。这里钉住共用的那一半：
    // T153 片1 顺手把两页各自裸调的三发（canQueryAllPackages /
    // requestQueryAllPackagesPermission）收进 `InstalledAppsService`
    // （widget 层裸 invokeMethod 是只降不升的棘轮，照搬一次就超一次），
    // 所以判据从"方法名字面量"换成"服务上的那两个入口"。
    for (final s in [derived, original]) {
      expect(s, contains('InstalledAppsService'));
      expect(s, contains('canQueryPackages'));
      expect(s, contains('requestQueryAllPackages'));
    }
    // 反向：两页都不该再裸调那三个原生方法名
    for (final s in [derived, original]) {
      expect(s, isNot(contains('canQueryAllPackages')));
      expect(s, isNot(contains('requestQueryAllPackagesPermission')));
      expect(s, isNot(contains("invokeMethod('getInstalledApps'")));
    }
  });
}
