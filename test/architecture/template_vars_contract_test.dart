import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/template_variables.dart';

import '../support/source_guards.dart';

/// 模板变量名单的跨语言契约（T08-A）。
///
/// 为什么要有这条：变量的**替换发生在原生**（webhook/应用走 `TemplateEngine.render`，
/// 邮件走 `EmailSender.applyTemplate`，两张表内容不同），而界面上的"可用变量"提示与
/// 快捷插入按钮此前是 Dart / ARB 里手抄的第三、第四份。手抄必然漂移，而且两个方向都坏：
///  * 原生有、界面没有 ⇒ 用户不知道能用（实测 `%count% %titles% %postTime%` 从未出现在界面）；
///  * 界面有、原生没有 ⇒ 插进去原样留在正文里，用户以为"设置了却没生效"。
/// 所以：名单在 Dart 侧只留 `lib/services/template_variables.dart` 一份，
/// 由本守卫逐 token 与原生两张表**双向**核对（与 `channel_identity_contract_test`
/// 跨语言核对数字表同一手法）。
void main() {
  final root = projectRoot();

  String readKotlin(String rel) => stripComments(
    File(
      '$root/android/app/src/main/kotlin/com/fnthink/notice/$rel',
    ).readAsStringSync(),
  );

  /// 取 `start` 之后到第一个匹配 [endAt] 的位置之前那段源码。
  /// ⚠ 终点用**正则**而不是定长字符串：锚点一旦写死可见性修饰符或"恰好两个换行"，
  ///   加个 `internal` 就找不到终点（T09-A2 撞过）。4 空格缩进可以放心写死，ktlint 挡着。
  /// ⚠ 这里不能 expect：调用点在测试体外，expect 会抛 `OutsideTestException`。
  String slice(String src, String start, RegExp endAt, String what) {
    final a = src.indexOf(start);
    if (a < 0) {
      throw StateError('原生里找不到 $what 的起点「$start」（函数改名/挪动 ⇒ 本守卫要同步）');
    }
    final head = src.substring(a + start.length);
    final b = endAt.firstMatch(head)?.start;
    if (b == null) {
      throw StateError('原生里找不到 $what 的终点「${endAt.pattern}」（函数结构变了 ⇒ 本守卫要同步）');
    }
    return head.substring(0, b);
  }

  String engine() => readKotlin('TemplateEngine.kt');
  String sender() => readKotlin('EmailSender.kt');

  /// ⚠ 三段抽取都放在**惰性函数**里：`slice` 找不到锚点会抛 StateError，而在 `main()`
  ///   顶层求值 = 整个文件加载失败，CI 里表现为"这个文件没有用例"而不是红（本仓库撞过三次）。
  Set<String> nativeWebhookVars() => RegExp(r'put\("([A-Za-z]+)"')
      .allMatches(
        slice(
          engine(),
          'fun render(',
          RegExp('\n    \\}'),
          'TemplateEngine.render',
        ),
      )
      .map((m) => m.group(1)!)
      .toSet();
  Set<String> nativeEmailVars() => RegExp(r'\.replace\("%([A-Za-z]+)%"')
      .allMatches(
        slice(
          sender(),
          'fun applyTemplate(', // 不写可见性：T09-A2 把它从 private 开成 internal 测试缝，锚点不该关心
          RegExp('fun buildSubject\\('), // 同上：不写可见性
          'EmailSender.applyTemplate',
        ),
      )
      .map((m) => m.group(1)!)
      .toSet();

  group('模板变量名单只有一份，且与原生两张表一致', () {
    test('webhook/应用：Dart 名单 == TemplateEngine.render 实际替换的键', () {
      final native = nativeWebhookVars();
      expect(
        native,
        isNotEmpty,
        reason: '正则一枚 token 都没抓到 ⇒ 断言退化成「Dart ⊆ 空集」，守卫已经没了',
      );
      final dart = webhookTemplateVars.map((v) => v.token).toSet();
      expect(
        dart.difference(native),
        isEmpty,
        reason: 'Dart 列了原生不替换的变量 ⇒ 插进去原样留在正文里',
      );
      expect(
        native.difference(dart),
        isEmpty,
        reason: '原生新增/改名了变量而 Dart 名单没跟上 ⇒ 界面上永远看不见它',
      );
      expect(
        webhookTemplateVars.map((v) => v.token).toList(),
        equals(webhookTemplateVars.map((v) => v.token).toSet().toList()),
        reason: '名单里不许有重复 token（提示行会显示两遍）',
      );
    });

    test('邮件：Dart 名单 == EmailSender.applyTemplate 实际替换的键', () {
      final native = nativeEmailVars();
      expect(native, isNotEmpty, reason: '一枚邮件变量都没抓到 ⇒ 上面两条双向核对会同时失去保护');
      final dart = emailTemplateVars.map((v) => v.token).toSet();
      expect(
        dart.difference(native),
        isEmpty,
        reason: '邮件侧原生不替换这些变量（%notifyType% 之类只在 webhook 侧有）',
      );
      expect(
        native.difference(dart),
        isEmpty,
        reason: 'EmailSender 新增/改名了变量而 Dart 名单没跟上',
      );
    });

    test('两族名单确实不同 ⇒ 谁把两份并成一份就会在这里红', () {
      // 这条不是凑数：把 emailTemplateVars 换成 webhookTemplateVars 传进邮件页，
      // 上面两条会同时红 —— 但如果没有这条，后来人可能"顺手统一成一份"。
      expect(
        webhookTemplateVars.map((v) => v.token).toSet(),
        isNot(equals(emailTemplateVars.map((v) => v.token).toSet())),
        reason: '两张原生表本就不同（TemplateEngine vs EmailSender），合并等于骗守卫',
      );
    });

    test('预置模板里用到的变量都在名单内', () {
      final preset = slice(
        engine(),
        'fun presetTemplate(',
        // 终点标记必须选**剥注释后仍然存在**的东西（`stripComments` 会连 KDoc 一起删掉，
        // 拿 '/**' 当终点会在清洗过的源码上永远找不到）。下一个函数声明是稳妥锚点。
        RegExp('\n    (?:private |internal |public |suspend )*fun '),
        'TemplateEngine.presetTemplate',
      );
      final used = RegExp(
        '%([A-Za-z]+)%',
      ).allMatches(preset).map((m) => m.group(1)!).toSet();
      expect(used, isNotEmpty, reason: '一段 %var% 都没抓到 ⇒ 抽取多半已经落空，这条断言也就永远为真');
      expect(
        used.difference(webhookTemplateVars.map((v) => v.token).toSet()),
        isEmpty,
        reason: '预置模板用了名单外的变量 ⇒ 发出去就是未替换的字面量',
      );
    });

    test('界面上不再手抄变量清单', () {
      // 唯一合法的写法是从 template_variables.dart 取名单；页面里再出现"空格分隔的
      // 变量清单"就说明第二份清单又长回来了。
      for (final rel in const [
        'lib/pages/webhook_settings_item.dart',
        'lib/pages/email_settings_page.dart',
      ]) {
        final src = stripComments(File('$root/$rel').readAsStringSync());
        // 判据取"枚举形状"而不是"出现过某个 token"：预置模板与示例提示里合法地嵌着
        // %title% 这类占位符（'应用：%appName%\n标题：%title%…'），而手抄清单的形状是
        // **空格相连的一串**（旧提示行就是 '%appName% %title% %content% …'）。
        expect(
          RegExp(r'%\w+% %\w+% %\w+%').hasMatch(src),
          isFalse,
          reason: '$rel 又出现"空格分隔的变量清单"：名单只允许在 template_variables.dart 里',
        );
        expect(
          src,
          anyOf(contains('templateVarTokens'), contains('commonTemplateVars')),
          reason: '$rel 必须经 template_variables.dart 拿名单',
        );
      }
      // ARB 里的「可用变量」文案只留前缀，不重复列清单
      for (final lang in const ['zh', 'en']) {
        final arb = File('$root/lib/l10n/arb/app_$lang.arb').readAsStringSync();
        final line = arb
            .split('\n')
            .firstWhere((l) => l.trim().startsWith('"availableVars":'));
        expect(
          line,
          isNot(contains('%')),
          reason: 'availableVars 又变成硬编码清单：应只留前缀 + {vars} 占位',
        );
      }
    });
  });
}
