import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fnthink_push/fnthink_push.dart';

import 'platform_channel.dart';

/// 幻念推送的设备身份（T26 第三片的 Dart 半边 / T29 的签名入口）。
///
/// 这里**只有公钥**：私钥从不跨通道流动，签名动作留在原生侧做（KeyStore 里的密钥不可导出，
/// 能导出的实现就不叫不可导出）。所以这个类的全部职责是：取身份、把要签的字节递过去、拿回签名。
@immutable
class FnthinkDeviceIdentity {
  const FnthinkDeviceIdentity({
    required this.publicKey,
    required this.plan,
    required this.keystoreBacked,
  });

  /// 裸 Ed25519 公钥的 base64（32 字节）。这是要交给对端写进白名单的那一串。
  final String publicKey;

  /// 走了哪条路：`androidKeyStoreEd25519` 或 `keystoreWrappedSoftwareKey`。
  final String plan;

  /// ⚠ 只有原生路径是 true。包裹路径"不可导出"的是包裹密钥，不是私钥本体 ——
  /// 对端与用户都有权知道这个差别，所以它一路带到返回值里，不许为了好看抹平。
  final bool keystoreBacked;

  factory FnthinkDeviceIdentity.fromMap(Map<Object?, Object?> map) =>
      FnthinkDeviceIdentity(
        publicKey: map['publicKey'] as String? ?? '',
        plan: map['plan'] as String? ?? '',
        keystoreBacked: map['keystoreBacked'] as bool? ?? false,
      );

  @override
  String toString() =>
      'FnthinkDeviceIdentity(publicKey=${publicKey.isEmpty ? '无' : '${publicKey.substring(0, publicKey.length < 8 ? publicKey.length : 8)}…'}, '
      'plan=$plan, keystoreBacked=$keystoreBacked)';
}

/// 身份与签名服务。失败一律返回 null 而不是抛：调用方是 UI 与发送链路，
/// 它们要的是"这次签不出来"，而不是一页红屏；原因留在日志里（日志里也不会有私钥）。
class FnthinkIdentityService {
  FnthinkIdentityService({MethodChannel? channel})
    : _channel = channel ?? AppChannels.notification;

  final MethodChannel _channel;

  Future<FnthinkDeviceIdentity?> identity() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('getFnthinkIdentity');
      if (raw is! Map) return null;
      final identity = FnthinkDeviceIdentity.fromMap(
        raw.cast<Object?, Object?>(),
      );
      // 公钥为空 = 原生侧没建成身份。返回一个"看起来成功"的空身份，比失败更糟：
      // 发出去会让对端把一个谁都签不动的公钥写进白名单。
      return identity.publicKey.isEmpty ? null : identity;
    } on PlatformException catch (e) {
      debugPrint('FnthinkIdentityService.identity 失败：${e.code} ${e.message}');
      return null;
    }
  }

  /// 签一段已经按契约规范化的字节（[CanonicalMessage.bytes] 的产物）。
  Future<Uint8List?> signCanonicalBytes(List<int> canonical) async {
    try {
      final signature = await _channel.invokeMethod<String>(
        'signFnthinkBytes',
        {'canonicalBase64': base64Encode(canonical)},
      );
      if (signature == null || signature.isEmpty) return null;
      return base64Decode(signature);
    } on PlatformException catch (e) {
      debugPrint('FnthinkIdentityService.sign 失败：${e.code} ${e.message}');
      return null;
    }
  }

  /// 便捷入口：规范化 + 签一次。字段缺任何一项都不会走到通道 —— 规范化的错误是编程错误，
  /// 让它当场抛（`CanonicalMessage` 会点名缺了哪个字段），而不是签出一个语义不明的签名。
  Future<Uint8List?> signFields(
    FnthinkContract contract,
    Map<String, Object?> fields,
  ) async {
    // async 是为了让"缺字段"与其它失败同一种形状（都是 Future 里的错误）：
    // 同步抛会让同一个类的两种调用点写出两套错误处理，早晚漏掉一套。
    final canonical = CanonicalMessage.bytes(contract, fields);
    return signCanonicalBytes(canonical);
  }
}
