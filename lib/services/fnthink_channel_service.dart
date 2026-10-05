import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/fnthink_channel.dart';
import '../models/fnthink_peer.dart';

/// 幻念通道的**唯一写咽喉**（T94 片3）。
///
/// 为什么单列一个服务而不用 `DatabaseHelper` 的静态方法：三件事凑在一起才是一个功能 ——
/// 通道的增删改、名单那一列的勾选、以及"新建一条设备通道时目标必须已勾选"这条判据。
/// 散在三处的话，第三条会在某一次改动里被漏掉，而它的表现是**往一台没勾选的设备发**。
abstract class FnthinkChannelStore {
  Future<List<FnthinkChannel>> list();

  Future<FnthinkChannel> create({
    required String id,
    required String name,
    required String target,
    required FnthinkChannelTarget targetKind,
    String role,
  });

  Future<FnthinkChannel> save(FnthinkChannel channel);

  Future<void> delete(String id);

  Future<List<FnthinkPeer>> listForwardTargets();
}

class FnthinkChannelService implements FnthinkChannelStore {
  FnthinkChannelService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  /// 全部通道，按建的时间正序（列表上先建的在上面 —— 与另外三族一致）。
  ///
  /// 读不到就**抛**，不返回空列表：空列表与"真的还没有"读起来一模一样，
  /// 而界面上那句「还没有通道」会在库读不出来的时候替库说话。
  @override
  Future<List<FnthinkChannel>> list() async {
    final rows = await (await _db.database).query(
      FnthinkChannel.table,
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(FnthinkChannel.fromDbRow).toList();
  }

  /// 建一条。**id 由调用方给**（毫秒时间戳 + 后缀），理由与另外三族相同：
  /// 数据库不该替界面决定"这一行叫什么"。
  @override
  Future<FnthinkChannel> create({
    required String id,
    required String name,
    required String target,
    required FnthinkChannelTarget targetKind,
    String role = 'primary',
  }) async {
    _rejectInvalid(name: name, target: target, targetKind: targetKind);
    if (targetKind == FnthinkChannelTarget.device) {
      await _rejectUncheckedDevice(target);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final channel = FnthinkChannel(
      id: id,
      name: name,
      target: target,
      targetKind: targetKind,
      role: role,
      createdAt: now,
      updatedAt: now,
    );
    await (await _db.database).insert(FnthinkChannel.table, channel.toDbRow());
    return channel;
  }

  /// 改一条已存在的通道（名字 / 目标 / 启停 / 主备）。
  ///
  /// 改完**重读**再返回：页面上显示的那一份必须来自库，而不是刚敲进去的值 ——
  /// 归一（角色、地址码大小写）都发生在写这一侧。
  @override
  Future<FnthinkChannel> save(FnthinkChannel channel) async {
    _rejectInvalid(
      name: channel.name,
      target: channel.target,
      targetKind: channel.targetKind,
    );
    if (channel.targetKind == FnthinkChannelTarget.device) {
      await _rejectUncheckedDevice(channel.target);
    }
    final row = channel
        .copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch)
        .toDbRow();
    final db = await _db.database;
    final changed = await db.update(
      FnthinkChannel.table,
      row,
      where: 'id = ?',
      whereArgs: [channel.id],
    );
    if (changed == 0) {
      throw StateError('没有这一条幻念通道：${channel.id}');
    }
    return (await list()).firstWhere((c) => c.id == channel.id);
  }

  /// 删一条。找不到当**已经不在**（幂等：删第二次不该报错，界面上那一下也是白按的）。
  @override
  Future<void> delete(String id) async {
    await (await _db.database).delete(
      FnthinkChannel.table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 勾上 / 取消勾选「这一台可以当幻念通道的目标」。
  ///
  /// 取消勾选**不连带删通道**：那一格要立刻断掉的只是"新通道不能再选它"，
  /// 已经建好的那一条留着并让它在发送时报出"目标未勾选"，比偷偷把用户的配置删掉好。
  Future<void> setForward(String peerAddress, bool forwards) async {
    final changed = await (await _db.database).update(
      FnthinkPeer.table,
      {'forwards': forwards ? 1 : 0},
      where: 'peer_address = ?',
      whereArgs: [peerAddress],
    );
    if (changed == 0) {
      throw StateError('名单里没有这一台，勾不动：$peerAddress');
    }
  }

  /// 名单里**已勾选**的那些（通道的目标只能从它们里面挑）。
  ///
  /// 一条独立读口而不是让调用方自己 filter：筛选口径一旦有两份，"这一台能不能选"
  /// 就会在某一处与另一处不一致，而不一致的那一侧表现为一个选不上的目标。
  @override
  Future<List<FnthinkPeer>> listForwardTargets() async {
    final rows = await (await _db.database).query(
      FnthinkPeer.table,
      where: 'forwards = 1',
      orderBy: 'granted_at DESC, peer_address ASC',
    );
    return rows.map(FnthinkPeer.fromDbRow).toList();
  }

  void _rejectInvalid({
    required String name,
    required String target,
    required FnthinkChannelTarget targetKind,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', '通道名不能空');
    }
    final t = target.trim();
    if (t.isEmpty) {
      throw ArgumentError.value(target, 'target', '目标不能空');
    }
    if (targetKind == FnthinkChannelTarget.webhook &&
        !t.startsWith('https://')) {
      // 不静默改成 http：这一格填错协议时的表现是"看着存下来了、一条都发不出去"，
      // 而当场说一句"要 https"比那个便宜得多。
      throw ArgumentError.value(target, 'target', 'webhook 目标必须以 https:// 开头');
    }
  }

  Future<void> _rejectUncheckedDevice(String target) async {
    final rows = await (await _db.database).query(
      FnthinkPeer.table,
      columns: ['peer_address', 'forwards'],
      where: 'peer_address = ?',
      whereArgs: [target.trim()],
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(target, 'target', '名单里没有这一台设备');
    }
    if ((rows.first['forwards'] as num?)?.toInt() != 1) {
      throw StateError('这一台还没勾选为转发目标：${target.trim()}');
    }
  }

  @visibleForTesting
  DatabaseHelper get db => _db;
}
