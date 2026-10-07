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
///  ③ **可复制的 GET 命令永远不产**：口令写在路径段里 ⇒ 它必然进反代 access log，而本站日志
///    脱敏（T89）还没配。所以 [getShape] 里是 `<secret>` 占位，且**不产出可复制的 GET 命令** ——
///    多一个复制点就是多一条把凭证写进别人终端历史的路。POST 那支的口令在请求头里，才给整条复制。
///    ⚠ 这一条管的是"别替人按下 GET"，不是"路径形态不许出现"：`pathPattern` 是契约声明的两种
///    POST 形态之一，所以 [pushUrl] 给（门槛同 [copyCommand]），代价写在界面那句话里。
class FnthinkEndpointGuide {
  const FnthinkEndpointGuide({
    required this.postUrl,
    required this.getShape,
    required this.pushUrl,
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
    // 路径形态的**真**链接：作者仍是契约的 `pathPattern`，只是把两个占位换成手上那一份
    // 明文（与上面 shapePath 同一来源，这里不重打一遍路径字符串）。明文不在手就回空串，
    // 页面据此置灰 —— 给一条拼了一半的假地址比不给更糟。
    final realPath = copyable
        ? contract
              .endpointIngressPath('pathPattern')
              .replaceAll(':endpointId', id)
              .replaceAll(':secret', held)
        : '';
    final pushUrl = (base.isEmpty || realPath.isEmpty)
        ? ''
        : 'https://$base$realPath';
    return FnthinkEndpointGuide(
      postUrl: postUrl,
      getShape: base.isEmpty ? '' : 'https://$base$shapePath?title=…&body=…',
      pushUrl: pushUrl,
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

  /// **推送地址**（路径形态，口令在最后一段）：`https://<host>/api/fnthink/p/<id>/<secret>`。
  ///
  /// 这一条是给"别的软件只有一个 webhook 输入框、发不了请求头"用的 —— Bearer 形态那条
  /// 它们用不上（T99，维护者 2026-10-07：「要能作为通用 webhook 链接让其他软件快速消息发送」）。
  ///
  /// ⚠ 门槛与 [copyCommand] **同一个**：只有页面手上还留着那枚明文时才给。这不是新增一条
  ///   泄露面 —— 同一格里本来就有「复制口令」，把 id 与口令分两次复制和复制一条拼好的
  ///   字符串，落到剪贴板上的东西是一样的。真正的差别只有一句：**口令进了 URL 就会进
  ///   反代 access log**，而那件事的处置权在部署侧（日志脱敏 = T89），不在这一格。
  ///   所以路径形态照契约给（`pathPattern` 是协议声明的两种形态之一，`postOnly` 只拒 GET
  ///   不拒 POST），但只在明文还活着的那一刻给，且不给 GET 形态的真链接（见类注释 ③）。
  final String pushUrl;

  /// 「一键复制」能不能按 —— 判据住在这儿，页面不许自己再判一次空串。
  bool get canCopyCommand => copyCommand != null;

  /// 推送地址能不能复制 —— 同上，判据不在页面里再写一份。
  bool get canCopyPushUrl => pushUrl.isNotEmpty;
}
