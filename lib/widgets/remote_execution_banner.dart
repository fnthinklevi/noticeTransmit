import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../l10n/app_localizations.dart';
import '../services/fnthink_remote_runner.dart';

/// 远程执行的**界面顶端横幅**（契约 `delay.cancelChannels` 里的 `inAppBanner`）。
///
/// ## 它为什么必须是「撤销」而不是「确认」
/// 契约 `l3.confirmForm = cancelableDelay`：窗口是**撤销机会**，不是确认。
/// 于是这一格只画一句话 + 一个撤销按钮 —— 画成「确认/取消」两枚按钮的话，
/// 用户看到的承诺就变成了"我要逐条点头才执行"，而协议根本没要求那一下。
///
/// ## 它为什么**每秒**自己重画
/// 倒计时停在 3 秒不动，用户会以为窗口过了却还留着「撤销」——
/// 而那一下按下只会回一句"撤不回来"。所以它自己按秒走，
/// 走到 0 时 runner 那边已经动手了，横幅随即消失（撤不回来就不该再给按钮）。
///
/// ⚠ **不自己判"该不该消失"**：这一格只渲染 [RemoteCommandRunner.pendingAt] 的读数。
///   倒计时到 0 之后那一条会不会真的从工作集里出去，是执行链的事；
///   横幅自己算一遍就变成第二个读者，而两处各算一次就会有一处过期。
class RemoteExecutionBanner extends StatefulWidget {
  const RemoteExecutionBanner({
    super.key,
    required this.runner,
    required this.clock,
    this.onCancelled,
  });

  final RemoteCommandRunner runner;
  final DateTime Function() clock;

  /// 撤销成功/失败都经这一个回调（页面用它给一句反馈）。
  final void Function(bool cancelled)? onCancelled;

  @override
  State<RemoteExecutionBanner> createState() => _RemoteExecutionBannerState();
}

class _RemoteExecutionBannerState extends State<RemoteExecutionBanner>
    with SingleTickerProviderStateMixin {
  /// 那一拍一拍往前走的那个（**每帧**，不是每秒一次 Timer）。
  ///
  /// ⚠ 为什么是 [Ticker] 而不是 `Timer.periodic`：
  ///   ① 一个独立于帧的 Timer 在 widget 测试结束时会留下 "A Timer is still pending"
  ///      —— 于是每一条用例都得记得手动卸载 widget tree，而**忘了的那一条**
  ///      会红成一条与被测物毫无关系的失败；
  ///   ② Ticker 由 widget 树自己驱动：这一格不在屏幕上了它就不走，
  ///      不用谁记得去 cancel（`SingleTickerProviderStateMixin` 在 dispose 里替你做）。
  late final Ticker _ticker = createTicker((_) {
    if (mounted) setState(() {});
  });

  /// 撤销之后那一句反馈（**几秒后自己消失**）。
  ///
  /// ⚠ 为什么不能什么都不说：撤销是这个窗口里用户**唯一**能做的动作，
  /// 而按完之后横幅直接消失 —— 那用户分不清「我撤成功了」与「它自己跑完了」。
  /// 而这两种情况下界面上看起来一模一样（都只是一条横幅不见了）。
  String? _feedback;

  /// 只在**真有东西在等、或刚给过反馈**的时候才让它走。
  ///
  /// ⚠ 常驻一个每帧醒一次的东西只为等一条一年可能来一次的指令，是持续的耗电；
  /// 所以它在 pending 空且反馈过期的那一刻就停。
  void _syncTicker(bool keepTicking) {
    if (keepTicking && !_ticker.isActive) {
      _ticker.start();
    } else if (!keepTicking && _ticker.isActive) {
      _ticker.stop();
    }
  }

  /// 反馈留几秒（够读完，不至于一直挂着）。
  static const _feedbackSeconds = 4;
  DateTime _feedbackUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    // ⚠ Ticker 必须**先停再交给 super**：带着 active 的 Ticker 被 dispose 时
    //   `SingleTickerProviderStateMixin` 会当场抛（那正是它拦住"忘了停"的那一声），
    //   而窗口期结束不代表这一格已经离开屏幕。
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _cancel(String execId) async {
    final l10n = AppLocalizations.of(context);
    final ok = await widget.runner.cancel(execId);
    widget.onCancelled?.call(ok);
    if (!mounted) return;
    // ⚠ 撤不掉时也**说清楚**，而不是让用户以为撤销成功 ——
    //   那一格要么是"动作可能做完了一半"，要么是"已经进到执行里去了"。
    setState(() {
      _feedback = ok ? l10n.remoteExecCancelled : l10n.remoteExecCancelTooLate;
      _feedbackUntil = DateTime.now().add(
        const Duration(seconds: _feedbackSeconds),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // ⚠ 监听执行链而不是每秒问一次：只 poll 的话，指令到达后横幅要等下一拍才出现，
    //   而那 1 秒正是用户最想按它的时刻（`run()` 里 `notifyListeners()` 是即时的）。
    return ListenableBuilder(
      listenable: widget.runner,
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final pending = widget.runner.pendingAt(widget.clock());
    final feedback =
        _feedback != null && widget.clock().isBefore(_feedbackUntil)
        ? _feedback
        : null;
    _syncTicker(pending.isNotEmpty || feedback != null);
    if (pending.isEmpty && feedback == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: pending.isEmpty
              ? Text(feedback!, style: Theme.of(context).textTheme.bodyMedium)
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.remoteExecPendingBanner(
                          pending.first.item,
                          pending.first.remainingSeconds,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _cancel(pending.first.execId),
                      child: Text(l10n.remoteExecCancel),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
