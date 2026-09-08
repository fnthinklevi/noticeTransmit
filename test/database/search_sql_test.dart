import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';

/// P1 历史搜索 SQL 构建纯函数单测。
/// 锁定 buildSearchSql 的 WHERE 拼接行为：条件组合、LIKE 转义、
/// 送达状态 JSON 粗筛（不引 JSON1 依赖）。
void main() {
  group('buildSearchSql', () {
    test('无条件时返回空 WHERE', () {
      final (where, args) = DatabaseHelper.buildSearchSql();
      expect(where, '');
      expect(args, isEmpty);
    });

    test('关键字匹配 title/content/app_name/package_name 四列', () {
      final (where, args) = DatabaseHelper.buildSearchSql(keyword: '验证码');
      expect(
        where,
        "WHERE (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' "
        "OR app_name LIKE ? ESCAPE '\\' OR package_name LIKE ? ESCAPE '\\')",
      );
      expect(args.length, 4);
      expect(args.every((a) => a == '%验证码%'), isTrue);
    });

    test('时间范围转为 post_time 区间（start 含、end 不含）', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        startTime: 1000,
        endTime: 2000,
      );
      expect(where, 'WHERE post_time >= ? AND post_time < ?');
      expect(args, [1000, 2000]);
    });

    test('应用名/包名 LIKE 条件', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        appName: '微信',
        packageName: 'com.tencent.mm',
      );
      expect(
        where,
        "WHERE app_name LIKE ? ESCAPE '\\' AND package_name LIKE ? ESCAPE '\\'",
      );
      expect(args, ['%微信%', '%com.tencent.mm%']);
    });

    test('送达状态粗筛：failed/success 命中 delivery_info JSON 文本', () {
      final (where1, args1) = DatabaseHelper.buildSearchSql(
        deliveryFilter: 'failed',
      );
      expect(where1, 'WHERE delivery_info LIKE ?');
      expect(args1, ['%failed%']);

      final (where2, args2) = DatabaseHelper.buildSearchSql(
        deliveryFilter: 'success',
      );
      expect(where2, 'WHERE delivery_info LIKE ?');
      expect(args2, ['%success%']);

      final (where3, _) = DatabaseHelper.buildSearchSql(deliveryFilter: 'all');
      expect(where3, '');
    });

    test('LIKE 通配符转义：用户输入 % _ \\ 不引起意外匹配', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        keyword: r'50%_off\a',
      );
      expect(
        where,
        "WHERE (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' "
        "OR app_name LIKE ? ESCAPE '\\' OR package_name LIKE ? ESCAPE '\\')",
      );
      expect(args.every((a) => a == r'%50\%\_off\\a%'), isTrue);
    });

    test('组合条件按 AND 连接', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        keyword: '验证码',
        startTime: 1000,
        packageName: 'com.a',
        deliveryFilter: 'failed',
      );
      expect(
        where,
        "WHERE (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' "
        "OR app_name LIKE ? ESCAPE '\\' OR package_name LIKE ? ESCAPE '\\') "
        "AND post_time >= ? AND package_name LIKE ? ESCAPE '\\' "
        'AND delivery_info LIKE ?',
      );
      expect(args.length, 7);
      expect(args[4], 1000);
      expect(args[6], '%failed%');
    });

    test('空白关键字视为无关键字', () {
      final (where, args) = DatabaseHelper.buildSearchSql(keyword: '   ');
      expect(where, '');
      expect(args, isEmpty);
    });
  });

  group('escapeLike', () {
    test('转义反斜杠/百分号/下划线并去除首尾空白', () {
      expect(DatabaseHelper.escapeLike(r'a\b%c%d_'), r'a\\b\%c\%d\_');
      expect(DatabaseHelper.escapeLike('  plain  '), 'plain');
    });
  });
}
