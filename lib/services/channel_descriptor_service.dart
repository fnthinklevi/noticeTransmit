import 'package:flutter/foundation.dart';

import 'platform_channel.dart';

/// 通道配置字段声明（原生 `FieldSpec` 的 Dart 镜像）。
@immutable
class ChannelFieldSpec {
  const ChannelFieldSpec({
    required this.key,
    required this.labelKey,
    required this.kind,
    required this.required,
    this.defaultValue,
  });

  final String key;

  /// ARB 资源名（译文只在 ARB 一处）
  final String labelKey;

  /// 'text' | 'number'
  final String kind;
  final bool required;

  /// 留空时落库的值（touser=@all、receive_id_type=chat_id、agentid=0）
  final String? defaultValue;

  bool get isNumber => kind == 'number';

  factory ChannelFieldSpec.fromMap(Map<dynamic, dynamic> m) => ChannelFieldSpec(
    key: m['key']?.toString() ?? '',
    labelKey: m['labelKey']?.toString() ?? '',
    kind: m['kind']?.toString() ?? 'text',
    required: m['required'] == true,
    defaultValue: m['defaultValue']?.toString(),
  );
}

/// 单个通道描述符（原生 `ChannelRegistry` / `AppChannelRegistry` 导出的只读视图）。
@immutable
class ChannelDescriptor {
  const ChannelDescriptor({
    required this.family,
    required this.key,
    required this.labelKey,
    required this.iconKey,
    required this.capabilities,
    required this.fields,
    this.hosts = const [],
    this.textLimitChars,
    this.officialBase,
  });

  /// 'webhook' | 'app'
  final String family;

  /// 稳定标识（与 Dart 送达键 `chan:<key>`、图标 key 同一口径）
  final String key;
  final String labelKey;
  final String iconKey;

  /// 能力位（原生**派生**出来的布尔，见 `ChannelRegistry.capabilitiesOf`）
  final Set<String> capabilities;
  final List<ChannelFieldSpec> fields;
  final List<String> hosts;
  final int? textLimitChars;

  /// 应用通道的官方 API 基址（私有化部署可覆盖）
  final String? officialBase;

  bool can(String capability) => capabilities.contains(capability);

  /// secret 输入框是否显示：HMAC 签名密钥 / Bearer 令牌 / Gotify App Token 都算凭据。
  /// 原生已把这条判断从"UI 平台黑名单"变成能力位，UI 只读结果。
  bool get usesSecretField => can('secretUsed');

  /// secret 是否**必填**（缺了原生直接早失败，服务端会拒收）。
  /// 与 [usesSecretField] 是两件事：显示输入框 ≠ 非填不可（Bark 显示 key 但可以留空）。
  bool get requiresSecret => can('secretRequired');

  /// 自定义消息格式/模板对该通道是否生效（不生效时 UI 不该给入口）
  bool get supportsCustomTemplate => can('customTemplate');

  bool get supportsMarkdown => can('markdown');

  factory ChannelDescriptor.fromMap(Map<dynamic, dynamic> m) {
    final caps = (m['capabilities'] as List<dynamic>?) ?? const [];
    final fields = (m['fields'] as List<dynamic>?) ?? const [];
    return ChannelDescriptor(
      family: m['family']?.toString() ?? 'webhook',
      key: m['key']?.toString() ?? '',
      labelKey: m['labelKey']?.toString() ?? '',
      iconKey: m['iconKey']?.toString() ?? (m['key']?.toString() ?? ''),
      capabilities: caps.map((e) => e.toString()).toSet(),
      fields: fields
          .whereType<Map<dynamic, dynamic>>()
          .map(ChannelFieldSpec.fromMap)
          .toList(growable: false),
      hosts: ((m['hosts'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      textLimitChars: (m['textLimitChars'] as num?)?.toInt(),
      officialBase: m['officialBase']?.toString(),
    );
  }
}

/// 通道描述符的 Dart 侧缓存（原生 `getChannelDescriptors` 一次性拉取）。
///
/// 为什么需要它：表单字段、类型选择器、secret/模板显隐都该由**同一份**描述符驱动。
/// 此前这些事实散在 Dart 的四处硬编码列表与两份平台名单里，加一个通道要同时改
/// 原生表 + Dart 列表 + ARB，漏一处就出现"能保存但表单没有该项"。
///
/// 装载时机：splash 的装配链（必须先于任何通道页可达）。取不到时保持未就绪，
/// 页面**不得**因此把已有配置写空 —— 见 `ChannelFormRenderer.collect` 的合并语义。
class ChannelDescriptorService {
  static const _channel = AppChannels.notification;

  List<ChannelDescriptor> _all = const [];

  /// 消息格式档位（`default` / `text` / `markdown` / `json` / `xml`），与描述符同一次导出。
  ///
  /// T08-B：此前 Dart 侧另存了一份 `WebhookMessageFormat` 枚举 —— 加一个格式要改两处，
  /// 而且它把不认识的存量值**静默回退成 default**（用户只是打开设置页看了一眼，
  /// 存着的格式就被改了）。现在名单只有原生一份；未就绪时是空列表，
  /// 表单据此只显示该通道当前已存的值，不凭空造档位。
  List<String> _messageFormats = const [];
  bool _loaded = false;

  bool get isReady => _loaded;
  List<String> get messageFormats => _messageFormats;
  List<ChannelDescriptor> get all => _all;
  List<ChannelDescriptor> get webhook =>
      _all.where((d) => d.family == 'webhook').toList(growable: false);
  List<ChannelDescriptor> get appChannels =>
      _all.where((d) => d.family == 'app').toList(growable: false);

  /// 按稳定 key 查描述符（`wecom_app` / `dingtalk` / ...）；未登记返回 null。
  ChannelDescriptor? byKey(String key) {
    for (final d in _all) {
      if (d.key == key) return d;
    }
    return null;
  }

  /// 拉取并缓存。[force] 用于原生侧热更新后重取。
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      // 载荷是对象不是裸列表：`{descriptors: [...], messageFormats: [...]}`（T08-B）。
      // 两侧同包发布，所以不需要"旧形状也认"的兼容分支 —— 认了反而会掩盖真正的错配。
      final raw = await _channel.invokeMethod<Object?>('getChannelDescriptors');
      if (raw == null) return;
      if (raw is! Map) {
        debugPrint(
          '[ChannelDescriptorService] 原生载荷形状不是 Map（拿到 ${raw.runtimeType}），'
          '保留旧缓存',
        );
        return;
      }
      final descriptors = raw['descriptors'];
      if (descriptors is! List) {
        debugPrint('[ChannelDescriptorService] 载荷缺 descriptors 字段，保留旧缓存');
        return;
      }
      final parsed = descriptors
          .whereType<Map<dynamic, dynamic>>()
          .map(ChannelDescriptor.fromMap)
          .toList(growable: false);
      // 空列表不是"没配好"就是异常，任何一种都不该让表单以为"这个通道没有字段"
      if (parsed.isEmpty) {
        debugPrint('[ChannelDescriptorService] 原生返回空描述符，保留旧缓存');
        return;
      }
      _all = parsed;
      _messageFormats = ((raw['messageFormats'] as List<Object?>?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false);
      _loaded = true;
    } catch (e) {
      debugPrint('[ChannelDescriptorService] 描述符拉取失败（表单将只渲染通用字段）: $e');
    }
  }
}
