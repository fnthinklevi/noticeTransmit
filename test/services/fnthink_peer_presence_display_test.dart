import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/l10n/app_localizations_en.dart';
import 'package:notice_transmit/l10n/app_localizations_zh.dart';
import 'package:notice_transmit/services/fnthink_peer_presence_display.dart';

/// T156 片2：那一行的**显示作者**。
///
/// 这里不判在线/离线（服务端的三态是唯一作者），只钉三件事：
///  ① 在线/离线都把服务端算好的秒数拿来分档，**不出现 Xms**；
///  ② `unknown` 说"还没上过线"、不在返回集合里说"对方没共享"——两句都不许画成"离线"；
///  ③ 读取失败时每行不编状态，只在卡片级说一句带原因原话的话。
void main() {
  late FnthinkContract contract;
  setUp(() => contract = FnthinkContract.readFile());

  const peer = 'PEER00000000000001';

  final zh = AppLocalizationsZh();
  final en = AppLocalizationsEn();

  FnthinkPeerPresenceResult ok(List<FnthinkPeerPresence> rows) =>
      FnthinkPeerPresenceResult(
        status: FnthinkPollStatus.ok,
        peers: rows,
        signedWhileUncalibrated: false,
      );

  ({FnthinkPeerPresenceKind kind, int? ageSeconds}) view({
    required FnthinkPeerPresenceResult? result,
    bool loading = false,
    String address = peer,
  }) => fnthinkPeerPresenceView(
    contract: contract,
    result: result,
    loading: loading,
    peerAddress: address,
  );

  test('在线/离线都用服务端秒数分档，不出现 Xms', () {
    final online = fnthinkPeerPresenceLine(
      zh,
      view(
        result: ok(const [
          FnthinkPeerPresence(
            addressCode: peer,
            presence: 'online',
            lastSeenAt: 1,
            ageSeconds: 12,
          ),
        ]),
      ),
    );
    expect(online, '在线 · 上次收取 12 秒前');
    expect(online, isNot(contains('ms')));

    final offline = fnthinkPeerPresenceLine(
      zh,
      view(
        result: ok(const [
          FnthinkPeerPresence(
            addressCode: peer,
            presence: 'offline',
            lastSeenAt: 1,
            ageSeconds: 90,
          ),
        ]),
      ),
    );
    expect(offline, '离线 · 上次收取 1 分钟前');
  });

  test('unknown 说还没上过线，不说离线', () {
    final line = fnthinkPeerPresenceLine(
      zh,
      view(
        result: ok(const [
          FnthinkPeerPresence(addressCode: peer, presence: 'unknown'),
        ]),
      ),
    );
    expect(line, '未知 · 还没上过线');
    expect(line, isNot(contains('离线')));
  });

  test('不在返回集合里 = 对方没共享，不说离线', () {
    final line = fnthinkPeerPresenceLine(zh, view(result: ok(const [])));
    expect(line, '对方没有共享在线状态');
    expect(line, isNot(contains('离线')));
  });

  test('读取失败每行不编状态，卡片级那句带原因原话', () {
    const failed = FnthinkPeerPresenceResult(
      status: FnthinkPollStatus.failed,
      reason: 'peer-presence-http:404',
      signedWhileUncalibrated: false,
    );
    expect(fnthinkPeerPresenceLine(zh, view(result: failed)), isNull);
    expect(
      fnthinkPeerPresenceFailedLine(zh, 'peer-presence-http:404'),
      contains('404'),
    );
    expect(
      fnthinkPeerPresenceFailedLine(en, 'peer-presence-http:404'),
      contains('404'),
    );
  });

  test('加载中整张名单共用一句', () {
    final v = view(result: null, loading: true);
    expect(v.kind, FnthinkPeerPresenceKind.loading);
    expect(fnthinkPeerPresenceLine(zh, v), fnthinkPeerPresenceLoadingLine(zh));
    expect(fnthinkPeerPresenceLoadingLine(en), isNot(contains('正在')));
  });

  test('英文那一句也走同一把尺', () {
    final line = fnthinkPeerPresenceLine(
      en,
      view(
        result: ok(const [
          FnthinkPeerPresence(
            addressCode: peer,
            presence: 'online',
            lastSeenAt: 1,
            ageSeconds: 12,
          ),
        ]),
      ),
    );
    expect(line, 'Online · last fetch 12s ago');
  });
}
