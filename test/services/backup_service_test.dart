import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:notice_transmit/services/backup_service.dart';

void main() {
  late BackupService service;

  /// 满足字段级要求的最小可备份配置
  Map<String, dynamic> sampleData() => {
    'webhookChannels': [
      {
        'id': 'ch1',
        'name': '企微',
        'url': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=k',
        'type': 'WECHAT_WORK',
        'secret': 's3cret',
        'enabled': true,
      },
    ],
    'emailChannels': [
      {
        'id': 'em1',
        'host': 'smtp.example.com',
        'port': 465,
        'username': 'a@b.com',
        'password': 'p@ss',
      },
    ],
    'notificationRules': [
      {
        'id': 'r1',
        'name': '验证码',
        'enabled': true,
        'priority': 10,
        'conditions': [],
        'actions': [],
      },
    ],
    'smsSettings': {
      'sms_monitor_enabled': true,
      'sms_code_monitor_enabled': true,
      'sms_sim_filter': 'all',
    },
    'appFilter': {
      'mode': 'allow',
      'packages': ['com.a', 'com.b'],
    },
    'blacklistKeywords': ['广告'],
    'whitelistKeywords': ['验证码'],
    // N5 v2 新增三类
    'battery': {
      'notify_enabled': true,
      'rules': [
        {
          'id': 'charging',
          'type': 'charging',
          'value': 0,
          'enabled': true,
          'title': '开始充电',
        },
      ],
    },
    'deviceName': '我的设备',
    'preferences': {'theme_mode': 'dark', 'app_language': 'zh'},
  };

  /// v1 旧备份 payload：不含 N5 新增三类（电池/设备名/偏好）
  Map<String, dynamic> sampleV1Data() {
    final data = sampleData()
      ..remove('battery')
      ..remove('deviceName')
      ..remove('preferences');
    return data;
  }

  setUp(() {
    service = BackupService();
  });

  group('encryptBackup / decryptBackup 往返', () {
    test('加密后解密还原原始数据（嵌套结构保真）', () async {
      final data = sampleData();
      final container = await service.encryptBackup(data, 'password123');
      final restored = await service.decryptBackup(container, 'password123');
      expect(restored, data);
    });

    test('文件头携带 KDF 参数与算法标识', () async {
      final container = await service.encryptBackup(
        sampleData(),
        'password123',
      );
      expect(container['format'], BackupService.formatId);
      expect(container['version'], BackupService.formatVersion);
      expect(container['createdAt'], isA<String>());
      expect(container['cipher'], 'AES-256-GCM');
      final kdf = container['kdf'] as Map<String, dynamic>;
      expect(kdf['algorithm'], 'PBKDF2-HMAC-SHA256');
      expect(kdf['iterations'], BackupService.kdfIterations);
      // 16 字节盐 base64
      expect(base64Decode(kdf['salt'] as String).length, 16);
      // 12 字节 GCM nonce
      expect(base64Decode(container['nonce'] as String).length, 12);
      expect(base64Decode(container['mac'] as String).isNotEmpty, isTrue);
    });

    test('两次加密相同数据产出不同盐/nonce（随机化）', () async {
      final c1 = await service.encryptBackup(sampleData(), 'password123');
      final c2 = await service.encryptBackup(sampleData(), 'password123');
      expect(c1['nonce'] != c2['nonce'], isTrue);
      expect((c1['kdf'] as Map)['salt'] != (c2['kdf'] as Map)['salt'], isTrue);
    });

    test('解密按容器内 salt 派生（不同 salt 的容器均可解）', () async {
      final c1 = await service.encryptBackup(sampleData(), 'password123');
      final c2 = await service.encryptBackup(sampleData(), 'password123');
      expect(await service.decryptBackup(c1, 'password123'), sampleData());
      expect(await service.decryptBackup(c2, 'password123'), sampleData());
    });
  });

  group('口令与篡改防护', () {
    test('错误口令抛 SecretBoxAuthenticationError', () async {
      final container = await service.encryptBackup(
        sampleData(),
        'password123',
      );
      expect(
        () => service.decryptBackup(container, 'wrongpass1'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('密文被篡改抛 SecretBoxAuthenticationError（GCM 完整性）', () async {
      final container = await service.encryptBackup(
        sampleData(),
        'password123',
      );
      final cipherText = base64Decode(container['ciphertext'] as String);
      cipherText[0] ^= 0xFF;
      container['ciphertext'] = base64Encode(cipherText);
      expect(
        () => service.decryptBackup(container, 'password123'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('口令过短抛 FormatException', () async {
      expect(
        () => service.encryptBackup(sampleData(), 'short'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => service.decryptBackup(sampleData(), 'short'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('validateContainer 容器结构校验', () {
    test('合法容器通过', () async {
      final container = await service.encryptBackup(
        sampleData(),
        'password123',
      );
      expect(() => service.validateContainer(container), returnsNormally);
    });

    test('format 不符拒绝', () {
      expect(
        () => service.validateContainer({'format': 'other'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('版本不支持拒绝', () {
      expect(
        () => service.validateContainer({
          'format': BackupService.formatId,
          'version': 99,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('KDF 算法不符拒绝', () {
      expect(
        () => service.validateContainer({
          'format': BackupService.formatId,
          'version': 1,
          'kdf': {'algorithm': 'ARGON2'},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺少密文字段拒绝', () {
      expect(
        () => service.validateContainer({
          'format': BackupService.formatId,
          'version': 1,
          'kdf': {'algorithm': 'PBKDF2-HMAC-SHA256'},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('validatePayload 字段级校验', () {
    test('非 https webhook 被跳过并计数', () {
      final (fixed, skipped) = service.validatePayload({
        'webhookChannels': [
          {'url': 'https://good.example.com/hook'},
          {'url': 'http://bad.example.com/hook'},
          {'url': 'ftp://worse.example.com/f'},
        ],
      });
      expect(skipped, 2);
      expect((fixed['webhookChannels'] as List).length, 1);
      expect(
        (fixed['webhookChannels'] as List).first['url'],
        'https://good.example.com/hook',
      );
    });

    test('webhookChannels 非列表时归一为空列表', () {
      final (fixed, skipped) = service.validatePayload({
        'webhookChannels': 'garbage',
      });
      expect(skipped, 0);
      expect(fixed['webhookChannels'], isEmpty);
    });
  });

  group('N5 schema v2 与 v1 兼容', () {
    test('v2 容器（version=2）通过校验', () async {
      final container = await service.encryptBackup(
        sampleData(),
        'password123',
      );
      expect(container['version'], 2);
      expect(() => service.validateContainer(container), returnsNormally);
    });

    test('v1 旧容器（version=1）仍可校验与解密（向后兼容）', () async {
      final container = await service.encryptBackup(
        sampleV1Data(),
        'password123',
      );
      // 强制把容器版本标回 v1（模拟旧版本 App 产出的备份）
      container['version'] = 1;
      expect(() => service.validateContainer(container), returnsNormally);
      final restored = await service.decryptBackup(container, 'password123');
      expect(restored, sampleV1Data());
      expect(restored.containsKey('battery'), isFalse);
      expect(restored.containsKey('preferences'), isFalse);
    });

    test('v1 payload（无新三类字段）通过字段级校验且原样保留', () {
      final (fixed, skipped) = service.validatePayload(sampleV1Data());
      expect(skipped, 0);
      expect(fixed.containsKey('battery'), isFalse);
      expect(fixed.containsKey('preferences'), isFalse);
    });

    test('v2 往返保真：新三类字段加密解密后逐字段一致', () async {
      final data = sampleData();
      final container = await service.encryptBackup(data, 'password123');
      final restored = await service.decryptBackup(container, 'password123');
      expect(restored['battery'], data['battery']);
      expect(restored['deviceName'], data['deviceName']);
      expect(restored['preferences'], data['preferences']);
    });
  });
}
