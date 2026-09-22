import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/notification_service.dart';

/// `NotificationService.applyDelivery` 纯函数契约。
///
/// 该函数原先是内存命中分支与 DB 兜底分支各抄一份的同构逻辑，仅靠注释维系同步；
/// 抽出一个入口后，这里锁定四种回传形态的语义，防止再次分叉。
void main() {
  Map<String, dynamic> pending() => {
    'webhook:钉钉': {'status': 'pending', 'message': ''},
    '邮件': {'status': 'pending', 'message': ''},
  };

  group('applyDelivery – 普通通道', () {
    test('只更新自己那条 label，保留其他通道状态', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'WECHAT_WORK',
        label: 'webhook:企业微信',
        existing: pending(),
        normalized: 'success',
        message: 'ok',
      );

      expect(out.keys, containsAll(['webhook:钉钉', '邮件']));
      expect(out['webhook:企业微信'], {'status': 'success', 'message': 'ok'});
      // 未被本次回传触及的通道保持原状（不得被误覆盖成 success）
      expect((out['webhook:钉钉'] as Map)['status'], 'pending');
      expect((out['邮件'] as Map)['status'], 'pending');
    });

    test('existing 为空时仍建出该 label 的终态', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'EMAIL',
        label: '邮件',
        existing: <String, dynamic>{},
        normalized: 'failed',
        message: '550 拒收',
      );
      expect(out, {
        '邮件': {'status': 'failed', 'message': '550 拒收'},
      });
    });
  });

  group('applyDelivery – 拦截伪通道', () {
    test('FILTER 把全部真实通道统一置为 intercepted（不沿用回传的 normalized）', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'FILTER',
        label: '过滤拦截',
        existing: pending(),
        normalized: 'failed',
        message: '命中黑名单关键词',
      );
      expect(out['webhook:钉钉'], {
        'status': 'intercepted',
        'message': '命中黑名单关键词',
      });
      expect(out['邮件'], {'status': 'intercepted', 'message': '命中黑名单关键词'});
      expect(out.containsKey('过滤拦截'), isFalse);
    });

    test('SMS 与 FILTER 同语义', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'SMS',
        label: 'SMS',
        existing: pending(),
        normalized: 'failed',
        message: '短信被拦截',
      );
      expect(
        out.values.every((v) => (v as Map)['status'] == 'intercepted'),
        isTrue,
      );
    });
  });

  group('applyDelivery – 聚合伪通道（MERGE）', () {
    test('成功：全部通道转 success（文案由上层映射为「已合并推送」）', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'MERGE',
        label: '合并推送',
        existing: pending(),
        normalized: 'success',
        message: '已合并推送',
      );
      expect(out['webhook:钉钉'], {'status': 'success', 'message': '已合并推送'});
      expect(out['邮件'], {'status': 'success', 'message': '已合并推送'});
    });

    test('⚠ 失败必须保留失败态：写死 success 即重演「假成功丢内容」缺陷', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'MERGE',
        label: '合并推送',
        existing: pending(),
        normalized: 'failed',
        message: '网络连接失败',
      );
      expect(out['webhook:钉钉'], {'status': 'failed', 'message': '网络连接失败'});
      expect(out['邮件'], {'status': 'failed', 'message': '网络连接失败'});
    });

    test('existing 为空时以回传状态建占位，不静默丢弃', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'MERGE',
        label: '合并推送',
        existing: <String, dynamic>{},
        normalized: 'failed',
        message: '无可用通道',
      );
      expect(out['合并推送'], {'status': 'failed', 'message': '无可用通道'});
    });
  });
}
