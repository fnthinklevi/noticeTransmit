import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/widgets/channel_visuals.dart';

/// 「推送通道」那一组入口行的**同一句**摘要（T103，维护者点名的一致的东西）。
///
/// 钉三件读数口径，都不抄文案字面量（措辞会漂）：
/// 1. 0 条 ⇒ 就是「未配置」那一条词条本身；
/// 2. 有 N 条 ⇒ 报出**两个数**（配置数与启用数），且全停用**不等于**「未配置」——
///    库里确实有 N 条，只是都关着，说成"未配置"会把用户的配置抹没；
/// 3. 这一句里不许出现探测/健康度的词 —— 探测结果在每一族的列表页与详情页上，
///    入口行说那种话就会被当成探测结果读。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('一条都没配 ⇒ 「未配置」那一条词条本身（中英文各按各自 locale）', () {
    expect(
      channelFamilySummary(zh, total: 0, enabled: 0),
      zh.channelNotConfigured,
    );
    expect(
      channelFamilySummary(en, total: 0, enabled: 0),
      en.channelNotConfigured,
    );
  });

  test('有 N 条 ⇒ 两个数都在句子里；全停用不等于「未配置」', () {
    final s = channelFamilySummary(zh, total: 3, enabled: 1);
    expect(s, zh.channelConfigured(3, 1));
    expect(s.contains('3'), isTrue, reason: '配置数没出现在屏幕上 ⇒ 那一格白报了');
    expect(s.contains('1'), isTrue, reason: '启用数没出现在屏幕上 ⇒ 同上');
    expect(
      channelFamilySummary(zh, total: 3, enabled: 0),
      isNot(zh.channelNotConfigured),
      reason: '库里三条都关着 ≠ 一条都没配 —— 说成「未配置」是把用户的配置抹没',
    );
  });

  test('这一句只报条数，不替健康度说话', () {
    for (final s in [
      zh.channelNotConfigured,
      channelFamilySummary(zh, total: 5, enabled: 2),
    ]) {
      for (final word in ['连通', '不可达', '探测', '未知']) {
        expect(
          s.contains(word),
          isFalse,
          reason: '入口行混进「$word」就会被读成探测结果，而这一格没有那个证据',
        );
      }
    }
  });
}
