/// 推送模板变量名单（Dart 侧唯一一份）。
///
/// 为什么需要这一份：变量真正的替换发生在原生 —— webhook/应用通道走
/// `TemplateEngine.render`，邮件走 `EmailSender.applyTemplate`，**两者支持的变量集不同**
/// （邮件侧有 `%type% %date% %datetime% %postTime%`，webhook 侧有
/// `%notifyType% %simInfo% %sender% %phoneNumber% %durationStr% %callState% %timestamp%
/// 以及聚合用的 `%count% %titles%`）。此前这份名单在四个地方各抄一遍：原生两张表、
/// webhook 模板提示行、邮件编辑器 `availableVars` 文案 —— 抄本必然漂移，实测就是
/// `%count% %titles% %postTime%` 从来没出现在任何界面里，用户不知道能用；
/// 反过来界面上写了的变量若原生不支持，插入后只会原样留在正文里。
///
/// 名单与原生两张表的**一致性由 `test/architecture/template_vars_contract_test.dart`
/// 逐 token 双向核对**（跨语言源码守卫，与 `channel_identity_contract_test` 同一手法）。
/// 新增变量时改三处：原生替换函数、这里、以及（可选）`common` 标记。
class TemplateVar {
  const TemplateVar(this.token, {this.common = false});

  /// 占位符本体，不带百分号（渲染时是 `%token%`）。
  final String token;

  /// 是否值得作为"点一下就插入"的快捷按钮展示（true ⇒ 高频且对任何通知都有意义）。
  final bool common;
}

/// webhook / 自建应用通道：`TemplateEngine.render` 支持的变量。
const List<TemplateVar> webhookTemplateVars = [
  TemplateVar('appName', common: true),
  TemplateVar('title', common: true),
  TemplateVar('content', common: true),
  TemplateVar('subText'),
  TemplateVar('time', common: true),
  TemplateVar('deviceName', common: true),
  TemplateVar('packageName'),
  TemplateVar('notifyType', common: true),
  TemplateVar('simInfo'),
  TemplateVar('sender'),
  TemplateVar('phoneNumber'),
  TemplateVar('durationStr'),
  TemplateVar('callState'),
  TemplateVar('timestamp'),
  // F3 聚合推送：非聚合时渲染成空串，所以模板里用了也不会在普通推送里留垃圾。
  TemplateVar('count'),
  TemplateVar('titles'),
];

/// 邮件通道：`EmailSender.applyTemplate` 支持的变量（与上面**不是**同一份）。
const List<TemplateVar> emailTemplateVars = [
  TemplateVar('appName', common: true),
  TemplateVar('title', common: true),
  TemplateVar('content', common: true),
  TemplateVar('subText', common: true),
  TemplateVar('packageName', common: true),
  TemplateVar('deviceName', common: true),
  TemplateVar('time', common: true),
  TemplateVar('postTime'),
  TemplateVar('type', common: true),
  TemplateVar('date'),
  TemplateVar('datetime'),
];

/// 提示行用的完整列表：`%appName% %title% …`
String templateVarTokens(List<TemplateVar> vars) =>
    vars.map((v) => '%${v.token}%').join(' ');

/// 快捷插入按钮用的子集（保持声明顺序）。
List<TemplateVar> commonTemplateVars(List<TemplateVar> vars) =>
    vars.where((v) => v.common).toList(growable: false);
