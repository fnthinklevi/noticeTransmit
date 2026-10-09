import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../models/fnthink_channel.dart';
import 'fnthink_channel_service.dart';
import 'fnthink_contract_loader.dart';
import 'fnthink_endpoint_send.dart';
import 'fnthink_settings.dart';

/// 「Webhook 通道」这一组的一枚目标（T122）。
///
/// 与「已配对设备」那种目标的区别就写在字段上：这一枚带的是**地址**（端点口令在地址最后一段里），
/// 设备那一枚带的是**地址码**（关系与档位住在那台中转机上）。
class FnthinkWebhookTarget {
  const FnthinkWebhookTarget({
    required this.channelId,
    required this.name,
    required this.target,
  });

  final String channelId;

  /// 用户给这条通道起的名字（界面上显示的就是它 —— 地址那一串不适合当标签）。
  final String name;

  /// 通道里存的那条推送地址（`https://…/p/<id>/<secret>`）。
  final String target;
}

/// 这一档的目标读口：幻念通道里 **`targetKind == webhook` 且启用着**的那几条。
///
/// 只给启用的：停用一条通道的意思是"这一族别再用它往外发"，而这一格是往外发。
/// 读失败**与空名单分开**（返回 `null` = 读不出来），调用方那两句不许糊成一句。
Future<List<FnthinkWebhookTarget>?> loadFnthinkWebhookTargets({
  FnthinkChannelStore? store,
}) async {
  final source = store ?? GetIt.instance<FnthinkChannelService>();
  try {
    final rows = await source.list();
    return [
      for (final c in rows)
        if (c.enabled && c.targetKind == FnthinkChannelTarget.webhook)
          FnthinkWebhookTarget(
            channelId: c.id,
            name: c.name.isEmpty ? c.target : c.name,
            target: c.target,
          ),
    ];
  } catch (_) {
    return null;
  }
}

/// 往一条「Webhook 通道」发一条消息（T122）：算地址与发那一下都在这里收口。
///
/// 算地址用 `fnthinkEndpointMessageFor`（与端点干跑同一份判据与作者）——它认不出这条目标时
/// 这一发报 `preconditionFailed` + `not-an-endpoint-target`，**不猜也不硬发**
/// （猜出来的那一发会把长期口令送到别人主机上）。
Future<FnthinkSendResult> sendFnthinkWebhookMessage({
  required FnthinkWebhookTarget target,
  required String title,
  required String body,
  FnthinkContract? contract,
  String? host,
  Future<FnthinkSendResult> Function({
    required Uri messageUrl,
    required String secret,
    required String title,
    required String body,
  })?
  post,
}) async {
  final FnthinkContract c;
  final String h;
  try {
    c = contract ?? await GetIt.instance<FnthinkContractLoader>().load();
    h = host ?? await GetIt.instance<FnthinkSettings>().host;
  } catch (_) {
    return const FnthinkSendResult(
      status: FnthinkSendStatus.preconditionFailed,
      reason: 'contract-unavailable',
    );
  }
  final plan = fnthinkEndpointMessageFor(
    contract: c,
    target: target.target,
    allowedHost: h,
  );
  if (plan == null) {
    // 「这条不是我们的端点地址」与「它属于另一台服务器」在判据里同形（同一个 null），
    // 而这两种的下一步动作不同 —— 那句原话把两者都留给用户自己去核对。
    return const FnthinkSendResult(
      status: FnthinkSendStatus.preconditionFailed,
      reason: 'not-an-endpoint-target',
    );
  }
  final call = post ?? postFnthinkEndpointMessage;
  return call(
    messageUrl: plan.messageUrl,
    secret: plan.secret,
    title: title,
    body: body,
  );
}
