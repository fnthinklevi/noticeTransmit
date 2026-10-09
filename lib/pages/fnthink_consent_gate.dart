/// 「内容真的会经服务器走」的四类动作**共用**的那一道同意门（T118）。
///
/// 维护者 2026-10-09 拍的范围（四条全拦）：
///  ① 建／换／撤接入端点；② 发起配对与批准配对；③ 幻念通道的创建／启用与「发一条」；
///  ④ 手动测试里**会带正文**的那一发（通道详情页的「仅探测」）。
/// **不拦**（刻意划在外面，理由写在下面）：非浸入探针（签名面 `/probe` 与端点干跑 —— 它们
/// 一个字段都不读、一条都不投，拦它等于把"同意之前先看看通不通"这条自检路弄死）、
/// 收件箱读取、本地历史与统计。
///
/// 为什么要有这一道（而不是只靠服务层那道）：
/// `FnthinkReceiveCoordinator._resolveSpec` 已经是硬门（缺同意 ⇒ `not-consented`），但它出现在
/// **点了之后** —— 用户照着一句"先同意"去翻页面，而入口本身看起来完全可用。这一道把话说在
/// 点击那一刻，并且**取消就一个字节都不写**。
///
/// 三条口径：
///  - **不给"自动续跑"**：用户从同意页回来之后，这里返回 `false`，调用方什么都不做。
///    续跑意味着"在别的页读完说明"之后替他执行掉上一步那次点击 —— 而批准配对、撤销端点
///    这些动作本身还带二次确认，自动执行等于把"为这一发做决定"这件事从用户手里拿走。
///  - **弹层只说规则，不说结果**：不许出现"已发送／已建好"这类既成事实的措辞 ——
///    事实是**什么都还没发生**。
///  - **拿不到同意状态就拦**（fail-closed）：读不到契约或 prefs 时返回 false，
///    不猜"大概同意过了"（那正是 T56 立这道门时反对的形状）。
library;

import 'package:flutter/cupertino.dart';

import '../l10n/app_localizations.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_settings.dart';
import '../widgets/ios_dialog_actions.dart';
import 'fnthink_receive_page.dart';

/// 拿不到页面自己那份 settings 时用的读口。**不查 GetIt**：这个模块在 widget 测试里也要能跑，
/// 而测试未必装过 service locator；契约是随包资源（pubspec 的 assets 那一行），测试里读得到。
/// 装载器自带缓存，所以这里是"第一次点才读一次资源"。
final FnthinkContractLoader _contractLoader = FnthinkContractLoader();

/// 测试替换口 —— **只为测试存在**，生产装配永远走下面那条默认读口。
///
/// 为什么必须有它：widget 测试跑在假时钟里，`rootBundle` 那种真 IO 的 future **不会完成**
/// （不报错、也不挂断用例，表现是"点了没反应、断言说那一发没发生"），而这一族的页面用例
/// 必须能过门去做它自己那件事。测试在 `setUp` 里塞一份同步读出来的契约即可：
/// `debugFnthinkConsentSettingsOverride = FnthinkSettings(contract: FnthinkContract.readFile());`
@visibleForTesting
FnthinkSettings? debugFnthinkConsentSettingsOverride;

Future<FnthinkSettings?> _settingsFromBundle() async {
  final preset = debugFnthinkConsentSettingsOverride;
  if (preset != null) return preset;
  try {
    return FnthinkSettings(contract: await _contractLoader.load());
  } catch (_) {
    return null;
  }
}

/// 打开同意入口那一页（`FnthinkReceivePage`）—— 门这一处与 hub 那一行都指向同一页。
Future<void> openFnthinkConsentPage(BuildContext context) {
  return Navigator.of(
    context,
  ).push(CupertinoPageRoute<void>(builder: (_) => const FnthinkReceivePage()));
}

/// 返回 `true` = 已同意过（放行，调用方照原样往下走）；
/// 返回 `false` = 没同意（或用户取消了）—— **调用方什么都不做**。
///
/// [action] 是那一发的人话名字（例如「建一把接入端点」），进弹层正文；不给就用一句通用的。
Future<bool> requireFnthinkRelayConsent(
  BuildContext context, {
  FnthinkSettings? settings,
  String? action,
}) async {
  final target = settings ?? await _settingsFromBundle();
  if (target == null) return false;
  if (await target.hasRelayConsent()) return true;
  if (!context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  final go = await IosDialogActions.askConfirm(
    context,
    title: l10n.fnthinkConsentGateTitle,
    message: l10n.fnthinkConsentGateMsg(
      action ?? l10n.fnthinkConsentGateThisStep,
    ),
    confirmText: l10n.fnthinkConsentGateGo,
    // 这不是破坏性动作：确认键走"默认"色，而取消键永远在左边、永远是那条"什么都不做"的路。
    destructive: false,
  );
  if (!go || !context.mounted) return false;
  await openFnthinkConsentPage(context);
  return false;
}
