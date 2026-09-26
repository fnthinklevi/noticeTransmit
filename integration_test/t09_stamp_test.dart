import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/services/app_channel_service.dart';
import 'package:notice_transmit/services/channel_config_codec.dart';
import 'package:notice_transmit/services/email_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/webhook_service.dart';

/// roadmap T09「真发一次」的**设备侧**：把库里每一类通道真发一条出去，并打印一份清单。
///
/// ⚠ 本文件与另两个集成测试最要紧的区别：**一个方法都不许 mock**。
/// `support/native_payload_stubs.dart` 那套桩能证明"接线通了"，证明不了"对方收到了"，
/// 而 realSend 这一列要的就是后者 —— 一旦这里补上桩，脚本仍然会打印"发送成功"，
/// 盖章于是变成自证。守卫见 `test/architecture/t09_stamp_tool_test.dart`。
///
/// **它不会替你盖章。** 它只负责把消息真发出去 + 生成一次性 nonce，剩下的判断
/// （收件端到底有没有出现那一条）由人来做，写矩阵的是主机侧的
/// `tools/t09_stamp.dart confirm`。
///
/// 用法（由 `tools/t09_stamp.dart send` 统一驱动，手工跑时）：
///   flutter test integration_test/t09_stamp_test.dart -d emulator-5554 \
///     --dart-define=T09_TYPES=dingtalk,email
///
/// ⚠ 这会往你配置的真实收件端发真消息。只在模拟器上跑，别对着你的手机跑。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  /// 只发这些类型；空 = 库里有的全都发。
  const onlyTypes = String.fromEnvironment('T09_TYPES');

  testWidgets(
    'T09 盖章：逐类真发一条（nonce 挂在设备名上）',
    (tester) async {
      const channel = AppChannels.notification;
      final filter = onlyTypes
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();

      // nonce 为什么要挂在设备名上：三族的测试消息正文都是**原生自己拼的**
      // （`buildTestPayload` / `AppChannelSender` / `EmailSender` 的 `%deviceName%`），
      // 调用方插不进自定义文本。设备名是三者唯一都带、且能改回来的自由字段。
      final originalName = await _deviceName(channel);
      final nonce = _makeNonce();
      final rows = <Map<String, dynamic>>[];
      final version = await _appVersion(channel);

      try {
        await channel.invokeMethod('setDeviceName', {'name': 'T09-$nonce'});

        final hooks = WebhookService();
        await hooks.loadChannels();
        final apps = AppChannelService();
        await apps.loadChannels();
        final emails = (await DatabaseHelper().getEmailChannels())
            .map((r) => EmailChannel.fromDbRow(r))
            .toList();

        // 每个类型只发**一条**（同类型五条通道不需要骚扰收件端五次）；
        // 优先发启用的那条，全族都没启用时仍发第一条 —— 盖章要的是"这条链路能送到"。
        for (final entry in _groupByType(
          hooks.channels,
          (c) => c['channelType']?.toString() ?? '',
        ).entries) {
          if (filter.isNotEmpty && !filter.contains(entry.key)) continue;
          final c = entry.value.first;
          final secret = c['secret']?.toString() ?? '';
          rows.add(
            await _sendOne(
              type: entry.key,
              family: 'webhook',
              target: _redact(c['url']?.toString() ?? ''),
              call: () => channel.invokeMethod('testWebhook', {
                'url': c['url']?.toString() ?? '',
                if (secret.isNotEmpty) 'secret': secret,
                'channelType': entry.key,
              }),
            ),
          );
        }

        for (final entry in _groupByType(
          apps.channels,
          (c) => c['appType']?.toString() ?? '',
        ).entries) {
          if (filter.isNotEmpty && !filter.contains(entry.key)) continue;
          final c = entry.value.first;
          rows.add(
            await _sendOne(
              type: entry.key,
              family: 'app',
              target: _redact(
                c['baseUrl']?.toString() ?? c['base_url']?.toString() ?? '',
              ),
              call: () => channel.invokeMethod('testAppChannel', {
                ...ChannelConfigCodec.appProbePayload(c),
                'appType': entry.key,
              }),
            ),
          );
        }

        if (emails.isNotEmpty &&
            (filter.isEmpty || filter.contains('email'))) {
          final emailService = EmailService();
          final first = emails.first;
          rows.add(
            await _sendOne(
              type: 'email',
              family: 'email',
              target: _redact('mailto:${first.toEmail}'),
              call: () => emailService.testEmail(first),
            ),
          );
        }
      } finally {
        // 无论发到哪一步炸了都要把设备名换回去：这是用户的设置，不是测试脚手架。
        try {
          await channel.invokeMethod('setDeviceName', {'name': originalName});
        } catch (e) {
          debugPrint('T09 盖章：设备名还原失败，请手动改回「$originalName」: $e');
        }
      }

      final manifest = <String, dynamic>{
        'nonce': nonce,
        'deviceNameBefore': originalName,
        'versionName': version['versionName'],
        'build': version['versionCode'],
        'at': DateTime.now().toIso8601String(),
        'rows': rows,
      };
      // 主机侧就靠这一行前缀取结果（设备侧读不到宿主 stdin，也不该写宿主文件）。
      debugPrint('T09-MANIFEST ${jsonEncode(manifest)}');
      // ignore: avoid_print
      print('T09-MANIFEST ${jsonEncode(manifest)}');

      expect(
        rows,
        isNotEmpty,
        reason:
            '模拟器库里一个通道都没有：先去「更多 → 备份与恢复」把真实备份导入这台'
            '模拟器（或用界面配好），再跑盖章。',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<String> _deviceName(MethodChannel channel) async {
  try {
    final r = await channel.invokeMethod<Object?>('getDeviceName');
    if (r is Map) return (r['name'] ?? r['deviceName'] ?? '').toString();
    return (r ?? '').toString();
  } catch (e) {
    debugPrint('T09 盖章：读设备名失败（将继续，但还原时只能写空串）: $e');
    return '';
  }
}

Future<Map<String, Object?>> _appVersion(MethodChannel channel) async {
  try {
    final r = await channel.invokeMethod<Object?>('getAppVersion');
    if (r is Map) {
      return r.map((k, v) => MapEntry(k.toString(), v as Object?));
    }
  } catch (e) {
    debugPrint('T09 盖章：读版本号失败: $e');
  }
  return const {};
}

/// 一次真发。失败**不抛**：发不出去本身就是这一列的结论（这一类就盖不了章），
/// 让整轮跑完比在第三条中断更有用。
Future<Map<String, dynamic>> _sendOne({
  required String type,
  required String family,
  required String target,
  required Future<Object?> Function() call,
}) async {
  final watch = Stopwatch()..start();
  var ok = false;
  var message = '';
  try {
    final r = await call();
    if (r is Map) {
      ok = r['success'] == true;
      message = (r['message'] ?? r['reason'] ?? '').toString();
    } else {
      message = '原生未返回结论（${r.runtimeType}）';
    }
  } catch (e) {
    message = '调用抛异常: $e';
  }
  return {
    'type': type,
    'family': family,
    'target': target,
    'success': ok,
    'message': message,
    'latencyMs': watch.elapsedMilliseconds,
  };
}

Map<String, List<Map<String, dynamic>>> _groupByType(
  List<Map<String, dynamic>> rows,
  String Function(Map<String, dynamic>) typeOf,
) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final t = typeOf(r);
    if (t.isEmpty) continue;
    (out[t] ??= <Map<String, dynamic>>[]).add(r);
  }
  // 启用的排前面，其余顺序不变（稳定排序 → 同一台设备两次跑挑到同一条）
  for (final list in out.values) {
    list.sort((a, b) => (b['enabled'] == true ? 1 : 0) - (a['enabled'] == true ? 1 : 0));
  }
  return out;
}

/// 清单里**不得出现凭据**：只留 host（或邮箱域名）。URL 的 path/query 里往往是
/// access_token / webhook key，写进 outputs/ 就等于把密钥抄到仓库旁边。
String _redact(String raw) {
  if (raw.isEmpty) return '(空)';
  if (raw.startsWith('mailto:')) {
    final at = raw.indexOf('@');
    return at < 0 ? raw.substring(7) : '…@${raw.substring(at + 1)}';
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return '(无法解析)';
  return uri.host;
}

String _makeNonce() {
  // 去掉 0/O、1/I 这类会看错的字形：这串字符是要人拿去在手机上对的。
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(5, (_) => alphabet[r.nextInt(alphabet.length)]).join();
}
