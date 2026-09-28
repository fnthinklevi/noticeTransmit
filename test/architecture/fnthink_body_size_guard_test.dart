import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 跨语言守卫（#130-A3）：**公网面的请求体上限必须装得下协议自己允许的最大载荷**。
///
/// 对的是三份互不相识的文本：
///  - `protocol/fnthink-v1.json` 的 `limits.requestBodyMaxBytes`（服务端闸）；
///  - `android/.../ChannelDescriptor.kt` 的 `ChannelLimits`（原生侧最宽的正文上限）；
///  - `server/lib/fnthink/bodylimit.js`（闸到底从契约读，还是从实现里另抄了一份数）。
///
/// 为什么要钉在这一处：它们各自都对的时候，改一处另两处不会报错。原生把 Telegram 上限
/// 抬到 40960 而这里还是 65536 时，症状是「一条合法长通知永远 413」，而用户在真机上看到的
/// 是"推送丢了" —— 与限流毫无关系的一条线索。上一片（A1）刚在限流上犯过"实现绕开契约自己定数"，
/// 所以这一片把"数字必须有唯一出处"直接做成断言。
void main() {
  const contractPath = 'protocol/fnthink-v1.json';
  const kotlinPath =
      'android/app/src/main/kotlin/com/fnthink/notice/ChannelDescriptor.kt';
  const limiterPath = 'server/lib/fnthink/bodylimit.js';
  const appPath = 'server/lib/app.js';

  final contract =
      jsonDecode(File(contractPath).readAsStringSync()) as Map<String, Object?>;
  final limits = contract['limits']! as Map<String, Object?>;
  final codes = contract['statusCodes']! as Map<String, Object?>;

  test('三份文本都在（缺一个就等于守卫空转）', () {
    for (final p in [contractPath, kotlinPath, limiterPath, appPath]) {
      expect(File(p).existsSync(), isTrue, reason: '$p 被挪走了：本守卫已失去保护作用');
    }
  });

  test('闸的字节数装得下最宽的正文上限（按转义最坏算）', () {
    final maxBytes = limits['requestBodyMaxBytes']! as int;
    final kotlin = File(kotlinPath).readAsStringSync();
    // 原生那张表里"字符"口径的上限（`*_BYTES` 是 UTF-8 字节口径，单独算一份）
    final chars = RegExp(
      r'const val [A-Z_]+_CHARS = (\d+)',
    ).allMatches(kotlin).map((m) => int.parse(m.group(1)!)).toList();
    final bytes = RegExp(
      r'const val [A-Z_]+_BYTES = (\d+)',
    ).allMatches(kotlin).map((m) => int.parse(m.group(1)!)).toList();
    expect(chars, isNotEmpty, reason: '原生上限表改名了：这条守卫从此什么都拦不住');
    final widest = chars.reduce((a, b) => a > b ? a : b) * 6;
    // ×6 不是拍脑袋：JSON 里一个非 ASCII 字符转义成 `\uXXXX` 是 6 字节，那是**最坏**编码。
    expect(
      maxBytes,
      greaterThanOrEqualTo(widest),
      reason:
          '原生最宽正文 $widest 字节（${widest ~/ 6} 字符 × 转义最坏），'
          '而闸是 $maxBytes ⇒ 合法长通知会被当成攻击拦掉，症状是"推送静默丢了"',
    );
    expect(
      maxBytes,
      greaterThanOrEqualTo(bytes.fold<int>(0, (a, b) => a > b ? a : b)),
      reason: '字节口径的正文上限也不能超过闸',
    );
  });

  test('群发倍数与地址码也得塞进这一个包里', () {
    final maxBytes = limits['requestBodyMaxBytes']! as int;
    final groupSendMax = limits['groupSendMax']! as int;
    final addressCode =
        (contract['identity']! as Map<String, Object?>)['addressCode']
            as Map<String, Object?>;
    final addressLen = addressCode['length']! as int; // 取不到就该红，不许悄悄按 10 算
    // 一发群发最多带 groupSendMax 个目标地址；正文只有一份（同一条通知发给多台）。
    final envelope = groupSendMax * (addressLen + 8) + 4096;
    expect(
      maxBytes,
      greaterThanOrEqualTo(envelope),
      reason: '闸小于"群发信封"($envelope) 时，groupSendMax 这个数字就是假的',
    );
  });

  test('公网面那把必须严于管理面的 1 MB（否则收紧没有发生）', () {
    final maxBytes = limits['requestBodyMaxBytes']! as int;
    final appSrc = File(appPath).readAsStringSync();
    final admin = RegExp(
      r"express\.json\(\{ limit: '(\d+)mb' \}\)",
    ).firstMatch(appSrc);
    expect(admin, isNotNull, reason: '管理面的上限写法变了：这条断言从此是摆设');
    expect(maxBytes, lessThan(int.parse(admin!.group(1)!) * 1024 * 1024));
  });

  test('闸只从契约读，且 413 这个码由契约给出', () {
    final src = File(limiterPath).readAsStringSync();
    expect(src, contains('requestBodyMaxBytes'), reason: '实现没再读契约 ⇒ 数字变成第二份真值');
    expect(src, isNot(contains('limit: \'')), reason: '实现里写死了字面量上限');
    expect(codes.containsKey('requestTooLarge'), isTrue);
    final code = codes['requestTooLarge']! as int;
    expect(code, inInclusiveRange(400, 417));
    // 与其它同步码不撞车（撞车时运维分不清被拒的原因）
    expect(
      codes.entries
          .where(
            (e) =>
                e.value is num && e.value != code && e.key != 'requestTooLarge',
          )
          .length,
      greaterThan(0),
    );
  });
}
