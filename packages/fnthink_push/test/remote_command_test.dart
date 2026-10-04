import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 远程执行 片3b-2：**指令载荷**的编解码（两端共用的那一份形状）。
///
/// 这一组钉四件事：
///  ① 往返：拼出来的拆回去逐项相等（含参数与两种凭据）；
///  ② **拆不出来就说拆不出来**：不是指令 / 坏 JSON / 不是对象 / 缺 level / 缺 item ⇒ 全 null；
///  ③ **凭据不进 toString**（它会进日志，而日志会离开这台机）；
///  ④ 前缀与标题信封**不同**（共用前缀的话，指令会被当成标题消息拆）。
void main() {
  group('往返', () {
    test('最小那条（L1，无参数无凭据）逐项相等', () {
      final wire = RemoteCommandEnvelope.encode(
        level: 'L1',
        item: 'listener:start',
      );
      final back = RemoteCommandEnvelope.decode(wire);
      expect(back, isNotNull);
      expect(back!.level, 'L1');
      expect(back.item, 'listener:start');
      expect(back.argument, isEmpty);
      expect(back.key, isNull);
      expect(back.totpCode, isNull);
      expect(back.hasCredential, isFalse);
    });

    test('带参数、带高级密钥、带 TOTP 三样一起往返', () {
      final wire = RemoteCommandEnvelope.encode(
        level: 'L3',
        item: 'channel:toggle',
        argument: 'webhook_acme',
        key: 'my-secret-key',
        totpCode: '123456',
      );
      final back = RemoteCommandEnvelope.decode(wire)!;
      expect(back.level, 'L3');
      expect(back.item, 'channel:toggle');
      expect(back.argument, 'webhook_acme');
      expect(back.key, 'my-secret-key');
      expect(back.totpCode, '123456');
      expect(back.hasCredential, isTrue);
    });

    test('参数为空时载荷里根本不带那个键（不是带一个空串）', () {
      final wire = RemoteCommandEnvelope.encode(
        level: 'L2',
        item: 'device_state:push',
      );
      final raw =
          jsonDecode(wire.substring(RemoteCommandEnvelope.prefix.length))
              as Map;
      expect(raw.containsKey('argument'), isFalse);
      expect(raw.containsKey('key'), isFalse);
      expect(raw.containsKey('totp'), isFalse);
    });

    test('空串凭据按"没带"处理（传了空串与不传是同一件事）', () {
      final wire = RemoteCommandEnvelope.encode(
        level: 'L2',
        item: 'listener:stop',
        key: '',
        totpCode: '',
      );
      final back = RemoteCommandEnvelope.decode(wire)!;
      expect(back.key, isNull);
      expect(back.totpCode, isNull);
      expect(back.hasCredential, isFalse);
    });
  });

  group('拆不出来就是拆不出来（不猜）', () {
    test('普通通知那一条拆出来是 null', () {
      expect(RemoteCommandEnvelope.decode('今天天气不错'), isNull);
      expect(RemoteCommandEnvelope.decode(''), isNull);
    });

    test('前缀后面不是 JSON ⇒ null', () {
      expect(
        RemoteCommandEnvelope.decode('${RemoteCommandEnvelope.prefix}not json'),
        isNull,
      );
    });

    test('解出来不是对象 ⇒ null', () {
      expect(
        RemoteCommandEnvelope.decode('${RemoteCommandEnvelope.prefix}[1,2]'),
        isNull,
      );
    });

    test('缺 level 或缺 item ⇒ null（字段不全的那一条不是"半个指令"）', () {
      expect(
        RemoteCommandEnvelope.decode(
          '${RemoteCommandEnvelope.prefix}{"item":"listener:start"}',
        ),
        isNull,
      );
      expect(
        RemoteCommandEnvelope.decode(
          '${RemoteCommandEnvelope.prefix}{"level":"L2"}',
        ),
        isNull,
      );
      expect(
        RemoteCommandEnvelope.decode(
          '${RemoteCommandEnvelope.prefix}{"level":"","item":"x"}',
        ),
        isNull,
      );
    });

    test('参数与凭据类型不对时退成空/null，而不是抛', () {
      final wire =
          '${RemoteCommandEnvelope.prefix}'
          '{"level":"L2","item":"x","argument":123,"key":true,"totp":[]}';
      final back = RemoteCommandEnvelope.decode(wire);
      expect(back, isNotNull);
      expect(back!.argument, isEmpty);
      expect(back.key, isNull);
      expect(back.totpCode, isNull);
    });
  });

  group('与标题信封互不串', () {
    test('前缀与标题信封不同（共用前缀的话指令会被当成标题消息拆）', () {
      // ⚠ 从契约现取，不写死字面量：写死的话契约改前缀那天这里会**绿着**失效，
      // 而失效的表现是"一条指令在收件端被当成标题消息拆掉"。
      final titlePrefix = FnthinkContract.readFile().deviceTitlePrefix;
      expect(
        RemoteCommandEnvelope.prefix == titlePrefix,
        isFalse,
        reason: '指令前缀与标题信封前缀相同：$titlePrefix',
      );
    });

    test('一条指令不会被标题信封当成标题消息拆出来', () {
      final command = RemoteCommandEnvelope.encode(
        level: 'L1',
        item: 'listener:start',
      );
      final asTitle = FnthinkTitleEnvelope.decode(
        FnthinkContract.readFile(),
        command,
      );
      expect(asTitle.split, isFalse, reason: '标题信封拆成功 = 指令被当成一条带标题的通知');
      expect(asTitle.title, isEmpty);
    });
  });

  group('凭据不进日志', () {
    test('toString 里没有那串密钥，也没有那六位码', () {
      final cmd = RemoteCommandEnvelope.decode(
        RemoteCommandEnvelope.encode(
          level: 'L3',
          item: 'channel:toggle',
          argument: 'webhook_acme',
          key: 'super-secret-key',
          totpCode: '654321',
        ),
      )!;
      final printed = cmd.toString();
      expect(printed.contains('super-secret-key'), isFalse);
      expect(printed.contains('654321'), isFalse);
      expect(printed.contains('已带'), isTrue, reason: '要说清"带了"，但不说带了什么');
    });
  });
}
