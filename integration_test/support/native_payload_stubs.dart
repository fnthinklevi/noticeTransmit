/// 集成测试共用的**原生描述符桩**（roadmap T09-B1）。
///
/// ## 为什么要有这个文件
/// 集成测试跑在设备上，拿不到仓库里的 `channel_descriptors.json`，只能自带一份桩 ——
/// 这没问题，问题是**两份手抄**（`smoke_test.dart` 与 `release_walkthrough_test.dart`
/// 各写过一份）。抄本与原生表分叉时不会有人红：
/// - T08-B 撞过一次：载荷从裸列表改成对象，两份桩还是旧形状 ⇒ 设备上 splash 静默
///   判"描述符未就绪"，而 681 例 Dart 单测全绿；
/// - T08-C2 又撞一次：邮件页改成按描述符渲染后，桩里没有 email 族 ⇒ 闸门点不开编辑器。
/// 所以：桩只留这一份，且由 `test/architecture/native_payload_stub_test.dart`
/// 与导出快照做**逐字段深比对**（是数据比对，不是正则扫源码 —— 解析式守卫一旦锚点
/// 漂移就会静默放行，这正是本仓库反复撞到的那类失效）。
///
/// ## 为什么桩要用**真实**的 labelKey / capabilities，不用 `gateLabel*` 之类的假名
/// 旧写法给每条桩编一个不存在的资源名（`gateLabel$key`），于是闸门里看到的通道名
/// 是资源名原文 —— 那既不是用户会看到的文字，也让"描述符 ⇄ ARB"这条链路在闸门里
/// 等于没测。桩与真表唯一的合法差异是**条数**（各文件只给自己用得到的那几条）。
library;

/// 与原生 `TemplateEngine.formatOptions` 同一份档位名单（深比对会盯住它）。
const List<String> stubMessageFormats = <String>[
  'default',
  'text',
  'markdown',
  'json',
  'xml',
];

/// 钉钉群机器人 webhook。
Map<String, Object?> stubDingtalk() => _webhook(
  key: 'dingtalk',
  labelKey: 'channelTypeDingtalk',
  hosts: const <String>['oapi.dingtalk.com'],
  capabilities: const <String>['secretUsed', 'customTemplate', 'jsonContract'],
);

/// 企业微信群机器人 webhook。
Map<String, Object?> stubWechatWork() => _webhook(
  key: 'wechat_work',
  labelKey: 'channelTypeWechat',
  hosts: const <String>['qyapi.weixin.qq.com'],
  capabilities: const <String>['secretUsed', 'customTemplate', 'jsonContract'],
);

/// 企业微信自建应用。
Map<String, Object?> stubWecomApp() => _app(
  key: 'wecom_app',
  labelKey: 'channelTypeWecomApp',
  officialBase: 'https://qyapi.weixin.qq.com',
  capabilities: const <String>['secretUsed', 'markdown'],
  fields: <Map<String, Object?>>[
    _field(key: 'corpid', labelKey: 'appChannelCorpidLabel', required: true),
    _field(
      key: 'agentid',
      labelKey: 'appChannelAgentidLabel',
      kind: 'number',
      required: true,
      defaultValue: '0',
    ),
    _field(
      key: 'touser',
      labelKey: 'appChannelTouserLabel',
      defaultValue: '@all',
    ),
  ],
);

/// 邮件族（T08-C 起才有的第 15 条描述符）。
///
/// ⚠ 邮件页现在**按这份 fields 渲染表单**，而闸门 5.2 节是按位置点输入框的 ——
/// 顺序或字段数一变，点的就不是你以为点的那个框。
Map<String, Object?> stubEmail() => <String, Object?>{
  'family': 'email',
  'key': 'email',
  'labelKey': 'emailChannel',
  'iconKey': 'email',
  'hosts': const <String>[],
  'capabilities': const <String>[
    'secretUsed',
    'secretRequired',
    'secretKeepsPrevious',
    'customTemplate',
  ],
  'fields': <Map<String, Object?>>[
    _field(
      key: 'smtpHost',
      labelKey: 'smtpHost',
      kind: 'host',
      required: true,
      hintKey: 'emailHintHostExample',
    ),
    _field(
      key: 'smtpPort',
      labelKey: 'smtpPort',
      kind: 'number',
      required: true,
      defaultValue: '465',
      hintKey: 'emailHintPort',
    ),
    _field(
      key: 'useSSL',
      labelKey: 'useSSL',
      kind: 'switch',
      defaultValue: 'true',
    ),
    _field(
      key: 'username',
      labelKey: 'smtpAccount',
      kind: 'email_address',
      required: true,
      hintKey: 'emailHintAddressExample',
    ),
    _field(
      key: 'password',
      labelKey: 'smtpPassword',
      kind: 'secret',
      required: true,
      hintKey: 'emailHintPassword',
    ),
    _field(
      key: 'fromEmail',
      labelKey: 'fromEmail',
      kind: 'email_address',
      required: true,
      hintKey: 'emailHintAddressExample',
    ),
    _field(
      key: 'toEmail',
      labelKey: 'toEmail',
      required: true,
      hintKey: 'emailHintRecipients',
    ),
    _field(
      key: 'subjectTemplate',
      labelKey: 'subjectTemplate',
      hintKey: 'emailHintSubject',
      presets: <Map<String, String?>>[
        _preset('presetDefault', 'emailPresetSubjectDefault'),
        _preset('presetSimple', 'emailPresetSubjectSimple'),
        _preset('presetDetailed', 'emailPresetSubjectDetailed'),
        _preset('presetTime', 'emailPresetSubjectTime'),
        _preset('presetCode', 'emailPresetSubjectCode'),
        _preset('presetDevice', 'emailPresetSubjectDevice'),
      ],
    ),
    _field(
      key: 'bodyTemplate',
      labelKey: 'bodyTemplate',
      kind: 'multiline',
      hintKey: 'emailHintBody',
      presets: <Map<String, String?>>[
        // valueKey=null = 「清空该字段、交回原生运行时默认」，不是漏填词条
        _preset('presetDefault', null),
        _preset('presetStandard', 'emailPresetBodyStandard'),
        _preset('presetComplete', 'emailPresetBodyComplete'),
        _preset('presetCode', 'emailPresetBodyCode'),
        _preset('presetMinimal', 'emailPresetBodyMinimal'),
      ],
    ),
  ],
};

/// 组装 `getChannelDescriptors` 的答复（形状必须与生产一致：对象，两个键）。
Map<String, Object?> channelDescriptorsStub(List<Map<String, Object?>> subset) =>
    <String, Object?>{'descriptors': subset, 'messageFormats': stubMessageFormats};

Map<String, Object?> _webhook({
  required String key,
  required String labelKey,
  required List<String> hosts,
  required List<String> capabilities,
}) => <String, Object?>{
  'family': 'webhook',
  'key': key,
  'nativeType': key.toUpperCase(),
  'labelKey': labelKey,
  'iconKey': key,
  'hosts': hosts,
  'capabilities': capabilities,
  'fields': const <Map<String, Object?>>[],
  // 键集合也要与生产一致：webhook 行发 textLimitChars（可为 null），app 行发
  // officialBase，邮件行两者都不发。差一个键，Dart 侧就是"少一个字段可读"，
  // 而深比对守卫正好以此为判据。
  'textLimitChars': null,
};

Map<String, Object?> _app({
  required String key,
  required String labelKey,
  required String officialBase,
  required List<String> capabilities,
  required List<Map<String, Object?>> fields,
}) => <String, Object?>{
  'family': 'app',
  'key': key,
  'nativeType': key,
  'labelKey': labelKey,
  'iconKey': key,
  'officialBase': officialBase,
  'hosts': <String>[officialBase.replaceFirst('https://', '')],
  'capabilities': capabilities,
  'fields': fields,
};

Map<String, Object?> _field({
  required String key,
  required String labelKey,
  String kind = 'text',
  bool required = false,
  String? defaultValue,
  String? hintKey,
  List<Map<String, String?>> presets = const <Map<String, String?>>[],
}) => <String, Object?>{
  'key': key,
  'labelKey': labelKey,
  'kind': kind,
  'required': required,
  'defaultValue': defaultValue,
  'hintKey': hintKey,
  'presets': presets,
};

Map<String, String?> _preset(String labelKey, String? valueKey) => {
  'labelKey': labelKey,
  'valueKey': valueKey,
};
