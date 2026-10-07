import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_endpoint_guide.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/fnthink_card.dart';
import '../widgets/ios_dialog_actions.dart';
import '../widgets/primary_action_button.dart';

/// 这一页的依赖（T97 片B：从混合页那一格里抽出来）。
///
/// 只要契约与协调者两样：端点的建/读/关/换全走设备面签名事件，而教程那两个
/// 网址的作者是契约。地址码、身份、健康度探测都不在这一页的职责里 ——
/// 依赖表少一项，测试里就多一项"这一页确实没碰它"。
class FnthinkEndpointDeps {
  FnthinkEndpointDeps({required this.contracts, required this.coordinator});

  factory FnthinkEndpointDeps.fromLocator() => FnthinkEndpointDeps(
    contracts: GetIt.instance<FnthinkContractLoader>(),
    coordinator: GetIt.instance<FnthinkReceiveCoordinator>(),
  );

  final FnthinkContractLoader contracts;
  final FnthinkReceiveCoordinator coordinator;
}

/// 接入端点页（T42 第七片建、#157 读/关/换、T87 教程；T97 片B 独立成页）。
///
/// 为什么它值得有一页（维护者 2026-10-07 拍）：它是**机器对机器**的入口 ——
/// 应用内没有任何一条路径需要它，它却占着原来那张混合页的第一屏；它的口令是一次性的、
/// 轮换还带宽限期，放在日常页里迟早有人误点轮换然后回不来。
/// ⚠ 边界：它是外部服务推进来的**唯一**入口 ⇒ 那一行必须一眼可见、可搜到，
///   不做折叠三层（页首那句"多数人不需动这里"是说明，不是把它藏起来）。
///
/// ⚠ 这一页刻意没有的东西：
///  - **改服务器地址**：地址住在设置那一页，这一页只**读**它来拼推送地址。
///    两处都能改就是两个作者，而换地址还要重启收货循环（`_applyHost` 那条纪律）。
///  - **口令的第二份副本**：见 `_endpoint` 与 `_endpointRotated` 的注释。
class FnthinkEndpointPage extends StatefulWidget {
  const FnthinkEndpointPage({super.key, this.deps});

  final FnthinkEndpointDeps? deps;

  @override
  State<FnthinkEndpointPage> createState() => _FnthinkEndpointPageState();
}

class _FnthinkEndpointPageState extends State<FnthinkEndpointPage> {
  late final FnthinkEndpointDeps _deps;
  late final FnthinkReceiveCoordinator _coordinator;

  /// 契约不可用的原话。非空时整页只显示这一条：上限那个数与教程那条路径都只有一份作者
  /// （契约），拿不到契约还让人建入口，等于让他抄一份说不出含义的地址。
  String? _contractError;

  /// 教程与契约读到的那一份（读不到时整页已经只显示错误了）。
  FnthinkContract? _contract;

  /// 这一台当前对着的那台服务器，**只读**（拼推送地址用）。坏值按空处理 ⇒ 地址整条不给，
  /// 而不是拼半条（改它不在这一页）。
  String _host = '';

  /// 刚建好的那条接入端点。**口令只在这里活这么长**：页面不把它写进 prefs、不写进表、
  /// 不拼进任何日志 —— 这一格存在的目的就是让用户当场抄走，抄不到就重新建一把。
  /// （留一份"方便回去再看"的副本是这个功能最容易做错的形状：那等于把长期凭证存进
  ///  一个会跟着备份走、又不加密的地方，而服务端那边只存了摘要，谁都不知道丢了什么。）
  FnthinkEndpointCreateResult? _endpoint;

  /// 「我建过哪些入口」那一次读的结论（null = 这一页还没读过）。
  /// ⚠ 这一份**不持久化**，也不与 `_endpoint` 合成一个东西：口令是一次性的、这份是每次读重来的，
  /// 两者放一起的下场是"重新读一次把刚拿到的口令覆盖掉"，而那份口令本来就只有这一次。
  /// 端点表在服务端，本机不留副本 —— 留了就是一本会漂的账（那边吊销了，这本还写着在用）。
  FnthinkEndpointListResult? _endpointList;

  /// 最近一次"关掉一把入口"的结论（null = 这一页还没关过）。
  /// 与名单那一格同一个道理：结论必须经得起回去再看一眼，不能弹个 toast 就消失 ——
  /// 而这里更需要，因为**关掉之后列表里那一行还在**（只是不再收信），
  /// 没有这句结论，用户看不出那一行是自己刚关的还是一早就停的。
  FnthinkEndpointRevokeResult? _endpointRevoked;

  /// 最近一次"换口令"的结论（null = 这一页还没换过）。
  /// ⚠ 与 `_endpoint` 同一条红线：它带着**只出现一次的新明文口令**，所以不落盘、不进日志；
  /// 页面关掉这一格就是它消失的时候（换过一次而没抄走，只能再换一次 —— 旧那把会跟着进宽限期）。
  FnthinkEndpointRotateResult? _endpointRotated;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _deps = widget.deps ?? FnthinkEndpointDeps.fromLocator();
    _coordinator = _deps.coordinator;
    unawaited(_load());
  }

  Future<void> _load() async {
    final FnthinkContract contract;
    try {
      contract = await _deps.contracts.load();
    } on FnthinkContractUnavailable catch (e) {
      if (mounted) setState(() => _contractError = e.reason);
      return;
    }
    String host;
    try {
      host = await FnthinkSettings(contract: contract).host;
    } on FnthinkSettingsInvalid {
      // 备份恢复可能灌回来一个坏值。这一页不改它（改地址住在设置那一页），
      // 但也不能拿它拼地址：空 ⇒ 教程里那两枚复制按钮置灰。
      host = '';
    }
    if (!mounted) return;
    setState(() {
      _contract = contract;
      _host = host;
    });
  }

  /// 建一条接入端点（T42 第七片那一发）。名字用本地化里那句默认外号，这里**不给输入框**：
  /// 这一发的价值全在"回一把只出现一次的口令"，外号是管理面那列可以以后改的东西，
  /// 而为一个非关键输入开一个弹层，就把这个页面变成了表单生命周期那类事故的发生地。
  Future<void> _createEndpoint() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await _coordinator.createEndpoint(
      name: l10n.fnthinkEndpointDefaultName,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _endpoint = result;
    });
    // 建成之后，这一格**已经读过**的话立刻重读：留着"2 把"显示而实际是 3 把，与留着"3 把"
    // 而实际是 2 把说的是同一句假话，只是方向反了。还没读过就**不凭空开始读** ——
    // 那一支的界面该说的是"还没看过"，不是刚编出来的一份列表。
    if (result.ok && _endpointList != null) await _readEndpoints();
  }

  /// 读一次"这台设备名下有哪几把入口"（`/endpoint-list`，#157 第二片）。
  ///
  /// 只有按这一下才读：**不在 `initState` 里读**。那一刻服务地址与本机身份还没就位，
  /// 读回来的多半是一句失败，而界面会把"还没法读"画成屏幕上第一句话 —— 用户第一次翻开
  /// 这一格看到的反而是错误。空着并写着"还没看过"才是那一刻的真话。
  Future<void> _readEndpoints() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await _coordinator.listEndpoints();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _endpointList = result;
    });
  }

  /// 关掉一把入口（`/endpoint-revoke`，#157 第四片）。
  ///
  /// 按 T06 那条规矩：**关掉一个东西一律二次确认**，而弹层释放之后才发那一发。
  /// 确认之后要做的事只有一件 —— 把结论记下来，然后**重新读一次列表**：
  /// 屏幕跟上服务端，而不是自己把那一行就地画灰（本机若有一份"我把它标成停了"的账，
  /// 下一次读之前它就是唯一的一份真值，而那份真值可能是错的）。
  /// 还没读过就不重读：没看过的东西不凭空生成一份列表（与 `_createEndpoint` 同一条口径）。
  ///
  /// 这一格被砸过什么（`outputs/_eprv2.report.txt` + `_eprv2b.report.txt`）：
  ///  - **SA6** `if (!ok || !mounted) return;` 摘掉（= 取消也发）⇒ 红在「弹层上点取消 ⇒ 那一发不发」。
  ///    ⚠ 这条第一次跑是 **NO FAILURE**：原来那两条只走"确定"那一支，而 `askConfirm` 本身是
  ///    await 的，摘掉早退在它们身上完全看不出来 —— 二次确认这道闸的可观察点在**取消那一路**，
  ///    于是补了这条用例再反证（不是把植入改巧一点就算完）；
  ///  - **SA7** 已停的那一行也给"关掉"按钮（`if (row.usable)` 摘掉）⇒ 红在「已经停了的那一把不再给」；
  ///  - **SA8** 关掉之后不重读 ⇒ 红在「关掉之后重读一次列表」；
  ///  - **SA9** 幂等那一句倒向"没关掉"（`if (result.revoked == false)` 摘掉）⇒
  ///    红在「那边本来就不收了 ⇒ 走成功那一路」。
  Future<void> _revokeEndpoint(FnthinkEndpointSummary row) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkEndpointRevokeAskTitle,
      message: l10n.fnthinkEndpointRevokeAskMsg(row.id),
      // 弹层里的确认键不写"关掉"：与列表里那个按钮同词时，`find.text` 一次抓到两个，
      // 而用户也分不清自己点的是"要关"还是"只是打开了弹层"。
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = await _coordinator.revokeEndpoint(endpointId: row.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _endpointRevoked = result;
    });
    if (_endpointList != null) await _readEndpoints();
  }

  /// 吊销那一发的结论。⚠ `revoked:false` 走**成功**那一路（幂等：那把本来就不收了）——
  /// 报成失败会让人再点一次，而第二次换来的还是一句 200。
  String _endpointRevokeText(AppLocalizations l10n) {
    final result = _endpointRevoked;
    if (result == null) return '';
    if (!result.ok) {
      return l10n.fnthinkEndpointRevokeFailed(
        result.reason ?? 'no-endpoint-revoke',
      );
    }
    if (result.revoked == false) {
      return l10n.fnthinkEndpointRevokeAlreadyGone(result.endpointId);
    }
    return l10n.fnthinkEndpointRevoked(result.endpointId);
  }

  /// 换那把入口的口令（`/endpoint-rotate`，#157 第六片）。
  ///
  /// 也走二次确认（T06 那条规矩的另一种情形：这一发不删东西，但它**会让一把别人正在用的口令
  /// 开始倒计时** —— 手滑的代价在 NAS 那头，与删一条通道同级）。
  /// 换完之后同样重新读一次列表：`rotatingUntil` 那一行是服务端的事实，不在本机留副本。
  ///
  /// 这一格被砸过什么（`outputs/_erot2.report.txt`，RC6–RC10 全 named+restored）：
  ///  - **RC6** 二次确认那道早退摘掉（取消也发）⇒ 红在「弹层上点取消 ⇒ 那一发不发」。
  ///    ⚠ 与 SA6 同一条教训：这条用例**必须先有"取消"那一支**才谈得上可观察，
  ///    只走"确定"的用例对 `askConfirm` 的 await 是无感的；
  ///  - **RC7** 换成那一支不再显示新口令 ⇒ 红在「新口令那一行就是这一把」；
  ///  - **RC8** `rotatingUntil` 没回也硬显示 ⇒ 红在「那一行根本不出现（不编一个截止时间）」；
  ///  - **RC9** 三档文案合一（那把已停也说成失败）⇒ 红在「说"没给它换"，不出现口令行」；
  ///  - **RC10** 已停的那一行也给两下按钮 ⇒ 红在「"关掉"与"换一把"两下都不给」。
  Future<void> _rotateEndpoint(FnthinkEndpointSummary row) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await IosDialogActions.askConfirm(
      context,
      title: l10n.fnthinkEndpointRotateAskTitle,
      message: l10n.fnthinkEndpointRotateAskMsg,
      confirmText: l10n.confirm,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = await _coordinator.rotateEndpoint(endpointId: row.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _endpointRotated = result;
    });
    if (_endpointList != null) await _readEndpoints();
  }

  /// 换口令那一发的结论。**三档必须分开说**：换成了（新口令在上面）、那一把已经不收信了
  /// （所以没换，这不是失败）、以及真失败。把第二档并进"没换成"，用户会去再点一次，
  /// 而那一发换来的是"给一个已经不工作的端点换口令" —— 一句体面的 no-op。
  String _endpointRotateText(AppLocalizations l10n) {
    final result = _endpointRotated;
    if (result == null) return '';
    if (!result.ok) {
      return l10n.fnthinkEndpointRotateFailed(
        result.reason ?? 'no-endpoint-rotate',
      );
    }
    if (result.rotated == false) {
      return l10n.fnthinkEndpointRotateNotRotated(result.endpointId);
    }
    return l10n.fnthinkEndpointRotated(result.endpointId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.fnthinkEndpointTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // 拿不到契约就只说这一条：上限那个数与教程那条路径都只有一份作者（契约）。
          // keyName 与接收页那一格同名同形：同一件"整页只剩一句错误"的事不该有两套键。
          if (_contractError != null)
            FnthinkNote(
              keyName: 'fnthink-contract-error',
              text: l10n.fnthinkContractUnavailable(_contractError!),
            )
          else
            _buildEndpointCard(l10n),
        ],
      ),
    );
  }

  /// 接入端点那一格（T42 第七片建、#157 第二片读）。
  ///
  /// 为什么这一格值得存在：以前只有管理面能建端点，自部署的用户要给自家 NAS 铸一把入口，
  /// 得先拿出那把能做远多于这件事的 admin token。
  /// 现在这一格是**建 + 读 + 关 + 换**：四件事全走设备面签名事件（self-only），
  /// 所以"我建过哪些、哪把还不收信、这把我要关掉、这把口令要换"都能在手机上说完，不必碰管理面。
  /// ⚠ 「换」与其余三件有一处根本不同：它**留下一段两把口令同时有效的时间**
  /// （契约 `endpoint.rotation.graceSeconds`）。所以界面必须把"旧的那把到什么时候算死"一起说清楚 ——
  /// 只报新口令不报截止日期，等于让人在不知道后果的情况下排自己的活儿。那一行只在服务端回了
  /// `rotatingUntil` 时出现；没回就不编。
  /// ⚠ 口令那一行只在这次 `setState` 之后存在：不写 prefs、不写表、不进日志（见 `_endpoint`）。
  /// 读回来的那份也不写：端点表的真值在服务端，本机留副本就是一本会漂的账。
  ///
  /// 这一格被砸过什么（`outputs/_endpntpeer.report.txt`）：
  ///  - **X4** 把"成功那一支"的判定从 `created.ok` 换成 `created != null` ⇒ 红在
  ///    「没建成 ⇒ 贴原话，且不出现口令行」（两支各红一条，另一支是"读不出口令"那一条）；
  ///  - **X5** 上限那句写死 `10` ⇒ 红在「上限那句里的数来自契约」。⚠ 这条用例第一版是**假绿**的：
  ///    它拿 `contract.endpointMaxPerDevice` 去比界面 —— 两边读同一个数，写死与读契约当场分不出来。
  ///    改成"喂一份 `perDeviceMax: 3` 的契约进去，断言界面说 3"，才是真的在断"读过"。
  ///  - 读那半被砸过什么（`outputs/_eplist2.report.txt`、`_eplist2b.report.txt`）：
  ///    **Z6** 建成之后不看"有没有读过"就重读 ⇒ 红在「还没读过就建一把 ⇒ 不凭空开始读」；
  ///    **Z7** `else if (!listing.ok)` 反了 ⇒ 三条一起红（"确实没有"与"这次没读到"是同一支的
  ///    两面，翻倒之后两头都在说谎）；
  ///    **Z8** 把"还没读过"那一支的 keyName 换掉 ⇒ 红在「只是翻开页面 ⇒ ...而界面说的是"还没读过"」。
  ///    ⚠ Z8 第一次的写法是 `if (false)`，那是**语法不过**（`listing` 没被提升成非空，
  ///    后面的 `listing.ok` 报 receiver 可为 null），不能读成"这条断言没覆盖"。
  Widget _buildEndpointCard(AppLocalizations l10n) {
    final created = _endpoint;
    final listing = _endpointList;
    final rotated = _endpointRotated;
    final cap = _contract?.endpointMaxPerDevice;
    return FnthinkCard(
      title: l10n.fnthinkEndpointTitle,
      children: [
        FnthinkNote(
          keyName: 'fnthink-endpoint-why',
          text: l10n.fnthinkEndpointWhy,
        ),
        if (cap != null)
          FnthinkNote(
            keyName: 'fnthink-endpoint-cap',
            text: l10n.fnthinkEndpointCap(cap),
          ),
        // 这一页的主操作（§1 判据④：一页最多一枚全宽填充）—— 「创建端点」是**做掉一件事**，
        // 而下面「读取列表」是"再看一眼"，两枚在旧写法里长得一模一样。
        PrimaryActionButton(
          key: const ValueKey('fnthink-endpoint-create'),
          label: l10n.fnthinkEndpointCreate,
          onPressed: _busy ? null : () => _createEndpoint(),
        ),
        if (created != null)
          if (created.ok) ...[
            FnthinkNote(
              keyName: 'fnthink-endpoint-id',
              text: l10n.fnthinkEndpointId(created.endpointId!),
            ),
            SelectableText(
              l10n.fnthinkEndpointSecret(created.secret!),
              key: const ValueKey('fnthink-endpoint-secret'),
            ),
            FnthinkNote(
              keyName: 'fnthink-endpoint-once',
              text: l10n.fnthinkEndpointOnce,
            ),
          ] else
            FnthinkNote(
              keyName: 'fnthink-endpoint-error',
              text: l10n.fnthinkEndpointFailed(created.reason ?? 'no-endpoint'),
            ),
        // ↓↓↓ 读的那半。三种"没有列表"必须分开说：还没读、读了但没读到、读到了确实没有。
        // 把它们合成一句"你还没有端点"，用户就会在第一次读失败那天下 NAS 的定时任务。
        Align(
          alignment: Alignment.centerLeft,
          child: FnthinkInlineAction(
            key: const ValueKey('fnthink-endpoint-read'),
            label: l10n.fnthinkEndpointListRead,
            onPressed: _busy ? null : _readEndpoints,
          ),
        ),
        if (listing == null)
          FnthinkNote(
            keyName: 'fnthink-endpoint-list-pending',
            text: l10n.fnthinkEndpointListPending,
          )
        else if (!listing.ok)
          FnthinkNote(
            keyName: 'fnthink-endpoint-list-failed',
            text: l10n.fnthinkEndpointListFailed(
              listing.reason ?? 'no-endpoint-list',
            ),
          )
        else if (listing.endpoints!.isEmpty)
          FnthinkNote(
            keyName: 'fnthink-endpoint-list-none',
            text: l10n.fnthinkEndpointNone,
          )
        else
          for (final row in listing.endpoints!) ...[
            FnthinkNote(
              keyName: 'fnthink-endpoint-row-${row.id}',
              text:
                  '${row.name.isEmpty ? l10n.fnthinkEndpointRowUnnamed(row.id) : l10n.fnthinkEndpointRowNamed(row.name, row.id)}'
                  ' · '
                  '${row.usable ? l10n.fnthinkEndpointUsable : l10n.fnthinkEndpointNotUsable(row.status)}',
            ),
            // 已经不收信的那一把**不再给"关掉"或"换一把"那两下**：那一行没有可操作的东西了，
            // 而给它一个按下去只会拿到一句幂等答复的按钮，等于在界面上摆一个假动作。
            // （真要再对外提供一个入口，正确动作是上面那一下"建一个端点"。）
            if (row.usable) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FnthinkInlineAction(
                  key: ValueKey('fnthink-endpoint-revoke-${row.id}'),
                  label: l10n.fnthinkEndpointRevoke,
                  onPressed: _busy ? null : () => _revokeEndpoint(row),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FnthinkInlineAction(
                  key: ValueKey('fnthink-endpoint-rotate-${row.id}'),
                  label: l10n.fnthinkEndpointRotate,
                  onPressed: _busy ? null : () => _rotateEndpoint(row),
                ),
              ),
            ],
          ],
        if (_endpointRevoked != null)
          FnthinkNote(
            keyName: 'fnthink-endpoint-revoke-note',
            text: _endpointRevokeText(l10n),
          ),
        if (rotated != null) ...[
          // ⚠ 这两行是这一格第二处"明文只出现一次"：口令不落盘、不缓存，这一格翻过去就没了。
          // 键名刻意与创建那一次的分开（同一份 children 里两个同值 ValueKey 会直接抛）。
          if (rotated.exchanged) ...[
            SelectableText(
              l10n.fnthinkEndpointSecret(rotated.secret!),
              key: const ValueKey('fnthink-endpoint-rotated-secret'),
            ),
            FnthinkNote(
              keyName: 'fnthink-endpoint-rotated-once',
              text: l10n.fnthinkEndpointOnce,
            ),
            // "旧的那把什么时候算死"：没回就不猜 —— 编一个时间会让人按错的节奏去改 NAS。
            if (rotated.rotatingUntil != null)
              FnthinkNote(
                keyName: 'fnthink-endpoint-rotate-grace',
                text: l10n.fnthinkEndpointRotateGrace(
                  fnthinkFormatTime(rotated.rotatingUntil!),
                ),
              ),
          ],
          FnthinkNote(
            keyName: 'fnthink-endpoint-rotate-note',
            text: _endpointRotateText(l10n),
          ),
        ],
        // ── T87：怎么调用这一把（教程 + 四枚复制）──
        // 出现条件按页面既有三态判：**真用过**才给教程。`listing == null` 是"还没读"，
        // 不是"没有" —— 把"还没读"当"没有"，这一格就在用户第一次读失败那天安静消失。
        if (_endpointUsed(created, rotated, listing))
          ..._buildEndpointTutorial(l10n, created, rotated),
      ],
    );
  }

  /// 真用过 = 这一页刚建成 / 刚换过一把，或读过列表且名下确实有端点。
  /// ⚠ 三种"没有列表"里只有"读到且为空"算没用过；"还没读"与"没读到"都不把这一格点亮 ——
  ///   前者是没发生过，后者是服务器那边刚出过事，两种情况下教程都会误导人去改 NAS。
  bool _endpointUsed(
    FnthinkEndpointCreateResult? created,
    FnthinkEndpointRotateResult? rotated,
    FnthinkEndpointListResult? listing,
  ) {
    if (created?.ok ?? false) return true;
    if (rotated?.exchanged ?? false) return true;
    return listing?.ok == true && (listing?.endpoints?.isNotEmpty ?? false);
  }

  /// 教程那一格的 children（T87）。做成"一串 widget"而不是一个弹层：
  /// 口令只活在这一页的内存里，把教程挪进弹层就会让人以为"关掉弹层它还在那儿"。
  ///
  /// ⚠ 网址、命令、字段别名**一律不在这个文件里拼**：全部出自 `FnthinkEndpointGuide`
  ///   （路径与别名的唯一作者是契约）。这里重打一遍 `/api/fnthink/p/…`，服务器换前缀时
  ///   界面会安静地教一条 404 的路径。
  List<Widget> _buildEndpointTutorial(
    AppLocalizations l10n,
    FnthinkEndpointCreateResult? created,
    FnthinkEndpointRotateResult? rotated,
  ) {
    final contract = _contract;
    // 契约读不到就整格不给（不给半条地址）：路径与别名都只有一份作者，缺了就只剩猜。
    if (contract == null) return const [];
    // 手上还有口令明文的只有这两次：创建那一次、轮换那一次。列表那半永远没有。
    final createdOk = created?.ok ?? false;
    final rotatedOk = rotated?.exchanged ?? false;
    final heldId = createdOk
        ? created!.endpointId
        : (rotatedOk ? rotated!.endpointId : null);
    final heldSecret = createdOk
        ? created!.secret
        : (rotatedOk ? rotated!.secret : null);
    final guide = FnthinkEndpointGuide.from(
      host: _host,
      endpointId: heldId ?? '',
      secret: heldSecret,
      contract: contract,
    );
    Widget copyButton(String keyName, String label, String? text) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FnthinkInlineAction(
          key: ValueKey(keyName),
          label: label,
          // 这一页手上没有那一段东西 ⇒ 置灰，而不是复制一条拼了一半的假命令。
          onPressed: _busy || text == null
              ? null
              : () => fnthinkCopyNotice(context, text),
        ),
      );
    }

    return [
      FnthinkNote(
        keyName: 'fnthink-endpoint-tutorial-title',
        text: l10n.fnthinkEndpointTutorial,
      ),
      if (guide.postUrl.isNotEmpty)
        SelectableText(
          guide.postUrl,
          key: const ValueKey('fnthink-endpoint-post-url'),
        ),
      FnthinkNote(
        keyName: 'fnthink-endpoint-post-why',
        text: l10n.fnthinkEndpointPostWhy,
      ),
      // GET 那一支永远只有形状（口令进 URL ⇒ 进反代 access log；T89 未配之前不给真口令）。
      if (guide.getShape.isNotEmpty)
        SelectableText(
          guide.getShape,
          key: const ValueKey('fnthink-endpoint-get-shape'),
        ),
      FnthinkNote(
        keyName: 'fnthink-endpoint-get-warning',
        text: l10n.fnthinkEndpointGetWarning,
      ),
      // T99：给"只有一个 webhook 输入框"的第三方软件用的路径形态。门槛与 copyCommand
      // 同一个（明文不在手就整格不给），所以这一格不会比「复制口令」多泄露一个字。
      if (guide.pushUrl.isNotEmpty) ...[
        SelectableText(
          guide.pushUrl,
          key: const ValueKey('fnthink-endpoint-push-url'),
        ),
        FnthinkNote(
          keyName: 'fnthink-endpoint-push-url-why',
          text: l10n.fnthinkEndpointPushUrlWhy,
        ),
      ],
      FnthinkNote(
        keyName: 'fnthink-endpoint-fields',
        text: l10n.fnthinkEndpointFieldAlias(
          guide.titleAliases.join('、'),
          guide.bodyAliases.join('、'),
        ),
      ),
      copyButton(
        'fnthink-endpoint-copy-id',
        l10n.fnthinkEndpointCopyId,
        heldId,
      ),
      copyButton(
        'fnthink-endpoint-copy-secret',
        l10n.fnthinkEndpointCopySecret,
        heldSecret,
      ),
      copyButton(
        'fnthink-endpoint-copy-command',
        l10n.fnthinkEndpointCopyCommand,
        guide.canCopyCommand ? guide.copyCommand : null,
      ),
      copyButton(
        'fnthink-endpoint-copy-push-url',
        l10n.fnthinkEndpointCopyPushUrl,
        guide.canCopyPushUrl ? guide.pushUrl : null,
      ),
      FnthinkNote(
        keyName: 'fnthink-endpoint-copy-hint',
        text: l10n.fnthinkEndpointCopyHint,
      ),
    ];
  }
}
