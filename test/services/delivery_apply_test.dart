import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/notification_service.dart';

/// `NotificationService.applyDelivery` 纯函数契约。
///
/// 该函数原先是内存命中分支与 DB 兜底分支各抄一份的同构逻辑，仅靠注释维系同步；
/// 抽出一个入口后，这里锁定四种回传形态的语义，防止再次分叉。
///
/// 键由 `kotlinType` 经 `channelDeliveryKey` 推导，**不是调用方传入的参数**：
/// 参数化就会让"回传类型"与"写入键"各自漂移（历史缺陷：首页写
/// `'自建应用:企微'` 而键是显示名，两套字符串永不相等）。
void main() {
  Map<String, dynamic> pending() => {
    'chan:dingtalk': {'status': 'pending', 'message': ''},
    'chan:email': {'status': 'pending', 'message': ''},
  };

  group('applyDelivery – 普通通道', () {
    test('只更新自己那条键，保留其他通道状态', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'WECHAT_WORK',
        existing: pending(),
        normalized: 'success',
        message: 'ok',
      );

      expect(out.keys, containsAll(['chan:dingtalk', 'chan:email']));
      expect(out['chan:wechat_work'], {'status': 'success', 'message': 'ok'});
      // 未被本次回传触及的通道保持原状（不得被误覆盖成 success）
      expect((out['chan:dingtalk'] as Map)['status'], 'pending');
      expect((out['chan:email'] as Map)['status'], 'pending');
    });

    test('existing 为空时仍建出该键的终态', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'EMAIL',
        existing: <String, dynamic>{},
        normalized: 'failed',
        message: '550 拒收',
      );
      expect(out, {
        'chan:email': {'status': 'failed', 'message': '550 拒收'},
      });
    });

    test('同一通道的不同拼写落在同一个键（不会分裂出第二项）', () {
      // 原生回传枚举名、DB 存的是 snake_case、v11 前记录里是本地化显示名
      for (final raw in [
        'DINGTALK',
        'dingtalk',
        'webhook:钉钉',
        'chan:dingtalk',
      ]) {
        final out = NotificationService.applyDelivery(
          kotlinType: raw,
          existing: pending(),
          normalized: 'success',
          message: 'ok',
        );
        expect(out.length, 2, reason: '$raw 不应新增第二个钉钉键');
        expect(out['chan:dingtalk'], {'status': 'success', 'message': 'ok'});
      }
    });
  });

  group('applyDelivery – 拦截伪通道', () {
    test('FILTER 把全部真实通道统一置为 intercepted（不沿用回传的 normalized）', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'FILTER',
        existing: pending(),
        normalized: 'failed',
        message: '命中黑名单关键词',
      );
      expect(out['chan:dingtalk'], {
        'status': 'intercepted',
        'message': '命中黑名单关键词',
      });
      expect(out['chan:email'], {
        'status': 'intercepted',
        'message': '命中黑名单关键词',
      });
      // 不新开 chan:blocked 项：真实通道必须转终态，否则历史永远「发送中」
      expect(out.containsKey('chan:blocked'), isFalse);
    });

    test('SMS 与 FILTER 同语义（两者规范键同为 blocked）', () {
      for (final raw in ['SMS', 'FILTER']) {
        final out = NotificationService.applyDelivery(
          kotlinType: raw,
          existing: pending(),
          normalized: 'failed',
          message: '短信被拦截',
        );
        expect(
          out.values.every((v) => (v as Map)['status'] == 'intercepted'),
          isTrue,
          reason: raw,
        );
      }
    });

    test('无真实通道时以 chan:blocked 建占位', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'FILTER',
        existing: <String, dynamic>{},
        normalized: 'failed',
        message: '应用过滤',
      );
      expect(out, {
        'chan:blocked': {'status': 'intercepted', 'message': '应用过滤'},
      });
    });
  });

  group('applyDelivery – 聚合伪通道（MERGE）', () {
    test('成功：全部通道转 success（文案由上层映射为「已合并推送」）', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'MERGE',
        existing: pending(),
        normalized: 'success',
        message: '已合并推送',
      );
      expect(out['chan:dingtalk'], {'status': 'success', 'message': '已合并推送'});
      expect(out['chan:email'], {'status': 'success', 'message': '已合并推送'});
    });

    test('⚠ 失败必须保留失败态：写死 success 即重演「假成功丢内容」缺陷', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'MERGE',
        existing: pending(),
        normalized: 'failed',
        message: '网络连接失败',
      );
      expect(out['chan:dingtalk'], {'status': 'failed', 'message': '网络连接失败'});
      expect(out['chan:email'], {'status': 'failed', 'message': '网络连接失败'});
    });

    test('existing 为空时以回传状态建占位，不静默丢弃', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'MERGE',
        existing: <String, dynamic>{},
        normalized: 'failed',
        message: '无可用通道',
      );
      expect(out['chan:merge'], {'status': 'failed', 'message': '无可用通道'});
    });
  });

  // T12 补充：主备路由降级时，历史记录要看得出"这条是备用通道发的"。
  // 标记写在**单个通道条目**上（不是记录级布尔），因为送达结果是逐通道回来的。
  group('applyDelivery – 备用标记（T12 降级投递）', () {
    test('降级轮次的结果只给该通道打标记', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'EMAIL',
        existing: pending(),
        normalized: 'success',
        message: 'ok',
        viaBackup: true,
      );
      expect(out['chan:email'], {
        'status': 'success',
        'message': 'ok',
        'viaBackup': true,
      });
      // 未被本轮触及的通道不得被顺带标上备用
      expect(out['chan:dingtalk'], {'status': 'pending', 'message': ''});
    });

    test('未降级的轮次不写这个键（不给多数记录存一个 false）', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'EMAIL',
        existing: pending(),
        normalized: 'success',
        message: 'ok',
      );
      expect(
        out['chan:email'],
        isNot(contains('viaBackup')),
        reason: '缺键即"没走备用"；写 false 会让历史 JSON 每行多一个字段',
      );
    });

    test('标记粘滞：后到的成功结果不得抹掉「当时走过备用」', () {
      // 真实时序：备用通道首发失败 → 重放队列稍后补一次成功，
      // 重放结果不带轮次上下文（viaBackup=false）。若允许覆盖，
      // 用户回看历史就看不出这条消息当初是降级发的。
      final first = NotificationService.applyDelivery(
        kotlinType: 'EMAIL',
        existing: pending(),
        normalized: 'failed',
        message: '超时',
        viaBackup: true,
      );
      final again = NotificationService.applyDelivery(
        kotlinType: 'EMAIL',
        existing: first,
        normalized: 'success',
        message: '重放成功',
      );
      expect(again['chan:email'], {
        'status': 'success',
        'message': '重放成功',
        'viaBackup': true,
      });
    });

    test('聚合伪通道展开时，逐通道保留各自已有的标记', () {
      final existing = <String, dynamic>{
        'chan:dingtalk': {'status': 'pending', 'message': ''},
        'chan:email': {'status': 'pending', 'message': '', 'viaBackup': true},
      };
      final out = NotificationService.applyDelivery(
        kotlinType: 'MERGE',
        existing: existing,
        normalized: 'success',
        message: '已合并推送',
      );
      expect(out['chan:dingtalk'], {'status': 'success', 'message': '已合并推送'});
      expect(out['chan:email'], {
        'status': 'success',
        'message': '已合并推送',
        'viaBackup': true,
      });
    });

    test('聚合轮次本身走了备用时，成员的全部通道一起标上', () {
      final out = NotificationService.applyDelivery(
        kotlinType: 'MERGE',
        existing: pending(),
        normalized: 'success',
        message: '已合并推送',
        viaBackup: true,
      );
      expect(out['chan:dingtalk']['viaBackup'], true);
      expect(out['chan:email']['viaBackup'], true);
    });
  });
}
