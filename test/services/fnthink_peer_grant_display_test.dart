import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/l10n/app_localizations_zh.dart';
import 'package:notice_transmit/services/fnthink_peer_grant_display.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';

/// T174：改权限那一发的结论 → 界面那一句（五种来路各说各的）。
void main() {
  final l10n = AppLocalizationsZh();

  FnthinkPeerGrantChange change({
    required FnthinkPairGrantUpdateResult result,
    bool? wrote,
    FnthinkPeerSkip? skipped,
  }) => FnthinkPeerGrantChange(result: result, wrote: wrote, skipped: skipped);

  FnthinkPairGrantUpdateResult result({
    FnthinkPollStatus status = FnthinkPollStatus.ok,
    bool? updated = true,
    String? reason,
  }) => FnthinkPairGrantUpdateResult(
    status: status,
    updated: updated,
    level: status == FnthinkPollStatus.ok ? 'L2' : null,
    items: status == FnthinkPollStatus.ok ? const [] : null,
    reason: reason,
    signedWhileUncalibrated: false,
  );

  test('成功 ⇒ 已保存', () {
    expect(
      fnthinkPeerGrantOutcomeText(l10n, change(result: result(), wrote: true)),
      l10n.fnthinkPeerGrantSaved,
    );
  });

  test('updated:false ⇒ 关系不在服务端，提示重新配对', () {
    expect(
      fnthinkPeerGrantOutcomeText(
        l10n,
        change(
          result: result(
            status: FnthinkPollStatus.failed,
            updated: false,
            reason: 'pair-grant-update-not-found',
          ),
        ),
      ),
      l10n.fnthinkPeerGrantNoRelationship,
    );
  });

  test('404/405 ⇒ 服务器版本旧（不把"没这扇门"说成网络失败）', () {
    for (final code in const ['404', '405']) {
      expect(
        fnthinkPeerGrantOutcomeText(
          l10n,
          change(
            result: result(
              status: FnthinkPollStatus.failed,
              updated: null,
              reason: 'pair-grant-update-http:$code',
            ),
          ),
        ),
        l10n.fnthinkPeerGrantMissingRoute,
      );
    }
  });

  test('服务端认了但本机没写成 ⇒ 说破本机那份没更新', () {
    expect(
      fnthinkPeerGrantOutcomeText(
        l10n,
        change(
          result: result(),
          wrote: false,
          skipped: FnthinkPeerSkip.writeFailed,
        ),
      ),
      l10n.fnthinkPeerGrantLocalNotWritten,
    );
  });

  test('其余失败 ⇒ 原话（不把网络问题翻译成"没保存"）', () {
    expect(
      fnthinkPeerGrantOutcomeText(
        l10n,
        change(
          result: result(
            status: FnthinkPollStatus.transportError,
            updated: null,
            reason: 'transport:ClientException',
          ),
        ),
      ),
      l10n.fnthinkPeerGrantFailed('transport:ClientException'),
    );
  });
}
