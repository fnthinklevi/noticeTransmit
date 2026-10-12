import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/fnthink_remote_outcome_words.dart';

import '../support/source_guards.dart';

/// T144 片2 格①（维护者 2026-10-12 第 2 条：失败**和成功都要有原因**）。
///
/// 这一张表管的是「本机做成了哪一步」那一列。它今天才第一次有了作者 ——
/// 在那之前成功那一档的 `result` 抄的是 `reason`（而成功时那是 null）⇒ 界面上
/// 状态写着「执行完毕」，两格空白。三条判据各拦一种长坏的方式：
///  ① 双向差集 —— 只加常量不加词条 ⇒ 那一格原样露出机器词；只加词条不加常量 ⇒
///     表里养着一个执行链压根产不出来的词（下个读它的人以为那是个档位）。
///  ② 每一词在中英两种语言里都得是**人话**（不许把词本身抄成"译文" —— 那是假装有翻译）。
///  ③ 消费点守卫 —— 页面不许再直出 `row.result`；runner 不许写裸字面量（词只能来自常量）。
void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  String source(String path) =>
      stripComments(File('${projectRoot()}/$path').readAsStringSync());

  group('这张表自己', () {
    test('封闭清单与词条表双向差集为空（不多不少）', () {
      expect(
        kFnthinkRemoteOutcomeWords.toSet().difference(
          kFnthinkRemoteOutcomeLabels.keys.toSet(),
        ),
        isEmpty,
        reason: '有词没配人话 ⇒ 那一格会原样露出机器词，而"结果"这一列本该是给人读的',
      );
      expect(
        kFnthinkRemoteOutcomeLabels.keys.toSet().difference(
          kFnthinkRemoteOutcomeWords.toSet(),
        ),
        isEmpty,
        reason: '表里留一个执行链产不出的词 ⇒ 下一个人把它当档位接走',
      );
      expect(
        kFnthinkRemoteOutcomeWords,
        hasLength(3),
        reason: '词表鼓起来了要能说清是哪一步加的',
      );
    });

    test('每一词中英都翻成了人话（译文不许就是那个词本身）', () {
      for (final word in kFnthinkRemoteOutcomeWords) {
        for (final l10n in [zh, en]) {
          final text = fnthinkRemoteOutcomeText(l10n, word);
          expect(text, isNotEmpty, reason: '$word 那一格是空的');
          expect(
            hasFnthinkRemoteOutcomeLabel(word),
            isTrue,
            reason: '$word 不在映射里，页面拿到的就是裸词',
          );
          if (l10n == en) {
            expect(
              text,
              isNot(word),
              reason: '$word 的英文"译文"就是它自己 ⇒ 这一列在英文界面等于没翻',
            );
          }
        }
        // 中文那一路按汉字判：词是 ASCII，人话里必须出现非 ASCII 才算真翻了。
        final zhText = fnthinkRemoteOutcomeText(zh, word);
        expect(
          zhText.codeUnits.any((c) => c > 0x7f),
          isTrue,
          reason: '$word 的中文那格还是 ASCII ⇒ 与英文同一判据，别让某一语言单独漏翻',
        );
      }
    });

    test('词表外的读数原样显示（不拿"已完成"盖住一个读不出来的东西）', () {
      expect(
        fnthinkRemoteOutcomeText(zh, 'some-new-code'),
        'some-new-code',
        reason:
            '退化成"已做完"就是把不知道说成知道 —— 与状态那一格 `不认得` 同一条纪律；'
            '回退形状变了 ⇒ 上面那条"没配就露出裸词"的判据也跟着失效',
      );
    });
  });

  group('消费点只认这张表', () {
    test('历史页那一格走查表，不再直出 `row.result`', () {
      final src = source('lib/pages/remote_history_page.dart');
      expect(
        src,
        contains('fnthinkRemoteOutcomeText('),
        reason: '页面绕过这张表自己拼句子 = 第二个词表',
      );
      expect(
        src,
        isNot(contains('remoteHistoryResult(row.result)')),
        reason: '把列里的机器词直接塞进句子 ⇒ 画给用户的是读数而不是人话',
      );
    });

    test('执行链只写常量，不写裸词', () {
      final src = source('lib/services/fnthink_remote_runner.dart');
      for (final word in kFnthinkRemoteOutcomeWords) {
        expect(
          src,
          isNot(contains("'$word'")),
          reason:
              'runner 里出现裸字面量 "$word" ⇒ 词就有了第二个作者：'
              '这一处改了而那张表没改，界面读出来的是一个不存在的档位',
        );
      }
      expect(
        src,
        contains('kFnthinkRemoteOutcomeReported'),
        reason: '成功那一档必须真的写进读数（回到"两格空白"就是本片白做）',
      );
    });
  });
}
