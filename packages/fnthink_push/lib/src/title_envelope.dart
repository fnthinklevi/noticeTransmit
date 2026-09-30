import 'dart:convert';

import 'contract.dart';

/// 拆出来的标题与正文。
class FnthinkTitleContent {
  const FnthinkTitleContent({
    required this.title,
    required this.body,
    required this.split,
  });

  final String title;
  final String body;

  /// 这一次**真的**拆开了吗。false = 整段就是正文（没有前缀，或前缀后面不是合法信封）。
  ///
  /// 留这一个布尔而不是"拆不出来就返回空标题"：调用方要能分清「这条本来就没有标题」与
  /// 「这条看起来有信封但读不懂」。后一种是编码或契约漂了，静默当没有标题处理，
  /// 症状就是标题一夜之间全空了而没有任何一条报错。
  final bool split;
}

/// 设备这一路的**标题信封**（§4 第 10 条定稿：不动 `signature.canonicalOrder`，标题放进已签的 body）。
///
/// 为什么要有这个东西：`canonicalOrder` 里没有 `title`，而服务端只收「出现在已签字节里」的标题
/// （**整段比对**，见 `server/lib/fnthink/routes.js`）。所以设备在顶层另附的 `title` 一定被丢掉，
/// 收件人看到的是一句没有标题的正文 —— 那是「不静默丢」的反面：字段进去了，出来时没了。
/// 把标题放进 `body` 之后，能改标题的人本来就能改整条消息（同一段签字节），
/// 攻击面没有变大，而「未签内容上屏」那个口子仍然不开。
///
/// ⚠ 三个值全部从契约读（`deviceSend.titleEnvelope`）。在代码里写死前缀就是第二个真值来源：
/// 换 v1→v2 时发出去的一串与收件端拆的那一串不是同一串，而症状是「标题没了」。
class FnthinkTitleEnvelope {
  /// 编码成要签、要发出去的 `body`。
  ///
  /// 空标题**不套信封**：套了就是给收件端留一个「有信封而标题为空」的形状，
  /// 而那种形状与「这条本来没有标题」在拆完之后不可区分。
  static String encode(
    FnthinkContract contract, {
    required String title,
    required String body,
  }) {
    if (title.isEmpty) return body;
    final payload = <String, String>{
      contract.deviceTitleKey: title,
      contract.deviceBodyKey: body,
    };
    return contract.deviceTitlePrefix + jsonEncode(payload);
  }

  /// 拆一段线上 `body`。拆不出来 ⇒ `split=false`、整段当正文（**不猜**）。
  ///
  /// 四种情况都算"拆不出来"：没有前缀、前缀后面不是 JSON、解出来不是对象、
  /// 那两个键缺一个或不是字符串。共同点是绝不返回"猜出来的标题" ——
  /// 把正文第一行升级成标题，正是这条信封要防的那种表现。
  static FnthinkTitleContent decode(FnthinkContract contract, String wire) {
    final prefix = contract.deviceTitlePrefix;
    if (!wire.startsWith(prefix)) {
      return FnthinkTitleContent(title: '', body: wire, split: false);
    }
    final titleKey = contract.deviceTitleKey;
    final bodyKey = contract.deviceBodyKey;
    final Object? parsed;
    try {
      parsed = jsonDecode(wire.substring(prefix.length));
    } on FormatException {
      return FnthinkTitleContent(title: '', body: wire, split: false);
    }
    if (parsed is! Map) {
      return FnthinkTitleContent(title: '', body: wire, split: false);
    }
    final title = parsed[titleKey];
    final body = parsed[bodyKey];
    if (title is! String || body is! String) {
      return FnthinkTitleContent(title: '', body: wire, split: false);
    }
    return FnthinkTitleContent(title: title, body: body, split: true);
  }

  /// 收件端那一刀：**只有已签的标题为空时**才用信封（契约
  /// `deviceSend.titleEnvelope.onlyWhenSignedTitleEmpty`，validate 钉着它必须是 true）。
  ///
  /// 已签的那一份是权威的。让正文里的信封盖掉它，等于未签内容覆盖已签内容 ——
  /// 这条协议在 `item`、`title`、`level` 上都拒过同一件事。
  static FnthinkTitleContent unwrap({
    required FnthinkContract contract,
    required String signedTitle,
    required String wireBody,
  }) {
    if (signedTitle.isNotEmpty) {
      return FnthinkTitleContent(
        title: signedTitle,
        body: wireBody,
        split: false,
      );
    }
    return decode(contract, wireBody);
  }
}
