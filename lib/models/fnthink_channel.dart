import 'package:flutter/foundation.dart';

/// 幻念通道的**目标种类**。封闭两个字面量（读别的词一律抛）。
///
/// 为什么只有这两种：维护者 2026-10-05 定的两件事 —— 转发目标是「一台绑定设备」
/// 或「一个 webhook」。加第三种就是加一条**没有发送实现**的路，而界面上摆一条
/// 点了没反应的行比没有这行更糟。
enum FnthinkChannelTarget { device, webhook }

/// 本机的一条幻念通道（T94 片3）。
///
/// 它是「这台设备作为发送方的转发目标」，不是配对关系也不是接入端点：
/// - 配对（[FnthinkPeer]）回答"谁可以往这台推"；
/// - 接入端点（服务端那张表）回答"谁能往这台写、写到哪一档"；
/// - **通道**回答"这台可以把收到的通知转发到哪儿"。
///
/// 三者方向不同、生命周期不同，混在一张表里就会出现"删了通道对方就不能推了"这种
/// 看着合理、实际是把权限和转发混成一件的事。
@immutable
class FnthinkChannel {
  const FnthinkChannel({
    required this.id,
    required this.name,
    required this.target,
    this.targetKind = FnthinkChannelTarget.device,
    this.enabled = true,
    this.role = 'primary',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 用户给的名字（列表上显示的就是它）。空名在保存那一层就被拒 —— 一张列表里
  /// 全是「通道 1 / 通道 2」的话，删错一条的代价与删对一条一样。
  final String name;

  /// 目标：设备时是 18 位地址码，webhook 时是 https 地址。
  final String target;

  final FnthinkChannelTarget targetKind;
  final bool enabled;

  /// 主备角色（与另外三族同一个口径，取值归一在 `ChannelConfigCodec.normalizeRole`）。
  final String role;

  final int createdAt;
  final int updatedAt;

  static const table = 'fnthink_channels';

  static const columns = <String>[
    'id',
    'name',
    'target_kind',
    'target',
    'enabled',
    'role',
    'created_at',
    'updated_at',
  ];

  /// 目标种类 ↔ 库里的词。**这是唯一一处**做这件事的地方。
  static String kindToDb(FnthinkChannelTarget kind) =>
      kind == FnthinkChannelTarget.webhook ? 'webhook' : 'device';

  /// 认不出的词判**设备**（fail-closed 的方向由调用方决定：读错成设备时，
  /// 那一列地址码在发送前会过地址码校验而失败，不会变成往一个乱地址发）。
  static FnthinkChannelTarget kindFromDb(Object? raw) => raw == 'webhook'
      ? FnthinkChannelTarget.webhook
      : FnthinkChannelTarget.device;

  Map<String, Object?> toDbRow() => {
    'id': id,
    'name': name,
    'target_kind': kindToDb(targetKind),
    'target': target,
    'enabled': enabled ? 1 : 0,
    'role': role,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  static FnthinkChannel fromDbRow(Map<String, Object?> row) {
    return FnthinkChannel(
      id: '${row['id'] ?? ''}',
      name: '${row['name'] ?? ''}',
      targetKind: kindFromDb(row['target_kind']),
      target: '${row['target'] ?? ''}',
      // 启停读不出时当**停用**：`enabled` 写坏而表现成"到处都在发"是不可接受的。
      enabled: (row['enabled'] as num?)?.toInt() == 1,
      role: '${row['role'] ?? 'primary'}',
      createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  FnthinkChannel copyWith({
    String? name,
    String? target,
    FnthinkChannelTarget? targetKind,
    bool? enabled,
    String? role,
    int? updatedAt,
  }) {
    return FnthinkChannel(
      id: id,
      name: name ?? this.name,
      target: target ?? this.target,
      targetKind: targetKind ?? this.targetKind,
      enabled: enabled ?? this.enabled,
      role: role ?? this.role,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'FnthinkChannel($id, $name, ${kindToDb(targetKind)}, '
      '${target.length > 12 ? '${target.substring(0, 12)}…' : target}, '
      'enabled=$enabled, role=$role)';
}
