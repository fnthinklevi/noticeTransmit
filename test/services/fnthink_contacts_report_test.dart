import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_contacts_report.dart';

/// 「按关键词搜通讯录」那段正文的组装（T124 片C-4 的 `contacts:search`）。
///
/// 钉四件（与通话记录那一份同源：同一条消息预算、同一条不静默丢的纪律）：
///  ① 一条都没命中也要回一句（带那个词）—— 空表不是失败；
///  ② 命中行只带两件：姓名／号码，顺序按原生交回的次序；
///  ③ 两格都空的行不出一行空白（进「未包含」的计数，明写）；全空表走"没有命中"那一句；
///  ④ 单条超长打省略号、整段放不下**明写**「另有 N 条未包含」。
void main() {
  Map<String, Object?> row({String? name, String? number}) => {
    'name': name,
    'number': number,
  };

  group('通讯录回传正文', () {
    test('一条都没命中 ⇒ 回一句带那个词的（不是空串，也不是失败）', () {
      final text = formatFnthinkContactsSearchReport('张三', const []);
      expect(text, contains('张三'));
      expect(text, contains('没有'));
    });

    test('命中 ⇒ 姓名与号码两件都在，顺序按原生交回的次序', () {
      final text = formatFnthinkContactsSearchReport('张', [
        row(name: '张三', number: '13800138000'),
        row(name: '张四', number: '13900139000'),
      ]);
      final lines = text.split('\n');
      expect(lines[0], contains('张三'));
      expect(lines[0], contains('13800138000'));
      expect(lines[1], contains('张四'));
      expect(lines[1], contains('13900139000'));
    });

    test('只有姓名或只有号码的行也出一行（缺哪格就少哪格，不补假数据）', () {
      final text = formatFnthinkContactsSearchReport('x', [
        row(name: '只有名字'),
        row(number: '10086'),
      ]);
      final lines = text.split('\n');
      expect(lines[0], '只有名字');
      expect(lines[1], '10086');
    });

    test('两格都空的行不出一行空白 —— 它进"未包含"的计数（明写）', () {
      final text = formatFnthinkContactsSearchReport('x', [
        row(),
        row(name: '张三', number: '13800138000'),
      ]);
      expect(text, contains('张三'));
      expect(text, contains('另有'));
    });

    test('全空表 ⇒ 走"没有命中"那一句（全空行不算"N 条未包含"）', () {
      final text = formatFnthinkContactsSearchReport('x', [row(), row()]);
      expect(text, contains('没有'));
      expect(text, isNot(contains('未包含')));
    });

    test('单条超长打省略号；整段放不下 ⇒ 明写「另有 N 条」', () {
      final longName = 'x' * (kFnthinkContactsNameCap + 10);
      final one = formatFnthinkContactsSearchReport('x', [
        row(name: longName, number: '13800138000'),
      ]);
      expect(one, contains('…'));
      final many = formatFnthinkContactsSearchReport('x', [
        for (var i = 0; i < 400; i++)
          row(name: '很长的名字很长的名字很长的名字很长的名字${'y' * 20}', number: '1380000$i'),
      ]);
      expect(many, contains('另有'));
      expect(many, contains('条因体积上限未包含'));
    });
  });
}
