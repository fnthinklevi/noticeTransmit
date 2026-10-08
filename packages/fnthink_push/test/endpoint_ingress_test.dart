import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:test/test.dart';

/// T106 片①b 格2：把一条**端点推送地址**折算成干跑那一发的纯函数（双端共读契约那两条形状）。
///
/// 这一族最值得钉的是两个方向都别错：
///  - **该探的不探** ⇒ 那条通道的徽标永远空着，用户只能手动测（回到片①b 之前的状态）；
///  - **不该探的探了** ⇒ 要么把长期口令送给了别人（第三方 host），要么变成"拿一次 401 当结论"
///    的**假红**（另一台服务器、bearer 形态、用户手敲错的位数）。
/// 所以断言一律打在契约上：路径由 `endpoint.ingress.pathPattern` 拼出来、期望的探针路径由
/// `endpoint.probe.bearerPath` 代入 —— 服务器换前缀时这些用例跟着走，而不是钉死 `/api/fnthink/p/`。
void main() {
  const host = 'push.example.com';
  // 32 位、只用契约字母表里的字符（避开 I L O U）。
  const secret = 'AB12CD34EF56GH78JK90MN23PQ45RS67';

  late FnthinkContract c;
  setUp(() => c = FnthinkContract.readFile());

  /// 按**契约那条模式**拼一条推送地址（不在测试里重打路径形状）。
  String ingress({
    FnthinkContract? contract,
    String h = host,
    String id = 'e_1',
    String sec = secret,
    String scheme = 'https',
    int extraSegments = 0,
  }) {
    final pattern = (contract ?? c).endpointIngressPath('pathPattern');
    final filled = pattern.split('/').map((s) {
      if (s == ':endpointId') return id;
      if (s == ':secret') return sec;
      return s;
    }).toList()..addAll(List.filled(extraSegments, 'extra'));
    return '$scheme://$h${filled.join('/')}';
  }

  String expectedProbePath({FnthinkContract? contract, String id = 'e_1'}) =>
      (contract ?? c).endpointProbePath().replaceAll(':endpointId', id);

  group('认得出来的那一半（该探的必须探）', () {
    test('路径形态的推送地址 ⇒ 折算出探针地址与口令，路径由契约给', () {
      final plan = fnthinkEndpointDryRunFor(
        contract: c,
        target: ingress(),
        allowedHost: host,
      );
      expect(plan, isNotNull);
      expect(plan!.secret, secret);
      expect(plan.endpointId, 'e_1');
      expect(plan.probeUrl.path, expectedProbePath());
      expect(plan.probeUrl.scheme, 'https');
      expect(plan.probeUrl.host, host);
    });

    test('口令只进请求头：折算出来的探针 URL 里**不含**那串口令', () {
      final plan = fnthinkEndpointDryRunFor(
        contract: c,
        target: ingress(),
        allowedHost: host,
      );
      expect(plan, isNotNull);
      // ⚠ 这一条是整件事的红线所在：口令一旦出现在 URL 里，它就会被 access log、浏览器历史
      //   与中间代理各留一份副本 —— 契约把干跑那一条钉成 bearer-header 就是为了这个。
      expect(plan!.probeUrl.toString(), isNot(contains(secret)));
      expect(plan.probeUrl.query, isEmpty);
    });

    test('自部署带端口 ⇒ 端口留着（丢了端口就是往 443 问一个不存在的服务）', () {
      final plan = fnthinkEndpointDryRunFor(
        contract: c,
        target: ingress(
          h: '192.168.1.10',
          id: 'e_7',
          sec: secret,
        ).replaceFirst('://192.168.1.10', '://192.168.1.10:8443'),
        allowedHost: '192.168.1.10',
      );
      expect(plan, isNotNull);
      expect(plan!.probeUrl.port, 8443);
      expect(plan.probeUrl.host, '192.168.1.10');
    });

    test('服务器换前缀 ⇒ 照样认（形状只从契约读，不在代码里写死 /api/fnthink/p/）', () {
      final moved = FnthinkContract.parse(
        jsonEncode({
          ...c.raw,
          'endpoint': {
            ...(c.raw['endpoint']! as Map<String, Object?>),
            'ingress': {
              ...(c.raw['endpoint']! as Map<String, Object?>)['ingress']!
                  as Map<String, Object?>,
              'pathPattern': '/api/fnthink/x/:endpointId/:secret',
              'postBearerPath': '/api/fnthink/x/:endpointId',
            },
            'probe': {
              ...(c.raw['endpoint']! as Map<String, Object?>)['probe']!
                  as Map<String, Object?>,
              'bearerPath': '/api/fnthink/x/:endpointId/probe',
            },
          },
        }),
      );
      final plan = fnthinkEndpointDryRunFor(
        contract: moved,
        target: ingress(contract: moved),
        allowedHost: host,
      );
      expect(plan, isNotNull, reason: '换前缀就认不出来 ⇒ 这一档的徽标从此永远空着');
      expect(plan!.probeUrl.path, expectedProbePath(contract: moved));
    });
  });

  group('认不出来的那一半（不该探的一条都不许问出去）', () {
    test('host 不是这台设备在用的那一台 ⇒ null：那是把口令送给别人', () {
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: ingress(),
          allowedHost: 'other.example.com',
        ),
        isNull,
      );
    });

    test('明文 http ⇒ null：HTTPS-only 在客户端这一侧也一步不让', () {
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: ingress(scheme: 'http'),
          allowedHost: host,
        ),
        isNull,
      );
    });

    test('POST + Bearer 形态（少一段口令）⇒ null：口令本来就不在地址里，不猜', () {
      final bearer = (c.endpointIngressPath('postBearerPath').split('/').map((
        s,
      ) {
        return s == ':endpointId' ? 'e_1' : s;
      }).toList());
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: 'https://$host${bearer.join('/')}',
          allowedHost: host,
        ),
        isNull,
        reason: '这一条通道行里没有口令 ⇒ 干跑问不成；问一次空口令只会得到一次假红',
      );
    });

    test('带 query ⇒ null（契约禁的就是"口令能放进 query"那个形状）', () {
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: '${ingress()}?title=x',
          allowedHost: host,
        ),
        isNull,
      );
    });

    test('带 fragment ⇒ null（用户从浏览器地址栏复制下来的那条不是端点地址）', () {
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: '${ingress()}#note',
          allowedHost: host,
        ),
        isNull,
      );
    });

    test('多一段 ⇒ null（那是别的服务的形状，不是我们的收单口）', () {
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: ingress(extraSegments: 1),
          allowedHost: host,
        ),
        isNull,
      );
    });

    test('前缀字面段对不上 ⇒ null（第三方 webhook 一律不探）', () {
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: 'https://$host/api/fnthink/other/e_1/$secret',
          allowedHost: host,
        ),
        isNull,
        reason: 'Slack / NAS 自己的口：协议里没有"问一句收不收得进"这一发，硬探＝真推一条',
      );
    });

    test('口令位数不对 ⇒ null（用户手敲错的地址问出去只会得到假红）', () {
      for (final bad in [secret.substring(0, 31), '${secret}X']) {
        expect(
          fnthinkEndpointDryRunFor(
            contract: c,
            target: ingress(sec: bad),
            allowedHost: host,
          ),
          isNull,
          reason:
              '位数 ${bad.length} 不是契约说的 ${c.identityLength('endpointSecret')}',
        );
      }
    });

    test('口令段按 URL 规则解**一次**：转义过的口令认，双重转义的不认', () {
      // `Uri.pathSegments` 交回来的已经是解码后的段（这是 Dart 的行为，不是这里选的）：
      // 用户从某些界面复制出来的地址可能带一层转义，解一次拿回真口令是**对的**。
      final once = fnthinkEndpointDryRunFor(
        contract: c,
        target: ingress(sec: '%41${secret.substring(1)}'),
        allowedHost: host,
      );
      expect(once, isNotNull, reason: '解一层就还原成契约位数 32 ⇒ 这一条该探');
      expect(
        once!.secret,
        secret,
        reason: '交出去的必须是**解出来**的那一份（拿编码串去当 Bearer 只会得到一次假红）',
      );
      // 但只解一次：`%2541` 解一层是 `%41`（还带百分号，位数也不对）⇒ 不认。
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: ingress(sec: '%2541${secret.substring(1)}'),
          allowedHost: host,
        ),
        isNull,
        reason: '在这里"再解一次"就是把用户的转义习惯当成口令的一部分 —— 交出去的是猜出来的串',
      );
    });

    test('空段（`//`）⇒ null', () {
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: 'https://$host/api/fnthink/p//secretvalue',
          allowedHost: host,
        ),
        isNull,
      );
    });

    test('根本不是 URL ⇒ null（不抛：调用方在遍历整族通道）', () {
      for (final junk in [
        '',
        '   ',
        'not a url',
        'https://',
        'ftp://$host/x',
      ]) {
        expect(
          fnthinkEndpointDryRunFor(
            contract: c,
            target: junk,
            allowedHost: host,
          ),
          isNull,
          reason: '脏数据不能让一整轮重探炸掉',
        );
      }
    });
  });

  group('装配那两条口子', () {
    test('endpointProbePath 缺段就抛（读不到路径不补默认值：那是往不存在的地方送口令）', () {
      final stripped = FnthinkContract.parse(
        jsonEncode({
          ...c.raw,
          'endpoint': {
            ...(c.raw['endpoint']! as Map<String, Object?>),
            'probe': null,
          },
        }),
      );
      expect(stripped.endpointProbePath, throwsStateError);
      expect(
        () => fnthinkEndpointDryRunFor(
          contract: stripped,
          target: ingress(),
          allowedHost: host,
        ),
        throwsStateError,
        reason: '折算函数不许把"契约读不到"咽成 null —— 那是装配问题，不是这条通道的问题',
      );
    });

    test('allowedHost 为空 ⇒ 一律 null（宁可全族不探，也不猜一个 host）', () {
      expect(
        fnthinkEndpointDryRunFor(
          contract: c,
          target: ingress(),
          allowedHost: '',
        ),
        isNull,
      );
    });
  });
}
