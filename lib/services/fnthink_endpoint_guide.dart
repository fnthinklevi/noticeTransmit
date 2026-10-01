import 'package:fnthink_push/fnthink_push.dart';

/// 接入端点「怎么调用」那一格的**唯一作者**（T87）。
///
/// 做成一个纯函数而不是页面里的几行字符串，是因为这一格里同时压着三条红线，
/// 而它们都必须能在没有设备、没有网络的情况下被判红：
///
///  ① **路径只有契约那一份作者**。教程里重打一遍 `/api/fnthink/p/…`，服务器换前缀时
///    界面会安静地教一条 404 的路径 —— 那副表现是"幻念推送坏了"，而断的只是这段文案。
///    两条路径都从 `endpoint.ingress` 读（`postBearerPath` 与 `pathPattern`）。
///  ② **口令只在「这一次创建」的内存里活着**。[copyCommand] 只在调用方手上确实有那枚明文时
///    才非 null；为了按钮常亮而把它存起来，就是破页面那句"这一把只出现一次"（同一条红线，
///    不是两条）。所以"能不能复制"这件事的判据也住在这里，页面只读 [canCopyCommand]。
///  ③ **GET 那一支永远只给形状**：口令写在路径段里 ⇒ 它必然进反代 access log，而本站日志
///    脱敏（T89）还没配。所以 [getShape] 里是 `<secret>` 占位，且**不产出可复制的 GET 命令** ——
///    多一个复制点就是多一条把凭证写进别人终端历史的路。POST 那支的口令在请求头里，才给整条复制。
class FnthinkEndpointGuide {
  const FnthinkEndpointGuide({
    required this.postUrl,
    required this.getShape,
    required this.titleAliases,
    required this.bodyAliases,
    this.copyCommand,
  });

  /// [secret] 传进来 = 页面手上还有这一次明文；不传/传空 = 只能给形状与占位符。
  /// [endpointId] 为空（用户只是读了一遍列表）时，两条 URL 都用 `<endpointId>` 占位 ——
  /// 形状照样讲得清，但**不会**产出一条可整行复制的命令（见 [canCopyCommand]）。
  factory FnthinkEndpointGuide.from({
    required String host,
    required String endpointId,
    String? secret,
    required FnthinkContract contract,
  }) {
    final base = host.trim();
    final id = endpointId.trim();
    final postPath = contract
        .endpointIngressPath('postBearerPath')
        .replaceAll(':endpointId', id.isEmpty ? '<endpointId>' : id);
    // 形状里就是占位符：这一支不给可复制的真命令（见类注释 ③）。
    final shapePath = contract
        .endpointIngressPath('pathPattern')
        .replaceAll(':endpointId', '<endpointId>')
        .replaceAll(':secret', '<secret>');
    final held = secret?.trim();
    final copyable = id.isNotEmpty && held != null && held.isNotEmpty;
    final postUrl = base.isEmpty ? '' : 'https://$base$postPath';
    return FnthinkEndpointGuide(
      postUrl: postUrl,
      getShape: base.isEmpty ? '' : 'https://$base$shapePath?title=…&body=…',
      titleAliases: contract.aliases['title'] ?? const [],
      bodyAliases: contract.aliases['body'] ?? const [],
      copyCommand: (copyable && postUrl.isNotEmpty)
          ? "curl -X POST '$postUrl'"
                " -H 'Authorization: Bearer $held'"
                " -H 'Content-Type: application/json'"
                " -d '{\"title\":\"…\",\"body\":\"…\"}'"
          : null,
    );
  }

  /// POST 那条的网址（口令不进 URL，只进请求头）。地址或 id 缺一个就是空串 ——
  /// 空串让页面知道"这一格现在没法给真东西"，而不是给一条拼了一半的假地址。
  final String postUrl;

  /// GET 的**形状**（永远带 `<endpointId>` / `<secret>` 占位）。
  final String getShape;

  final List<String> titleAliases;
  final List<String> bodyAliases;

  /// 整条可复制的命令：只有页面手上还有口令明文时才存在。
  final String? copyCommand;

  /// 「一键复制」能不能按 —— 判据住在这儿，页面不许自己再判一次空串。
  bool get canCopyCommand => copyCommand != null;
}
