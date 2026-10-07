import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T06：**删除一律二次确认**，而且确认必须写在"执行删除的那个函数"里。
///
/// 为什么不写在调用点：调用点会增加。这一批就是活例子 —— 长按菜单是 T05 新加的，
/// 它复用了卡片上那个"点一下就删"的入口；如果确认写在卡片按钮的 onTap 里，菜单这条
/// 新路径必然静默绕过。咽喉放在执行处，新增入口就只是多一个调用者。
///
/// 同一批还收掉了确认框本身的抄本：`IosDialogActions.confirm` 只给 actions，
/// 于是标题/圆角/按钮顺序在八处各写一遍，措辞还会分叉（电量页两份确认框，一份点名
/// 规则、一份只说"这条规则"）。删除类一律走 [IosDialogActions] 的 `askConfirm`。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  /// 页面 → **会改状态的那几条路径的执行处**。一页多条是正常的（推送页既要换地址码、
  /// 也要答复配对请求），所以这里登记的是清单而不是"每页恰好一个"：
  /// 新增一条路径必须在这里登记，否则第二条的计数断言就会红。
  const chokes = {
    'lib/pages/webhook_channel_list_page.dart': [
      'Future<void> _confirmDeleteChannel(',
    ],
    'lib/pages/app_channel_list_page.dart': [
      'Future<void> _confirmDeleteChannel(',
    ],
    'lib/pages/email_settings_page.dart': ['Future<void> _deleteChannel('],
    'lib/pages/battery_page.dart': [
      'Future<void> _confirmDeleteRule(',
      // T90 片13：这一发的后果是**改系统设置里那一项豁免**（点错了要被系统一直省电），
      // 与删一条规则同级的是「它不可由本页回滚」⇒ 也登记成咽喉，不按「只是个提示框」放过。
      'Future<void> _showBatteryOptimizationDialog(',
    ],
    'lib/pages/temperature_page.dart': ['Future<void> _confirmDeleteRule('],
    'lib/pages/rule_list_page.dart': ['Future<void> _deleteRule('],
    'lib/pages/keywords_page.dart': ['Future<void> _removeKeyword('],
    // T90 片13/#203：历史页这两条都是**一次点下去动一批**的路径。
    // 「批量重推」逐条再发一遍（对面收到 N 发，撤回不了）；「清空全部」是无差别删本机记录。
    // 其余三档（今天 / 最近 10 / 最近 50）不在此列 —— 那一发选档本身就是确认，
    // 唯独「全部」没有回滚可言，所以只有它多问一次。
    'lib/pages/history_page.dart': [
      'Future<void> _runBatchPush(',
      'Future<void> _showClearOptions(',
    ],
    // 幻念推送页：换一枚地址码 = 这台设备在所有对端白名单里那一串当场作废，
    // 后果与删一条通道同级（而更不可逆：对面不会报错，只是再也推不进来）。
    // 第二条是 T42 第五片：同意一条配对请求 = 把一台陌生设备写进本机名单并授一档，
    // 对面从此能往这台设备推正文 —— 契约把这一步定为 `confirmRequired`，不是可省的仪式。
    // 第三条是 T31 B 片：撤销 = 让对面从此推不进来。它比"同意"更需要看一眼：
    // 点错的代价不是本地能回滚的，对面要重新扫码配对才能再推。
    // ⚠ T94：答复一条配对请求与撤销都是「两台设备之间」的事，已搬到绑定页；
    //   它们不能留在旧页面的名单里——那个文件已经没有这几个方法了，
    //   留着只会让管理员以为它们还在那里受保护。
    'lib/pages/fnthink_peers_page.dart': [
      'Future<void> _answer(',
      'Future<void> _revoke(',
    ],
    'lib/pages/fnthink_push_page.dart': ['Future<void> _resetAddressCode('],
    // ⚠ T97 片B：那两下随「接入端点」独立成页走，名单跟着主语迁。
    //   留在旧文件名下就成了"那里还有一道确认闸"的假账 —— 那两个方法在新页里，
    //   旧页只剩一行入口，点下去连网络都不碰。
    'lib/pages/fnthink_endpoint_page.dart': [
      // T42/#157：关掉一把入口 = 关掉一个别人能写进来的门，手滑的代价是 NAS 从此 401
      'Future<void> _revokeEndpoint(',
      // 换口令不留"撤销"那么明显的后果，却更狠：旧那把当场开始倒计时，而 NAS 还在用它
      'Future<void> _rotateEndpoint(',
    ],
    // ⚠ T94 片2：这一下随「接收与远程执行」那张独立页走，名单随主语迁移。
    //   它不在旧名单里——留着会把“页面上不得有第二个点事出口”这一条让它看着像还在。
    // T56 同意门：这一下点下去的后果是**通知内容此后可以经服务器中转**。
    // 它比"换一枚地址码"更需要先看一眼 —— 而"看一眼"在这里必须是一次显式确认，
    // 不是开关被翻开时顺带勾上的。
    'lib/pages/fnthink_receive_page.dart': ['Future<void> _grantConsent('],
    // T94：删一条幻念通道 = 这台不再往它转发。每条方案都按自己的代价去次，
    //   不会提醒「我可以继续跟那台通帙」——那是超出本条的范围（业务意义）。
    'lib/pages/fnthink_channel_list_page.dart': ['Future<void> _delete('],
  };

  group('会改状态的路径只有一个咽喉（T06 + T42 授权那一下）', () {
    test('每条路径的执行处都 askConfirm', () {
      for (final entry in chokes.entries) {
        for (final signature in entry.value) {
          final body = blockAfter(read(entry.key), signature);
          expect(
            body,
            contains('askConfirm('),
            reason: '${entry.key} :: $signature 不再确认 ⇒ 手滑即丢凭据/规则/授权',
          );
          // ⚠ 光有 `askConfirm(` **不够** —— 它可以弹了、拿到 true/false、然后不看结果直接改数据
          // （反证 C2 当场抓到：我把 `_grantConsent` 里那道 `if (!ok …) return;` 摘掉，
          // 这条断言照样全绿）。所以这里钉的是**那个结果本身被否定过**：
          // 先认出结果被存进哪个标识符，再要求块里有一处 `if (!那个标识符`。
          //
          // ⚠⚠ 两次踩过的坑，都记在这里免得第三次：
          //  ① 先写成 `if (!ok` —— 那把**变量名**当成了契约（`_confirmDeleteChannel` 用的是
          //     `confirmed`，当场被判成缺陷）。守卫断行为不断写法。
          //  ② 放宽成 `if (!\w+` —— 那又被块里别处的 `if (!mounted)` 顺手满足（C2 假绿）。
          //     必须是**同一个标识符**，否则这道闸等于没有。
          // ③ T97 片B 反证 F3 抓到的这一处要说清：**块是"签名之后一直到文件末尾"**，不是方法体。
          //    把 `_revokeEndpoint` 那道 `if (!ok …) return;` 摘掉，这一条**照样全绿** ——
          //    因为下面 `_rotateEndpoint` 里还有一句同形的早退替它答了。真正拦住它的是页面用例
          //    「弹层上点取消 ⇒ 那一发不发」（F3b 实测 named+restored）。这本账管"每条路径都弹了、
          //    并按结果早退过"，管不了"哪一条路径的早退被摘掉"——别把这两件事混为一谈。
          final assigned = RegExp(
            r'=\s*await\s+(?:IosDialogActions\.)?askConfirm\(',
          ).firstMatch(body);
          expect(
            assigned,
            isNotNull,
            reason: '${entry.key} :: $signature 连 askConfirm 的结果都没接住',
          );
          final resultVar = RegExp(
            r'final\s+(\w+)\s*=\s*await\s+(?:IosDialogActions\.)?askConfirm\(',
          ).firstMatch(body)?.group(1);
          expect(
            resultVar == null ||
                RegExp(
                  'if\\s*\\(\\s*!\\s*${RegExp.escape(resultVar)}\\b',
                ).hasMatch(body),
            isTrue,
            reason:
                '${entry.key} :: $signature 弹了确认框但没按结果早退 ⇒ '
                '「取消」与「确定」成了同一件事（弹层只是走个过场）',
          );
        }
      }
    });

    test('每个页面的 askConfirm 恰好等于登记的那几条，且不再手搭确认框', () {
      for (final entry in chokes.entries) {
        final rel = entry.key;
        final src = read(rel);
        expect(
          'askConfirm('.allMatches(src).length,
          entry.value.length,
          reason:
              '$rel 的 askConfirm 数量与登记的路径数（${entry.value.length}）不符 ⇒ '
              '要么漏了一条路径，要么又开了一份抄本',
        );
        expect(
          'showDialog<bool>'.allMatches(src).length,
          0,
          reason: '$rel 又自己搭确认框了（形状抄第二份，措辞就会开始分叉）',
        );
      }
    });

    test('真正改掉数据的那一句只出现在咽喉里', () {
      const mutators = {
        'lib/pages/webhook_channel_list_page.dart': ['_service.deleteChannel('],
        'lib/pages/app_channel_list_page.dart': ['_service.deleteChannel('],
        // T08-C2：邮件页不再改本地列表，删除走服务层单条咽喉
        'lib/pages/email_settings_page.dart': ['_emailService.deleteChannel('],
        'lib/pages/battery_page.dart': [
          '_service.deleteRule(',
          // 片13：这一发改的是**系统里那项省电豁免**，同样只许从确认框那一条路出去
          "invokeMethod('requestBatteryOptimization')",
        ],
        'lib/pages/temperature_page.dart': ['_service.deleteRule('],
        'lib/pages/rule_list_page.dart': ['_rules.removeWhere('],
        'lib/pages/keywords_page.dart': ['_blacklist.remove('],
        // #203：只登记「无差别清空」那一句。批量重推走的是 `widget.onPushNow!(record)`，
        // 而这个方法还有一条**单条重推**的入口（历史行上那一下）—— 单条是用户指着一条按的，
        // 不该被二次确认按住，所以它不能登记成「只出现一次」的 mutator，否则那条正常入口当场红。
        'lib/pages/history_page.dart': ['widget.onClear('],
        'lib/pages/fnthink_peers_page.dart': [
          '_coordinator.confirmPairing(',
          '_coordinator.revokePeer(',
        ],
        'lib/pages/fnthink_push_page.dart': ['credentials.resetAddressCode('],
        // T97 片B：那两句随端点那一页走（名单跟着主语迁，旧文件名下留一条就是假账）。
        'lib/pages/fnthink_endpoint_page.dart': [
          '_coordinator.revokeEndpoint(',
          '_coordinator.rotateEndpoint(',
        ],
        'lib/pages/fnthink_receive_page.dart': ['settings.ensureFirstRunHost('],
      };
      for (final entry in mutators.entries) {
        for (final mutator in entry.value) {
          expect(
            mutator.allMatches(read(entry.key)).length,
            1,
            reason: '${entry.key} 里 `$mutator` 出现多次 ⇒ 有第二条绕过确认的改动路径',
          );
        }
      }
    });

    test('详情页离开时释放全部控制器（T07 之后这就是那条保证）', () {
      // T06 时删除发生在详情页内部，所以要在删除的那一刻按 id 前缀释放
      // （`_releaseControllers`）。T07 把删除挪到列表页、详情页只握一条通道，
      // 于是"整页控制器随页面 dispose"就是完备的了 —— 钉这一条而不是留一个空壳函数。
      for (final rel in const [
        'lib/pages/app_channel_settings_page.dart',
        'lib/pages/webhook_settings_page.dart',
        // T08-C2：邮件编辑器的 controller 建在路由里（不是 State 字段），
        // T06 那轮按 State 字段收口时正好漏掉这一页 —— 每次开合泄漏 9 个。
        'lib/pages/email_settings_page.dart',
      ]) {
        final src = read(rel);
        final body = blockAfter(src, 'void dispose() {');
        // 判据必须**扣掉 super.dispose()**：否则一个只调用父类、什么都不释放的
        // dispose() 也算命中（`contains('.dispose()')` 对它是真的 ⇒ 空壳守卫）。
        final releases = body
            .replaceAll('super.dispose();', '')
            .split('\n')
            .where(
              (l) =>
                  l.contains('.dispose()') ||
                  l.contains('.cancel()') ||
                  l.contains('.removeListener('),
            )
            .toList();
        expect(
          releases,
          isNotEmpty,
          reason: '$rel 的 dispose() 只剩 super.dispose() ⇒ 输入框控制器/订阅随页面泄漏',
        );
        expect(
          src,
          isNot(contains('_releaseControllers')),
          reason: '按 id 前缀释放的补丁已经跟着"详情页删通道"一起退场，别再留第二份',
        );
      }
    });

    test('删通道连带清健康记录（徽标不能靠 id 复用复活）', () {
      for (final entry in {
        'lib/pages/webhook_channel_list_page.dart': 'webhook',
        'lib/pages/app_channel_list_page.dart': 'app',
        'lib/pages/email_settings_page.dart': 'email',
      }.entries) {
        final body = blockAfter(read(entry.key), chokes[entry.key]!.single);
        expect(
          body,
          contains("_health.remove('${entry.value}'"),
          reason: '${entry.key} 的删除没清健康缓存：id 复用（从旧备份恢复）时徽标会复活',
        );
      }
    });
  });

  group('确认框本体的风格（T90 片3：删除确认换成 Cupertino 那一件）', () {
    test(
      'askConfirm 用的是 Cupertino 那一件（showCupertinoDialog + CupertinoAlertDialog）',
      () {
        final helper = read('lib/widgets/ios_dialog_actions.dart');
        // 切片而不是 blockAfter：参数表里那个 `{`（命名参数）会先被配对上，
        // 用花括号计数取块只会取到参数表结尾 —— 那不是我们要断的那一段。
        final start = helper.indexOf('static Future<bool> askConfirm(');
        final end = helper.indexOf('static List<Widget> confirm(', start);
        expect(
          start,
          greaterThanOrEqualTo(0),
          reason: 'askConfirm 不在了 ⇒ 本条在空转',
        );
        expect(end, greaterThan(start), reason: '下一个方法没找到，切片边界不成立');
        final ask = helper.substring(start, end);
        expect(
          ask,
          contains('showCupertinoDialog'),
          reason: '确认框没走 Cupertino 那条路 ⇒ 与根组件（CupertinoApp）两套外观',
        );
        expect(
          ask,
          contains('CupertinoAlertDialog('),
          reason: '上面那条只看调用名，这里兜住本体：两件可以名字对、本体错',
        );
      },
    );

    test('这份文件里不再长着一枚 Material AlertDialog（台账已把它划掉）', () {
      final helper = read('lib/widgets/ios_dialog_actions.dart');
      expect(
        RegExp(r'(^|[^A-Za-z0-9_])AlertDialog\(').hasMatch(helper),
        isFalse,
        reason:
            '又长出一枚 Material `AlertDialog` ⇒ 台账（ui_style_guards）里那一格本该已经划掉；'
            '两条路并存时"删除要确认"这件事会跟着外观一起分叉',
      );
    });

    test('发版闸门认得 Cupertino 弹窗（"有没有模态盖着"不许漏这一类）', () {
      final gate = stripComments(
        File(
          '$root/integration_test/release_walkthrough_test.dart',
        ).readAsStringSync(),
      );
      final start = gate.indexOf('bool _modalUp(');
      expect(start, greaterThanOrEqualTo(0), reason: '闸门里的模态判据不见了 ⇒ 本条在空转');
      final end = gate.indexOf(';', start);
      expect(
        gate.substring(start, end),
        contains('CupertinoAlertDialog'),
        reason:
            '`CupertinoAlertDialog` 走 `DialogRoute`、不是 `Dialog` 的子类，`byType` 又是精确匹配 ⇒ '
            '不补这一类，闸门会在确认框还开着的时候答"没有模态"，下一节就在弹层底下找控件'
            '（第 16、17 轮多节连红的共同根因）',
      );
    });
  });
}
