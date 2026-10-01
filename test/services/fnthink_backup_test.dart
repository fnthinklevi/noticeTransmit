import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_backup.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';

/// T59：幻念推送那一格「进备份什么、恢复什么、绝不进什么」。
///
/// 判据（维护者 2026-10-01 定）：**备份恢复的是「意图」，不恢复「身份」，也不携带「凭证」**。
/// 所以这一格只有三项：接收总开关、所选服务地址、同意门的版本号。
/// 本文件里最值钱的三条用例是 ①"从没配过的机器不带地址与同意键"、②"版本号不够就不写同意门
/// 并把这句话报出来"、③"契约读不到时按没同意过处理" —— 三条都是 fail-closed 方向；
/// 反过来（默认恢复、默认同意）表现是"用户没点过同意却开始往外发"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
  }

  group('收集', () {
    test('这台从没配过 ⇒ 只带一个 false，不带地址也不带同意版本', () async {
      await seed({});
      final got = await FnthinkBackup().collect();
      expect(got, {FnthinkBackup.fieldReceiveEnabled: false});
      expect(await FnthinkBackup().hasContent(), isFalse);
    });

    test('配过的三项都带出，且不带任何身份/凭证/名单/正文键', () async {
      await seed({
        FnthinkSettings.keyReceiveEnabled: true,
        FnthinkSettings.keyHost: 'push.example.com',
        FnthinkSettings.keyConsentVersion: 1,
      });
      final got = await FnthinkBackup().collect();
      expect(got, {
        FnthinkBackup.fieldReceiveEnabled: true,
        FnthinkBackup.fieldHost: 'push.example.com',
        FnthinkBackup.fieldConsentVersion: 1,
      });
      expect(await FnthinkBackup().hasContent(), isTrue);
      // 白名单的另一半：这一格里不许出现"看起来像凭证/身份/名单/历史"的键。
      final text = jsonEncode(got);
      for (final banned in const [
        'peers',
        'addressCode',
        'publicKey',
        'privateKey',
        'secret',
        'passphrase',
        'title',
        'body',
        'direction',
      ]) {
        expect(
          text.toLowerCase(),
          isNot(contains(banned)),
          reason: '「$banned」进了备份 ⇒ 违背"不恢复身份、不携带凭证"那条判据',
        );
      }
    });
  });

  group('形状兜底（文件是外部输入）', () {
    test('类型不对的一律不写键（保持本机现值）', () {
      final got = FnthinkBackup.normalize(const {
        'receive_enabled': 'yes',
        'consent_version': '1',
      });
      expect(got, isEmpty, reason: '把字符串 "yes" 当成 true 就是替用户开了接收');
    });

    test('非法主机名丢掉，而不是灌进 prefs', () {
      final got = FnthinkBackup.normalize(const {
        FnthinkBackup.fieldHost: 'https://push.example.com/hook',
      });
      expect(
        got,
        isEmpty,
        reason: '带 scheme 的地址一旦落库，收货循环拼出的 authority 一路 400，而没人会怀疑到刚恢复的备份上',
      );
    });

    test('合法值原样过（大小写归一与端口允许都走 FnthinkSettings 那一份校验）', () {
      final got = FnthinkBackup.normalize(const {
        FnthinkBackup.fieldHost: 'Push.Example.COM:8443',
        FnthinkBackup.fieldConsentVersion: 2,
      });
      expect(got[FnthinkBackup.fieldHost], 'push.example.com:8443');
      expect(got[FnthinkBackup.fieldConsentVersion], 2);
    });
  });

  group('落回本机', () {
    test('三项都恢复得回来（往返一致）', () async {
      await seed({});
      final backup = FnthinkBackup(requiredConsentVersion: () => 1);
      final note = await backup.apply(const {
        FnthinkBackup.fieldReceiveEnabled: true,
        FnthinkBackup.fieldHost: 'push.example.com',
        FnthinkBackup.fieldConsentVersion: 1,
      });
      expect(note, isNull, reason: '版本号够 ⇒ 同意门该跟着恢复，别让人再点一次');
      expect(await backup.collect(), {
        FnthinkBackup.fieldReceiveEnabled: true,
        FnthinkBackup.fieldHost: 'push.example.com',
        FnthinkBackup.fieldConsentVersion: 1,
      });
    });

    test('备份记的是旧版政策 ⇒ 不写同意门，并把这句话报出来', () async {
      await seed({});
      final backup = FnthinkBackup(requiredConsentVersion: () => 3);
      final note = await backup.apply(const {
        FnthinkBackup.fieldReceiveEnabled: true,
        FnthinkBackup.fieldConsentVersion: 1,
      });
      expect(note, isNotNull);
      expect(note, contains('同意'), reason: '报告里要能看出"少了哪一项"');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(FnthinkSettings.keyConsentVersion),
        isNull,
        reason: '中转政策改版后必须重新同意 —— 恢复时顺手替用户点是 T56 那条不变量的反面',
      );
      expect(
        prefs.getBool(FnthinkSettings.keyReceiveEnabled),
        isTrue,
        reason: '只有同意门没恢复；总开关那一项该落的还得落（否则一句"没恢复"盖掉全部）',
      );
    });

    test('契约读不到（装配未完成）⇒ 按没同意过处理，而不是"当它同意过"', () async {
      await seed({});
      final backup = FnthinkBackup(); // 没有 GetIt、也没有注入 ⇒ required 为 null
      final note = await backup.apply(const {
        FnthinkBackup.fieldConsentVersion: 1,
      });
      expect(note, isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(FnthinkSettings.keyConsentVersion), isNull);
    });

    test('缺 consent_version 键 ⇒ 不碰本机已有的同意记录（不许抹掉）', () async {
      await seed({FnthinkSettings.keyConsentVersion: 7});
      final backup = FnthinkBackup(requiredConsentVersion: () => 9);
      expect(
        await backup.apply(const {FnthinkBackup.fieldReceiveEnabled: false}),
        isNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(FnthinkSettings.keyConsentVersion), 7);
    });
  });

  group('真契约那一档（默认判据真的读的是包内那份表）', () {
    test('恢复的档位等于契约要求 ⇒ 写；低一档 ⇒ 不写', () async {
      final root = projectRoot();
      final source = File('$root/protocol/fnthink-v1.json').readAsStringSync();
      final loader = FnthinkContractLoader(readAsset: (_) async => source);
      await loader.load();
      final required =
          jsonDecode(source)['privacy']['relayConsentVersion'] as int;
      await seed({});
      final backup = FnthinkBackup(contractLoader: loader);
      expect(
        await backup.apply({FnthinkBackup.fieldConsentVersion: required}),
        isNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(FnthinkSettings.keyConsentVersion), required);

      await seed({});
      expect(
        await backup.apply({FnthinkBackup.fieldConsentVersion: required - 1}),
        isNotNull,
        reason: '差一档就是不恢复（这一档走的是 loader.cached，不是注入口）',
      );
    });
  });

  group('收取间隔那一档（T88 之后也归进「意图」）', () {
    Future<FnthinkContractLoader> loadedLoader() async {
      final loader = FnthinkContractLoader(
        readAsset: (_) async => File(
          '${projectRoot()}/protocol/fnthink-v1.json',
        ).readAsStringSync(),
      );
      await loader.load();
      return loader;
    }

    test('选过 ⇒ 跟着进备份；没选过 ⇒ 不带这个键（"没选过"不是"选了某个数"）', () async {
      await seed({'flutter.${FnthinkSettings.keyPollSeconds}': 45});
      expect(
        await FnthinkBackup().collect(),
        containsPair(FnthinkBackup.fieldPollSeconds, 45),
      );

      await seed({});
      expect(
        (await FnthinkBackup().collect()).keys,
        isNot(contains(FnthinkBackup.fieldPollSeconds)),
      );
    });

    test('合法那一档恢复得回来', () async {
      await seed({});
      final backup = FnthinkBackup(contractLoader: await loadedLoader());
      expect(
        await backup.apply({FnthinkBackup.fieldPollSeconds: 45}),
        isNull,
        reason: '范围内 ⇒ 该恢复，并回一句"全部按预期"',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(FnthinkSettings.keyPollSeconds), 45);
    });

    test('越界那一档不写、并把这句话报出来（范围仍只来自契约）', () async {
      await seed({});
      final backup = FnthinkBackup(contractLoader: await loadedLoader());
      final note = await backup.apply({FnthinkBackup.fieldPollSeconds: 99999});
      expect(note, isNotNull);
      expect(note, contains('间隔'), reason: '报告里要能看出少了哪一项');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(FnthinkSettings.keyPollSeconds),
        isNull,
        reason: '写进 prefs 的代价是这台被服务端按额度持续 429，而界面只显示"收不到货"',
      );
    });

    test('契约读不到 ⇒ 这一档也不恢复（没有可校验的范围，宁可不写）', () async {
      await seed({});
      final backup = FnthinkBackup();
      final note = await backup.apply({FnthinkBackup.fieldPollSeconds: 30});
      expect(note, isNotNull, reason: 'fail-closed：读不到范围就不写，而不是"照抄文件里那个数"');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(FnthinkSettings.keyPollSeconds), isNull);
    });

    test('同意门与间隔同时没恢复 ⇒ 报告里两句话都要在', () async {
      await seed({});
      final backup = FnthinkBackup();
      final note = await backup.apply({
        FnthinkBackup.fieldConsentVersion: 1,
        FnthinkBackup.fieldPollSeconds: 30,
      });
      expect(note, contains('同意'));
      expect(note, contains('间隔'), reason: '只报第一条就是替用户把第二件事藏起来了');
    });

    test('只带那四个意图字段：这一格里不许出现口令/地址码/名单', () async {
      await seed({'flutter.${FnthinkSettings.keyPollSeconds}': 45});
      final got = await FnthinkBackup().collect();
      for (final banned in ['secret', 'passphrase', 'address', 'peer', 'key']) {
        expect(
          got.keys.join(',').toLowerCase(),
          isNot(contains(banned)),
          reason: '收集结果里出现了 $banned ⇒ 这一格开始携带凭证或身份',
        );
      }
    });
  });
}
