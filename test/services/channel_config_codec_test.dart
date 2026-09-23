import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/channel_config_codec.dart';

import '../support/source_guards.dart';

/// `ChannelConfigCodec` 的三个方向各自钉住（第 6 步）。
///
/// 这个文件是「同一件事只有一处实现」的证据：抽取前 webhook 与应用通道各写两份
/// 归一化（DB↔UI、UI→原生）+ 两份 `'null'` 脏数据清洗，行为靠记忆保持一致。
/// 所以这里既钉**映射结果**，也钉**跨端键集合**（原生读的键我们必须给）。
void main() {
  group('nullableText / flag', () {
    test('历史把 null 写成字符串 "null"，两种都要还原成 null', () {
      expect(ChannelConfigCodec.nullableText('null'), isNull);
      expect(ChannelConfigCodec.nullableText(null), isNull);
      expect(ChannelConfigCodec.nullableText(''), isEmpty);
      expect(ChannelConfigCodec.nullableText('sec'), 'sec');
      // 数字 0 不是脏数据（secret 真的填 "0" 时不能被吞掉）
      expect(ChannelConfigCodec.nullableText(0), '0');
    });

    test('enabled 认 SQLite 的 0/1 也认 JSON 的 bool', () {
      expect(ChannelConfigCodec.flag(1), isTrue);
      expect(ChannelConfigCodec.flag(true), isTrue);
      expect(ChannelConfigCodec.flag(0), isFalse);
      expect(ChannelConfigCodec.flag(false), isFalse);
      expect(ChannelConfigCodec.flag(null), isFalse);
      // ⚠ 字符串 '1' 不算：DB 布尔列不会以字符串回来，放宽会让脏数据混进 UI
      expect(ChannelConfigCodec.flag('1'), isFalse);
    });
  });

  group('webhook：UI ↔ DB ↔ 原生', () {
    test('DB 行 → UI：snake 变 camel、保留 type 别名、脏数据过滤', () {
      final ui = ChannelConfigCodec.webhookFromDb({
        'id': 'wh_1',
        'name': '企微',
        'url': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=k',
        'channel_type': 'wechat_work',
        'enabled': 1,
        'secret': 'null',
        'message_format': 'markdown',
        'message_template': 'null',
        // 老库里仍存着 v9 时代的扩展配置值：读取端必须**安静忽略**它（roadmap D4 / ㊷），
        // 而不是解码成 UI 键、也不是抛异常。
        'extra_config': '{"corpid":"corp"}',
      });
      expect(ui['channelType'], 'wechat_work');
      expect(ui['type'], 'wechat_work', reason: '送达回传与通知服务按 type 取，别名必须留');
      expect(ui['enabled'], isTrue);
      expect(ui['secret'], isNull, reason: '"null" 未洗掉就会被当成已配置密钥');
      expect(ui['message_template'], isNull);
      expect(
        ui.containsKey('extra_config'),
        isFalse,
        reason: 'extra_config 全链路无人消费，不再进 UI（㊷）',
      );
    });

    test('DB 行 channel_type 为空才按 URL 识别；显式 generic 不被覆盖', () {
      final detected = ChannelConfigCodec.webhookFromDb({
        'url': 'https://oapi.dingtalk.com/robot/send',
        'channel_type': '',
      });
      expect(detected['channelType'], 'dingtalk');
      final explicit = ChannelConfigCodec.webhookFromDb({
        'url': 'https://oapi.dingtalk.com/robot/send',
        'channel_type': 'generic',
      });
      expect(
        explicit['channelType'],
        'generic',
        reason: '用户手动选的通用类型被 host 重探测覆盖 = 第 1 步修过的那类缺陷',
      );
    });

    test('UI → DB：列名与 null 脏数据清洗；extra_config 不再写入（㊷）', () {
      final row = ChannelConfigCodec.webhookToDb({
        'id': 'wh_1',
        'name': 'n',
        'url': 'https://h/x',
        'channelType': 'ntfy',
        'enabled': true,
        'secret': 'null',
        'message_format': 'default',
        'message_template': '## %title%',
        'extra_config': {'a': 1},
      });
      expect(row['channel_type'], 'ntfy');
      expect(row['secret'], isNull);
      expect(
        row.containsKey('extra_config'),
        isFalse,
        reason: '写入端已断：列保留但没人写，老值在下一次保存时归 NULL',
      );
      // UI 键仍随行透传（DatabaseHelper 只取它认识的列，多余键忽略）
      expect(row['channelType'], 'ntfy');
    });

    test('UI → 原生：今天等于 UI 形状，形状变更只改这一处', () {
      final ui = {
        'id': 'wh_1',
        'url': 'https://h/x',
        'type': 'generic',
        'channelType': 'generic',
        'enabled': true,
      };
      final native = ChannelConfigCodec.webhookToNative(ui);
      expect(native, equals(ui));
      expect(
        identical(native, ui),
        isFalse,
        reason: '必须是副本：原生长出独立字段时不能改一个 map 就同步改到 UI 列表',
      );
    });

    test('跨端契约：ConfigManager 读 webhook 的每个键，我们都给得出', () {
      final produced = ChannelConfigCodec.webhookToNative({
        'id': 'wh_1',
        'name': 'n',
        'url': 'https://h/x',
        'type': 'generic',
        'channelType': 'generic',
        'enabled': true,
        'secret': 's',
        'message_format': 'default',
        'message_template': '',
      }).keys.toSet();
      final read = nativeReadKeys('getWebhookChannelConfigs');
      expect(
        read,
        // 原生对 type 保留了历史列名兜底（optString("type", optString("channel_type", …))），
        // 主键名给了即可，别名不必再发。
        subsetOf(produced, aliases: {'channel_type'}),
        reason: '原生读得到而 Dart 不发的键 → 后台推送取空值，且「测试」按钮查不出（㉑ 同族）',
      );
      // 反向钉住 ㊷：extra_config 的解析已从原生侧删掉。将来若有人重新 optJSONObject 它，
      // 这条会红 —— 那时要么把链路接通（给用途），要么别加（roadmap D4 选的是删）。
      expect(
        read,
        isNot(contains('extra_config')),
        reason: 'extra_config 已按 D4=B 退出跨端契约',
      );
    });
  });

  group('自建应用通道：UI ↔ DB ↔ 原生', () {
    test('DB 行 → UI：app_type/base_url 变 appType/baseUrl，config 解成 Map', () {
      final ui = ChannelConfigCodec.appFromDb({
        'id': 'app_1',
        'name': '企微应用',
        'app_type': 'wecom_app',
        'base_url': 'https://qyapi.weixin.qq.com',
        'enabled': 1,
        'secret': 'null',
        'config': '{"corpid":"corp-x","agentid":1000002}',
        'message_format': 'default',
      });
      expect(ui['appType'], 'wecom_app');
      expect(ui['baseUrl'], 'https://qyapi.weixin.qq.com');
      expect(ui['enabled'], isTrue);
      expect(ui['secret'], isNull);
      expect((ui['config'] as Map)['corpid'], 'corp-x');
    });

    test('config 坏 JSON 退成空 Map，不抛（抛在加载链上会连带整表读不出）', () {
      expect(
        (ChannelConfigCodec.appFromDb({'config': '{oops'})['config'] as Map),
        isEmpty,
      );
      expect(
        (ChannelConfigCodec.appFromDb({'config': 'null'})['config'] as Map),
        isEmpty,
      );
    });

    test('UI → DB：config 统一成 Map（序列化交给 DatabaseHelper），secret 洗脏数据', () {
      final row = ChannelConfigCodec.appToDb({
        'id': 'app_1',
        'name': 'n',
        'appType': 'feishu_app',
        'baseUrl': '',
        'secret': 'null',
        'config': '{"app_id":"cli-1"}',
        'enabled': true,
      });
      expect(row['appType'], 'feishu_app');
      expect(row['baseUrl'], '');
      expect(row['secret'], isNull);
      expect((row['config'] as Map)['app_id'], 'cli-1');
      expect(row['message_format'], 'default', reason: '缺省要补齐，否则原生读到 null');
    });

    test('UI → 原生：必须是 type/base_url，UI 键不得漏进载荷', () {
      final native = ChannelConfigCodec.appToNative({
        'id': 'app_1',
        'name': 'n',
        'appType': 'wecom_app',
        'baseUrl': 'https://qyapi.weixin.qq.com',
        'secret': 's',
        'config': <String, dynamic>{},
        'message_format': 'default',
        'enabled': true,
      });
      expect(native['type'], 'wecom_app');
      expect(native['base_url'], 'https://qyapi.weixin.qq.com');
      expect(native.containsKey('appType'), isFalse);
      expect(native.containsKey('baseUrl'), isFalse);
    });

    test('跨端契约：ConfigManager 读 app 通道的每个键，我们都给得出', () {
      final produced = ChannelConfigCodec.appToNative({
        'id': 'app_1',
        'name': 'n',
        'appType': 'wecom_app',
        'baseUrl': 'https://qyapi.weixin.qq.com',
        'secret': 's',
        'config': <String, dynamic>{},
        'message_format': 'default',
        'enabled': true,
      }).keys.toSet();
      expect(
        nativeReadKeys('getAppChannelConfigs'),
        subsetOf(produced, aliases: {'url'}),
        reason: '原生读得到而 Dart 不发的键 → 推送静默失败',
      );
    });
  });
}

/// 解析 `ConfigManager.<fn>` 函数体里读到的键名（optString/optBoolean/… 的第一参数）。
Set<String> nativeReadKeys(String functionName) {
  final kotlin = stripComments(
    File(
      '${projectRoot()}/android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt',
    ).readAsStringSync(),
  );
  final start = kotlin.indexOf('fun $functionName(');
  expect(start, greaterThanOrEqualTo(0), reason: '原生读取函数改名了，需同步本用例');
  final next = kotlin.indexOf('\n    fun ', start + 1);
  final block = kotlin.substring(start, next < 0 ? kotlin.length : next);
  final read = RegExp(
    r'opt(?:String|Boolean|Int|Long|Double|JSONObject|JSONArray)\(\s*"([A-Za-z_][A-Za-z0-9_]*)"',
  ).allMatches(block).map((m) => m.group(1)!).toSet();
  expect(read, isNotEmpty, reason: '未解析到任何读取键 —— 本用例已失效');
  return read;
}

/// 断言 [actual] ⊆ 期望键集合 ∪ [aliases]，并反向检查别名确实还被原生读着
/// （别名一旦从原生代码消失，豁免就该删掉，否则豁免本身变成死角）。
/// 用法：`expect(nativeReadKeys(f), subsetOf(produced, aliases: {...}))`
Matcher subsetOf(Set<String> produced, {Set<String> aliases = const {}}) =>
    _SubsetOf(produced, aliases);

class _SubsetOf extends Matcher {
  _SubsetOf(this.produced, this.aliases);

  final Set<String> produced;
  final Set<String> aliases;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    final read = (item! as Set<String>);
    final missing = read.difference(produced).difference(aliases);
    matchState['missing'] = missing;
    // 别名必须确实出现在原生读取里，否则豁免是死条款
    final deadAliasExemption = aliases.difference(read);
    matchState['dead'] = deadAliasExemption;
    return missing.isEmpty && deadAliasExemption.isEmpty;
  }

  @override
  Description describe(Description description) =>
      description.add('原生读取的键都能被 Dart 载荷提供（或走原生别名兜底 $aliases）');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    final missing = matchState['missing'] as Set<String>;
    final dead = matchState['dead'] as Set<String>;
    if (missing.isNotEmpty) {
      mismatchDescription.add('Dart 载荷缺键 $missing（原生会读到空值）');
    }
    if (dead.isNotEmpty) {
      mismatchDescription.add('这些别名键原生已不再读，请删除豁免：$dead');
    }
    return mismatchDescription;
  }
}
