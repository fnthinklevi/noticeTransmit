import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_rule.dart';

/// 规则模板库（P2）。
///
/// - [presetTemplates]：内置模板（验证码优先 / 营销拦截 / 夜间免打扰 / 社交聚合 /
///   白名单直通），覆盖常见的规则配置场景；
/// - 用户模板：从现有规则「存为模板」持久化到 SharedPreferences；
/// - 导出/分享：模板集合写入 `.json` 文件；填写口令时用与配置备份同源的
///   PBKDF2(210k) + AES-256-GCM 加密（格式 `notice-rules-enc`），不填则明文
///   （模板仅含条件/动作，无任何凭据，明文分享零门槛）。
class RuleTemplateService {
  static const formatPlain = 'notice-rules';
  static const formatEncrypted = 'notice-rules-enc';
  static const formatVersion = 1;
  static const _userTemplatesKey = 'user_rule_templates';

  // ── 内置模板 ──────────────────────────────────────────────────────────

  /// 内置模板（id 由导入时生成，name 唯一性由列表展示保证）
  static List<NotificationRule> presetTemplates() => [
    NotificationRule(
      id: 'tpl_preset_code',
      name: '验证码优先推送',
      description: '标题或内容包含「验证码/校验码/verification code」的通知以最高优先级立即推送',
      priority: 100,
      conditions: [
        Condition(
          id: 'c1',
          type: ConditionType.contentContains,
          value: '验证码',
          logic: LogicOperator.or,
        ),
        Condition(
          id: 'c2',
          type: ConditionType.contentContains,
          value: '校验码',
          logic: LogicOperator.or,
        ),
        Condition(
          id: 'c3',
          type: ConditionType.contentContains,
          value: 'verification code',
          logic: LogicOperator.or,
        ),
      ],
      actions: [RuleAction(id: 'a1', type: ActionType.push)],
    ),
    NotificationRule(
      id: 'tpl_preset_marketing',
      name: '营销广告拦截',
      description: '命中常见营销词（优惠/促销/抢购/返现/红包/秒杀）的通知静默忽略，不再打扰',
      priority: 50,
      conditions: [
        Condition(
          id: 'c1',
          type: ConditionType.contentContains,
          value: '优惠',
          logic: LogicOperator.or,
        ),
        Condition(
          id: 'c2',
          type: ConditionType.contentContains,
          value: '促销',
          logic: LogicOperator.or,
        ),
        Condition(
          id: 'c3',
          type: ConditionType.contentContains,
          value: '抢购',
          logic: LogicOperator.or,
        ),
        Condition(
          id: 'c4',
          type: ConditionType.contentContains,
          value: '返现',
          logic: LogicOperator.or,
        ),
        Condition(
          id: 'c5',
          type: ConditionType.contentContains,
          value: '秒杀',
          logic: LogicOperator.or,
        ),
      ],
      actions: [RuleAction(id: 'a1', type: ActionType.silent)],
    ),
    NotificationRule(
      id: 'tpl_preset_dnd',
      name: '夜间免打扰',
      description: '22:00–07:00 之间的全部通知静默忽略（白天不受影响）',
      priority: 200,
      conditions: [
        Condition(
          id: 'c1',
          type: ConditionType.timeRange,
          value: '22:00-07:00',
        ),
      ],
      actions: [RuleAction(id: 'a1', type: ActionType.silent)],
    ),
    NotificationRule(
      id: 'tpl_preset_social_merge',
      name: '社交消息聚合',
      description: '微信/QQ 群消息按 60 秒窗口聚合，满 5 条提前推送一次，避免连发轰炸',
      priority: 40,
      conditions: [
        Condition(
          id: 'c1',
          type: ConditionType.packageName,
          value: 'com.tencent.mm',
          logic: LogicOperator.or,
        ),
        Condition(
          id: 'c2',
          type: ConditionType.packageName,
          value: 'com.tencent.mobileqq',
          logic: LogicOperator.or,
        ),
      ],
      actions: [
        RuleAction(
          id: 'a1',
          type: ActionType.merge,
          params: {'delaySeconds': 60, 'maxItems': 5},
        ),
      ],
    ),
    NotificationRule(
      id: 'tpl_preset_whitelist_push',
      name: '白名单关键词直通',
      description: '标题含「白名单」的通知高优先级立即推送（配合通知过滤常用于服务上线提醒）',
      priority: 90,
      conditions: [
        Condition(id: 'c1', type: ConditionType.titleContains, value: '白名单'),
      ],
      actions: [RuleAction(id: 'a1', type: ActionType.push)],
    ),
  ];

  // ── 用户模板持久化 ────────────────────────────────────────────────────

  Future<List<NotificationRule>> getUserTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userTemplatesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => NotificationRule.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 存为模板：追加（同名覆盖，避免重复堆积）
  Future<void> saveUserTemplate(NotificationRule rule) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (await getUserTemplates())
        .where((t) => t.name != rule.name)
        .toList();
    list.add(
      NotificationRule(
        id: 'tpl_user_${rule.id}',
        name: rule.name,
        description: rule.description,
        priority: rule.priority,
        conditions: rule.conditions,
        actions: rule.actions,
      ),
    );
    await prefs.setString(
      _userTemplatesKey,
      jsonEncode(list.map((r) => r.toMap()).toList()),
    );
  }

  Future<void> deleteUserTemplate(String templateId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (await getUserTemplates())
        .where((t) => t.id != templateId)
        .toList();
    await prefs.setString(
      _userTemplatesKey,
      jsonEncode(list.map((r) => r.toMap()).toList()),
    );
  }

  /// 导入模板 → 生成新 id（避免与既有规则主键冲突）、默认启用
  List<NotificationRule> instantiate(List<NotificationRule> templates) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return List.generate(templates.length, (i) {
      final t = templates[i];
      return NotificationRule(
        id: 'rule_${ts}_$i',
        name: t.name,
        description: t.description,
        enabled: true,
        priority: t.priority,
        conditions: t.conditions
            .map(
              (c) => Condition(
                id: 'c${i}_${c.id}',
                type: c.type,
                value: c.value,
                logic: c.logic,
              ),
            )
            .toList(),
        actions: t.actions
            .map(
              (a) => RuleAction(
                id: 'a${i}_${a.id}',
                type: a.type,
                params: a.params,
              ),
            )
            .toList(),
      );
    });
  }

  // ── 导出 / 导入 ───────────────────────────────────────────────────────

  /// 导出为可分享文件内容。[password] 非空时 AES-256-GCM 加密（与配置备份同源算法）。
  Future<String> buildExportContent(
    List<NotificationRule> templates,
    String? password,
  ) async {
    final payload = {'templates': templates.map((r) => r.toMap()).toList()};
    if (password == null || password.isEmpty) {
      return jsonEncode({
        'format': formatPlain,
        'version': formatVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        ...payload,
      });
    }
    return jsonEncode(await _encrypt(payload, password));
  }

  /// 解析导入内容：自动识别明文/加密格式；加密时需提供口令。
  /// 抛 [FormatException]（文件无效）或 [TemplateDecryptException]（口令错误）。
  Future<List<NotificationRule>> parseImportContent(
    String content,
    String? password,
  ) async {
    final dynamic root = jsonDecode(content);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('不是有效的模板文件');
    }
    List<dynamic> raw;
    switch (root['format']) {
      case formatPlain:
        raw = root['templates'] as List? ?? const [];
      case formatEncrypted:
        if (password == null || password.isEmpty) {
          throw const TemplatePasswordRequired();
        }
        final payload = await _decrypt(root, password);
        raw = payload['templates'] as List? ?? const [];
      default:
        throw const FormatException('不是有效的模板文件');
    }
    return raw
        .whereType<Map>()
        .map((e) => NotificationRule.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── 加密原语（与 BackupService 同源：PBKDF2 210k + AES-256-GCM）──────

  final _aes = AesGcm.with256bits();
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );
  final _random = Random.secure();

  Future<Map<String, dynamic>> _encrypt(
    Map<String, dynamic> data,
    String password,
  ) async {
    final salt = Uint8List.fromList(
      List.generate(16, (_) => _random.nextInt(256)),
    );
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key,
    );
    return {
      'format': formatEncrypted,
      'version': formatVersion,
      'kdf': {
        'algorithm': 'PBKDF2-HMAC-SHA256',
        'iterations': 210000,
        'salt': base64Encode(salt),
      },
      'cipher': 'AES-256-GCM',
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
  }

  Future<Map<String, dynamic>> _decrypt(
    Map<String, dynamic> container,
    String password,
  ) async {
    final kdf = container['kdf'] as Map<String, dynamic>?;
    if (kdf == null || container['ciphertext'] == null) {
      throw const FormatException('加密容器结构无效');
    }
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64Decode(kdf['salt'] as String),
    );
    try {
      final clear = await _aes.decrypt(
        SecretBox(
          base64Decode(container['ciphertext'] as String),
          nonce: base64Decode(container['nonce'] as String),
          mac: Mac(base64Decode(container['mac'] as String)),
        ),
        secretKey: key,
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw const TemplateDecryptException('口令错误或文件已损坏');
    }
  }
}

class TemplatePasswordRequired implements Exception {
  const TemplatePasswordRequired();
}

class TemplateDecryptException implements Exception {
  final String message;
  const TemplateDecryptException(this.message);
}
