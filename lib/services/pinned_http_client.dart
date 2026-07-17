import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// SSL 证书固定帮助类。
///
/// ## 获取证书指纹
///
/// 运行以下命令获取服务器 X.509 证书的 SHA256 指纹：
/// ```
/// openssl s_client -connect notice.fnthink.top:443 -servername notice.fnthink.top \
///   </dev/null 2>/dev/null \
///   | openssl x509 -noout -fingerprint -sha256 \
///   | sed 's/.*=//'
/// ```
///
/// ## 使用方法
///
/// ```dart
/// final client = PinnedHttpClient.create(
///   pinnedFingerprints: {
///     'notice.fnthink.top': 'AA:BB:CC:DD:...',
///     'xget.fnthink.top': 'AA:BB:CC:DD:...',
///   },
/// );
/// ```
///
/// 不配置 `pinnedFingerprints` 时仅做标准 TLS 验证。
class PinnedHttpClient {
  static http.Client create({
    Map<String, String> pinnedFingerprints = const {},
  }) {
    final httpClient = HttpClient();

    if (pinnedFingerprints.isNotEmpty) {
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
        final expected = pinnedFingerprints[host];
        if (expected == null) return false;

        // 计算证书 PEM 中 DER 部分的 SHA256
        final certDer = _pemToDer(cert.pem);
        if (certDer.isEmpty) return false;

        final hashBytes = sha256.convert(certDer).bytes;
        final hexFingerprint = hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

        // 比较指纹（支持带/不带冒号、空格的格式）
        final expectedClean = expected.toUpperCase().replaceAll(':', '').replaceAll(' ', '');
        final certClean = hexFingerprint.replaceAll(':', '');
        return certClean == expectedClean;
      };
    }

    return IOClient(httpClient);
  }

  /// 从 PEM 字符串中提取 DER 字节
  static Uint8List _pemToDer(String pem) {
    try {
      final lines = pem
          .split(RegExp(r'\r?\n'))
          .where((l) => !l.startsWith('-----'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join();
      return base64.decode(lines);
    } catch (_) {
      return Uint8List(0);
    }
  }
}
