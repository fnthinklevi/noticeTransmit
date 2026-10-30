import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receive_loop.dart';

/// T218：SSE 静默时那一发短轮询的判据。
///
/// 判的是"路径还答不答话"，不是"这一轮有没有取到货"：任何契约层响应
/// （含 429／401／409 这类业务结论）都说明中间层没断；只有 transport 失败
/// 才是真离线。`signing-unavailable` 是本地钥匙问题，不许拿它判死门铃。
void main() {
  FnthinkLoopReport report(
    FnthinkPollStatus status, {
    String? reason,
    bool skipped = false,
  }) => FnthinkLoopReport(status: status, reason: reason, skipped: skipped);

  test('服务端答话的各类结论 ⇒ 路径可达（degraded，不是 offline）', () {
    for (final status in const [
      FnthinkPollStatus.ok,
      FnthinkPollStatus.rateLimited,
      FnthinkPollStatus.rejectedUnsigned,
      FnthinkPollStatus.replayed,
      FnthinkPollStatus.needsCalibration,
    ]) {
      expect(
        fnthinkStreamProbeSucceeded(report(status)),
        isTrue,
        reason: '$status 说明请求到了服务端 ⇒ 门铃静默更可能是被中间层吞了',
      );
    }
  });

  test('transport 失败 ⇒ 真离线', () {
    expect(
      fnthinkStreamProbeSucceeded(report(FnthinkPollStatus.transportError)),
      isFalse,
    );
  });

  test('failed：本地签名不可用不算离线；HTTP/未知失败算离线', () {
    expect(
      fnthinkStreamProbeSucceeded(
        report(FnthinkPollStatus.failed, reason: 'signing-unavailable'),
      ),
      isTrue,
      reason: '钥匙问题与门铃健康是两件事，不许拿它把门铃判死',
    );
    expect(
      fnthinkStreamProbeSucceeded(
        report(FnthinkPollStatus.failed, reason: 'http:554'),
      ),
      isFalse,
    );
    expect(
      fnthinkStreamProbeSucceeded(report(FnthinkPollStatus.failed)),
      isFalse,
    );
  });

  test('整轮被跳过（有在途轮次）⇒ 没探成不等于离线', () {
    expect(
      fnthinkStreamProbeSucceeded(
        report(
          FnthinkPollStatus.failed,
          reason: 'round-in-progress',
          skipped: true,
        ),
      ),
      isTrue,
    );
  });
}
