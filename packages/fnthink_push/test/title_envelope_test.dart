import 'dart:convert';
import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// 设备这一路标题信封的 **Dart 侧**（§4 第 10 条定稿）。Node 那一半在
/// `server/test/fnthink-title-envelope.test.js`，两边吃同一份
/// `protocol/fnthink-vectors-v1.json` 的 `titleEnvelope` 段。
///
/// 分工要说清，否则这份表会被读成"两端各拆一遍"：
///  - Dart（发送端 + 收件端）断的是**编码规则**：这一串怎么拼出来、怎么拆回去、拆不回来时怎么办；
///  - Node 断的是**它不参与**：服务端把整段当不透明正文存、当不透明正文回，标题列永远是空的。
///
/// ⚠ 这里的期望值全部来自向量文件（手写的），不是从实现算出来的 —— 拿实现读的那份真值去断言，
/// "写死前缀"与"从契约读前缀"就永远分不出来（假绿台账 X5/Z4/SA1/RC1 那一族）。
void main() {
  final contract = FnthinkContract.readFile();
  final vectors =
      jsonDecode(File(fnthinkVectorsFile()).readAsStringSync())
          as Map<String, Object?>;
  final rows =
      ((vectors['titleEnvelope'] as Map<String, Object?>)['rows']
              as List<Object?>)
          .cast<Map<String, Object?>>();
  // 最常见的那一行（te-plain）：三格期望值都取自表，不在测试里另写一遍字面量。
  final plainExpect =
      rows.firstWhere((r) => r['id'] == 'te-plain')['expect']
          as Map<String, Object?>;
  final plainWire = '${plainExpect['wireBody']}';
  final plainTitle = '${plainExpect['appliedTitle']}';
  final plainBody = '${plainExpect['appliedBody']}';

  List<String> replayEncode() {
    final bad = <String>[];
    for (final row in rows) {
      final given = row['given'] as Map<String, Object?>;
      if (!given.containsKey('title')) continue;
      final expect_ = row['expect'] as Map<String, Object?>;
      final got = FnthinkTitleEnvelope.encode(
        contract,
        title: '${given['title']}',
        body: '${given['body']}',
      );
      if (got != expect_['wireBody']) {
        bad.add('${row['id']}: 编码得 ${got.replaceAll("\n", "\\n")}');
      }
    }
    return bad;
  }

  test('表非空，且每行都有 id（少一行的代价是"这一类输入今天没人测"）', () {
    expect(rows, isNotEmpty);
    expect(rows.map((r) => r['id']).toSet().length, rows.length);
  });

  test('逐条：编码结果就是向量里那一串 wireBody', () {
    expect(replayEncode(), isEmpty);
  });

  test('逐条：拆回来就是 appliedTitle / appliedBody / split 那三格', () {
    final bad = <String>[];
    for (final row in rows) {
      final given = row['given'] as Map<String, Object?>;
      final expect_ = row['expect'] as Map<String, Object?>;
      final wire = '${expect_['wireBody']}';
      final signed = '${given['signedTitleFromServer'] ?? ''}';
      final got = FnthinkTitleEnvelope.unwrap(
        contract: contract,
        signedTitle: signed,
        wireBody: wire,
      );
      if (got.title != expect_['appliedTitle'] ||
          got.body != expect_['appliedBody'] ||
          got.split != expect_['split']) {
        bad.add(
          '${row['id']}: 拆出 title=${got.title} body=${got.body} split=${got.split}',
        );
      }
    }
    expect(bad, isEmpty);
  });

  test('拆不拆这件事要说得出口：decode 的 split 与 unwrap 的不是同一回事', () {
    // 已签标题非空时 unwrap 不走信封（split=false），而**同一段 wireBody 单独 decode 是能拆开的**。
    // 这一条钉的是那两句的区别：少了它，下一个改动会把"不拆"实现成"拆了但不用"，
    // 表现是信封里那个假标题悄悄进了正文第一行。
    const wire = 'fnthink-title:v1{"t":"信封标题","b":"信封正文"}';
    expect(FnthinkTitleEnvelope.decode(contract, wire).split, isTrue);
    expect(
      FnthinkTitleEnvelope.unwrap(
        contract: contract,
        signedTitle: '已签标题',
        wireBody: wire,
      ).split,
      isFalse,
    );
  });

  test('收件内核那一刀真的接上了：tryFrom 用的是拆出来的标题与正文，不是服务端那两列', () {
    // 这一条是"编解码对了"与"收件端看得见"之间的那一段：拆开算对了、
    // 而 `FnthinkDelivered` 还按 raw 里那两列原样装，症状就是通知栏与收件详情显示一串带前缀的 JSON。
    final delivered = FnthinkDelivered.tryFrom(contract, {
      'messageId': 'm_1',
      'type': 'notice',
      'title': '',
      'body': plainWire,
      'sender': '7YD4RKQPBM8XZ3VHNT',
    });
    expect(delivered, isNotNull);
    expect(delivered!.title, plainTitle);
    expect(delivered.body, plainBody);
    // 已签标题非空时原样保留（信封不许盖它）。
    final signed = FnthinkDelivered.tryFrom(contract, {
      'messageId': 'm_2',
      'type': 'notice',
      'title': '已签标题',
      'body': plainWire,
    });
    expect(signed!.title, '已签标题');
    expect(signed.body, plainWire);
    // 端点那一路的普通正文：一个字符都不许动。
    final plain = FnthinkDelivered.tryFrom(contract, {
      'messageId': 'm_3',
      'type': 'notice',
      'title': '端点给的标题',
      'body': 'NAS：磁盘 91%',
    });
    expect(plain!.title, '端点给的标题');
    expect(plain.body, 'NAS：磁盘 91%');
  });

  test('前缀、键名都从契约读：换一把契约就换一串字节（不是在代码里写死）', () {
    final moved = Map<String, Object?>.from(
      jsonDecode(File(fnthinkContractFile()).readAsStringSync())
          as Map<String, Object?>,
    );
    final envelope = Map<String, Object?>.from(
      ((moved['deviceSend']! as Map<String, Object?>)['titleEnvelope']
          as Map<String, Object?>),
    );
    envelope['prefix'] = 'fnthink-title:v9';
    envelope['bodyKey'] = 'text';
    final section = Map<String, Object?>.from(
      moved['deviceSend']! as Map<String, Object?>,
    );
    section['titleEnvelope'] = envelope;
    moved['deviceSend'] = section;
    final other = FnthinkContract(moved);
    final wire = FnthinkTitleEnvelope.encode(other, title: '标题', body: '正文');
    expect(wire.startsWith('fnthink-title:v9{"t":"标题","text":"正文"}'), isTrue);
    // 用真契约去拆这一串 ⇒ 认不出前缀，也认不出键名 ⇒ 整段是正文（不猜）。
    final back = FnthinkTitleEnvelope.decode(contract, wire);
    expect(back.split, isFalse);
    expect(back.title, '');
    expect(back.body, wire);
  });

  test('契约缺这一节 ⇒ 取值是抛而不是退回默认前缀（默认前缀等于第二份协议）', () {
    final bare = <String, Object?>{}
      ..addAll(
        jsonDecode(File(fnthinkContractFile()).readAsStringSync())
            as Map<String, Object?>,
      );
    bare.remove('deviceSend');
    final broken = FnthinkContract(bare);
    expect(() => broken.deviceTitlePrefix, throwsStateError);
    expect(
      () => FnthinkTitleEnvelope.encode(broken, title: 't', body: 'b'),
      throwsStateError,
    );
    expect(
      broken.validate().any(
        (p) => p.startsWith('契约缺 deviceSend.titleEnvelope'),
      ),
      isTrue,
    );
  });

  test('validate 拦得住那三种写错的信封（都不是口味：每一条都会静默生效）', () {
    Map<String, Object?> loaded() =>
        jsonDecode(File(fnthinkContractFile()).readAsStringSync())
            as Map<String, Object?>;

    Map<String, Object?> withEnvelope(
      void Function(Map<String, Object?> e) mutate,
    ) {
      final doc = loaded();
      final section = Map<String, Object?>.from(
        doc['deviceSend']! as Map<String, Object?>,
      );
      section['titleEnvelope'] = Map<String, Object?>.from(
        section['titleEnvelope']! as Map<String, Object?>,
      );
      mutate(section['titleEnvelope']! as Map<String, Object?>);
      doc['deviceSend'] = section;
      return doc;
    }

    // ① 前缀里塞进签名字节的分隔符 ⇒ 规范化函数运行时抛，症状是"这一路今天发不出去"。
    expect(
      FnthinkContract(
        withEnvelope((e) => e['prefix'] = 'fn\u0000think'),
      ).validate(),
      contains(contains('prefix 含 signature.separator')),
    );
    // ② 两个键名同名 ⇒ 写得进去拆不出来，标题与正文互相覆盖。
    expect(
      FnthinkContract(withEnvelope((e) => e['bodyKey'] = 't')).validate(),
      contains(contains('titleKey / bodyKey')),
    );
    // ③ 声明成"服务端拆" ⇒ 与本包实现不符（两份实现各拆一半）。
    expect(
      FnthinkContract(withEnvelope((e) => e['splitBy'] = 'server')).validate(),
      contains(contains('splitBy 必须是 receiving-client')),
    );
    // 基线：真契约这一节是过的（少这一句，上面三条红可能只是"整段都没读"）。
    expect(
      FnthinkContract(
        loaded(),
      ).validate().where((p) => p.contains('titleEnvelope')),
      isEmpty,
    );
  });
}
