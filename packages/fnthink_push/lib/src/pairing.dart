import 'contract.dart';
import 'credentials.dart';

/// 配对（T28）的纯裁决层：载荷的拼装与解析、失败的可见文案、A 侧是否批准。
///
/// 这一层**不碰**二维码渲染、相机、网络与私钥 —— 它只回答三个会被两端各写一遍、
/// 而写歪一次就查不出来的问题：① 这份载荷到底算不算本协议的配对载荷；
/// ② 失败了该对用户说什么（答案对所有"设备不存在/口令错"都一样）；
/// ③ 什么条件下才允许把陌生公钥写进白名单（永远要人点一次头）。
class FnthinkPairingRequest {
  FnthinkPairingRequest({
    required this.addressCode,
    required this.pairingCode,
    required this.level,
    required this.contractVersion,
  });

  /// 接收方地址码（公开标识）。
  final String addressCode;

  /// 一次性配对口令。⚠ 它是整条链路上唯一允许出现在配对载荷里的秘密。
  final String pairingCode;

  /// 请求的能力级别。
  final String level;

  final int contractVersion;

  /// 生成要印进二维码/一次性链接的文本。
  ///
  /// 只在**本机显示**与 POST 正文里出现，绝不进 path/query：URL 会被 access log、
  /// 浏览器历史与中间代理留副本（契约 `privacy.credentialsNeverIn` 的 url 就是这条）。
  String qrText(FnthinkContract contract) {
    final fields = contract.pairingPayloadFields;
    final values = {
      'v': '$contractVersion',
      'to': addressCode,
      'code': pairingCode,
      'level': level,
    };
    final missing = fields.where((f) => !values.containsKey(f)).toList();
    if (missing.isNotEmpty) {
      throw StateError('契约要求载荷带 ${missing.join('/')}，本实现不会造这些字段');
    }
    final parts = [for (final field in fields) '$field=${values[field]}'];
    return '${contract.pairingQrPrefix}?${parts.join('&')}';
  }

  /// 解析。失败**不抛**：调用方要的是"能不能配对"，而原因只进日志/回执不进文案。
  static FnthinkPairingResult parse(FnthinkContract contract, String text) {
    final prefix = '${contract.pairingQrPrefix}?';
    if (!text.startsWith(prefix)) {
      return FnthinkPairingResult._fail('prefix');
    }
    final query = text.substring(prefix.length);
    if (query.isEmpty) return FnthinkPairingResult._fail('empty');
    final fields = <String, String>{};
    for (final part in query.split('&')) {
      final at = part.indexOf('=');
      if (at <= 0) return FnthinkPairingResult._fail('shape:$part');
      final key = part.substring(0, at);
      // 同一个键出现两次：不是"取第一个还是最后一个"的问题，是载荷被人拼过 —— 直接拒。
      if (fields.containsKey(key))
        return FnthinkPairingResult._fail('repeat:$key');
      fields[key] = part.substring(at + 1);
    }
    // 配对载荷上的"容错"= 给对方一个往身份交换里塞料的口子（与第三方推送正文的
    // ignoreUnknownFields 是两回事，那条只管 title/body 别名）。
    if (contract.pairingRejectUnknownFields) {
      // 先查禁带秘密再查"未知字段"：`signature=` 两者都命中，而日志里该看到的是前者。
      for (final key in contract.pairingNeverCarry) {
        if (fields.containsKey(key)) {
          return FnthinkPairingResult._fail('carries-secret:$key');
        }
      }
      final known = contract.pairingPayloadFields.toSet();
      for (final key in fields.keys) {
        if (!known.contains(key))
          return FnthinkPairingResult._fail('unknown:$key');
      }
    }
    for (final required in contract.pairingPayloadFields) {
      if (!fields.containsKey(required)) {
        return FnthinkPairingResult._fail('missing:$required');
      }
    }
    final parsedVersion = int.tryParse(fields['v'] ?? '');
    if (parsedVersion == null)
      return FnthinkPairingResult._fail('version-unparseable');
    if (parsedVersion != contract.contractVersion) {
      return FnthinkPairingResult._fail('version:$parsedVersion');
    }
    if (FnthinkAddressCode.parse(contract, fields['to'] ?? '') == null) {
      return FnthinkPairingResult._fail('address-code');
    }
    if (FnthinkPairingCode.parse(contract, fields['code'] ?? '') == null) {
      return FnthinkPairingResult._fail('pairing-code');
    }
    if (!contract.capabilityLevels.contains(fields['level'])) {
      return FnthinkPairingResult._fail('level:${fields['level']}');
    }
    return FnthinkPairingResult._ok(
      FnthinkPairingRequest(
        addressCode: (fields['to'] ?? '').toUpperCase(),
        pairingCode: (fields['code'] ?? '').toUpperCase(),
        level: fields['level'] ?? '',
        contractVersion: parsedVersion,
      ),
    );
  }
}

/// 解析结果：`ok` + 只在内部使用的原因。
class FnthinkPairingResult {
  FnthinkPairingResult._(this.request, this.internalReason);

  factory FnthinkPairingResult._ok(FnthinkPairingRequest request) =>
      FnthinkPairingResult._(request, null);

  factory FnthinkPairingResult._fail(String reason) =>
      FnthinkPairingResult._(null, reason);

  final FnthinkPairingRequest? request;

  /// 给日志与回执用的原因。**不许**拼进用户可见文案 —— 见 [fnthinkPairingFailureTextKey]。
  final String? internalReason;

  bool get ok => request != null;
}

/// 用户看到的失败文案只有一个 key：预授权阶段的四种失败（没这台设备 / 口令错 /
/// 口令过期 / 口令形状不对）塌成同一条。理由与 T27 服务端那条一样 —— 地址码可分享、
/// 可印二维码，一旦文案能分辨，服务端与本机都成了"哪些地址码有效"的枚举器。
///
/// ⚠ 这个函数**故意**不使用它的参数。哪天要按原因分叉，必须先回答"分叉的那条文案
/// 会不会泄露设备存在性"，而 `pairing_test.dart` 里那条用例就是让人别忘了回答它。
String fnthinkPairingFailureTextKey(String? unusedInternalReason) =>
    'fnthinkPairingFailedGeneric';

/// 哪些失败**可以**给出具体原因：口令已经验对（对方就是设备所有者）之后的策略性拒绝。
/// 这一条区分是本文件存在的意义 —— 把"同形"当成万能药，会把"你要的级别太高"这种
/// 用户必须知道的提示也糊成一句"配对失败"，然后用户只能反复重试。
bool fnthinkPairingMayExplain(
  String internalReason, {
  required bool codeVerified,
}) {
  if (!codeVerified) return false;
  return internalReason.startsWith('level:') ||
      internalReason == 'level-too-high';
}

enum PairingVerdict {
  /// 口令已验、签名已验，等人点一次头。**默认状态就是这个**。
  awaitingConfirmation,

  /// 已确认，可以写入白名单。
  approve,

  /// 载荷本身不成形（前缀/字段/版本）。
  rejectPayload,

  /// 口令阶段失败（不存在的设备、错口令、过期、已消耗 —— 对外同一句）。
  rejectCredential,

  /// 缺签名或签名不对（只对**携带**的字段判，验签本身要私钥侧配合，见 T29）。
  rejectSignature,

  /// 请求的级别超过免本地确认的上限（L3 必须走锁屏/生物认证，不在此路）。
  rejectLevelTooHigh,
}

/// A 侧"要不要把这条请求写进白名单"的唯一裁决点。纯函数：不写库、不弹框、不猜时钟。
PairingVerdict decidePairing(
  FnthinkContract contract, {
  required FnthinkPairingResult? payload,
  required bool pairingCodeVerified,
  bool hasSenderSignature = false,
  bool signatureValid = false,
  bool userConfirmed = false,
}) {
  // 顺序就是规则本身。把"人没点确认"提前判，会让不合法的载荷也走一遍确认框；
  // 把签名提前判，会让拿错口令的人得到一条与"地址码不存在"不同的反馈 ——
  // 那是 T27 同形那条的翻版。
  if (payload == null || !payload.ok) return PairingVerdict.rejectPayload;
  if (!pairingCodeVerified) return PairingVerdict.rejectCredential;
  if (contract.levelRank(payload.request!.level) >
      contract.levelRank(contract.pairingMaxRequestableLevel)) {
    return PairingVerdict.rejectLevelTooHigh;
  }
  if (!hasSenderSignature || !signatureValid) {
    return PairingVerdict.rejectSignature;
  }
  // 契约哪天被翻成"可以自动批准"，这里也**不**自动批准：宁可拒，也不擅自多一个可信发送方。
  // （`validate()` 已把那种契约报成不自洽；这条是运行期的第二道，因为它守的是白名单。）
  if (!contract.pairingRequiresHumanConfirmation) {
    return PairingVerdict.rejectPayload;
  }
  // ⚠ 走到这里仍然不批准：机器能判"对不对"，"要不要多一个可信发送方"是人的决定。
  if (!userConfirmed) return PairingVerdict.awaitingConfirmation;
  return PairingVerdict.approve;
}
