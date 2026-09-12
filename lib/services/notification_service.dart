import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:workmanager/workmanager.dart';
import 'archive_worker.dart';
import 'channel_display.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';
import 'platform_channel.dart';
import 'webhook_service.dart';
import 'email_service.dart';

class NotificationService {
  static const _channel = AppChannels.notification;

  final List<NotificationRecord> _records = [];
  bool _serviceRunning = false;
  bool _serviceManuallyStopped = false;

  List<NotificationRecord> get records => _records;
  bool get serviceRunning => _serviceRunning;
  bool get serviceManuallyStopped => _serviceManuallyStopped;

  Future<void> loadRecords() async {
    try {
      await DatabaseHelper().migrateFromSharedPreferences();
    } catch (e) {
      debugPrint('数据库迁移失败: $e');
    }

    try {
      // 取消保存上限（P1）：全量加载历史记录，配合全量搜索/按时间筛选。
      // 数据库无自动删旧逻辑（归档仅导出备份不删源），内存列表 = DB 全量；
      // 历史页为 ListView 懒加载渲染，万级记录可用。启动耗时随记录数线性增长，
      // 若未来积压过大（>5 万条）可考虑改为分页加载。
      final dbRecords = await DatabaseHelper().getAllNotifications();
      _records.clear();
      _records.addAll(
        dbRecords.map((e) => NotificationRecord.fromMap(e)).toList(),
      );
    } catch (e) {
      debugPrint('从数据库加载记录失败: $e');
      _records.clear();
    }

    // 拉取原生端离线缓存（软件被杀期间的通知），通过 id 去重后合并入库
    await _drainOfflineCache();

    // 存量修复：旧版本拦截记录的真实通道停留"发送中"
    await migrateInterceptedRecords();

    // 补偿拉取 Activity 销毁期间丢失的送达结果（修复"一直显示推送中"）
    await drainPendingDeliveries();
  }

  /// 存量数据修复：旧版本把拦截结果写到独立的 '过滤拦截' key 下，导致记录的
  /// 真实通道永远停留 pending（"发送中"）。将含该 key 的记录统一迁移为
  /// intercepted 状态：停留发送中的通道改为拦截并标注原因，已有终态不覆盖。
  Future<void> migrateInterceptedRecords() async {
    var migrated = 0;
    for (var i = 0; i < _records.length; i++) {
      final status = _records[i].deliveryStatus;
      final legacy = status['过滤拦截'];
      if (legacy is! Map) continue;
      final message = legacy['message']?.toString() ?? '';
      final updated = <String, dynamic>{};
      for (final k in status.keys) {
        if (k == '过滤拦截') continue;
        final info = status[k];
        if (info is Map && info['status'] == 'pending') {
          updated[k] = {'status': 'intercepted', 'message': message};
        } else {
          updated[k] = info;
        }
      }
      // 无真实通道时保留拦截标记本身（历史页对 channels 为空的记录回退按 key 渲染）
      if (updated.isEmpty) {
        updated['过滤拦截'] = {'status': 'intercepted', 'message': message};
      }
      final newRecord = _records[i].copyWith(deliveryStatus: updated);
      _records[i] = newRecord;
      migrated++;
      try {
        await DatabaseHelper().updateNotificationDelivery(
          newRecord.id,
          updated,
        );
      } catch (e) {
        debugPrint('迁移拦截记录状态到 DB 失败: $e');
      }
    }
    if (migrated > 0) {
      debugPrint('[迁移] 修复 $migrated 条拦截记录的送达状态');
    }
  }

  /// 补偿拉取 DeliveryResultStore 中未消费的送达结果并逐条补更新。
  /// 送达结果实时走广播链路（依赖 MainActivity 存活），Activity 被销毁期间的结果
  /// 由原生持久化兜底，此处拉取后按记录幂等补更新（成功/失败/暂停状态写回）。
  Future<void> drainPendingDeliveries() async {
    try {
      final results = await _channel.invokeMethod<List<dynamic>>(
        'drainDeliveryResults',
      );
      if (results == null || results.isEmpty) return;
      for (final item in results) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        await updateDelivery(
          map['notificationId']?.toString() ?? '',
          map['webhookType']?.toString() ?? '',
          map['status']?.toString() ?? '',
          map['message']?.toString() ?? '',
          httpCode: (map['httpCode'] as num?)?.toInt() ?? 0,
          channelUrl: map['channelUrl']?.toString() ?? '',
        );
      }
      debugPrint('[DeliveryResultStore] 补更新 ${results.length} 条送达结果');
    } catch (e) {
      debugPrint('补偿拉取送达结果失败: $e');
    }
  }

  /// 拉取原生 HistoryCache 缓存的离线通知，按 id 去重后入库。
  /// 修复"软件关闭重开后推送历史记录消失"问题。
  Future<void> _drainOfflineCache() async {
    try {
      final cached = await _channel.invokeMethod<List<dynamic>>(
        'drainOfflineCache',
      );
      if (cached == null || cached.isEmpty) return;

      // 获取现有 id 集合，避免重复入库
      final existingIds = _records.map((r) => r.id).toSet();

      var merged = 0;
      for (final item in cached) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString() ?? '';
        if (id.isEmpty || existingIds.contains(id)) continue;

        map['channels'] = _getActiveChannels();
        map['deliveryStatus'] = _buildInitialDeliveries(map['channels']);
        final record = NotificationRecord.fromMap(map);
        _records.insert(0, record);
        await DatabaseHelper().insertNotification(record.toMap());
        merged++;
      }

      // 取消保存上限（P1）：离线通知全量合并，不再截断内存列表

      if (merged > 0) {
        debugPrint('[HistoryCache] 合并 $merged 条离线通知');
      }
    } catch (e) {
      debugPrint('拉取离线缓存失败: $e');
    }
  }

  /// 全量历史搜索（P1）：SQLite LIKE 粗筛 + Dart 端 jsonDecode 精筛。
  ///
  /// 粗筛由 DatabaseHelper.searchNotifications 完成（keyword/时间范围/应用名/
  /// 包名走 SQL，送达状态对 delivery_info JSON 文本 LIKE 粗筛，不引 JSON1 依赖）；
  /// 送达状态的精确判定在 Dart 端 jsonDecode 后完成：
  /// - failed：任一通道 status 为 failed 或 intercepted（拦截视为未送达）
  /// - success：至少有一个通道状态，且全部通道均为 success
  /// 返回 (精筛后记录, 是否可能有下一页)——hasMore 以粗筛行数为准，
  /// 精筛只过滤当页不产生丢条（符合条件者必经粗筛命中）。
  Future<(List<NotificationRecord>, bool)> searchRecords({
    String? keyword,
    int? startTime,
    int? endTime,
    String? appName,
    String? packageName,
    String? deliveryFilter,
    int limit = 200,
    int offset = 0,
  }) async {
    final rows = await DatabaseHelper().searchNotifications(
      keyword: keyword,
      startTime: startTime,
      endTime: endTime,
      appName: appName,
      packageName: packageName,
      deliveryFilter: deliveryFilter,
      limit: limit,
      offset: offset,
    );
    final hasMore = rows.length >= limit;
    var records = rows.map((e) => NotificationRecord.fromMap(e)).toList();
    // Dart flow analysis 不做 a=='x' || a=='y' 的"值集合"提升，
    // 先显式判空得到非空局部（final 提升可跨闭包保留）
    final df = deliveryFilter;
    if (df != null && (df == 'failed' || df == 'success')) {
      records = records
          .where((r) => _matchDeliveryFilter(r.deliveryStatus, df))
          .toList();
    }
    return (records, hasMore);
  }

  /// 送达状态精筛判定（jsonDecode 已由 NotificationRecord.fromMap 完成）
  static bool _matchDeliveryFilter(Map<String, dynamic> status, String filter) {
    if (status.isEmpty) return false;
    final states = status.values
        .whereType<Map>()
        .map((m) => m['status']?.toString())
        .toList();
    if (filter == 'failed') {
      return states.any((s) => s == 'failed' || s == 'intercepted');
    }
    // success：有状态且全部成功
    return states.isNotEmpty && states.every((s) => s == 'success');
  }

  Future<void> loadServiceState() async {
    final prefs = await SharedPreferences.getInstance();
    _serviceManuallyStopped = prefs.getBool('service_manually_stopped') ?? true;
    try {
      _serviceRunning =
          await _channel.invokeMethod('isServiceRunning') as bool? ?? false;
    } catch (e) {
      _serviceRunning = false;
    }
  }

  void addRecord(Map<String, dynamic> record) {
    record['channels'] = _getActiveChannels();
    record['deliveryStatus'] = _buildInitialDeliveries(record['channels']);
    final notificationRecord = NotificationRecord.fromMap(record);
    // 取消保存上限（P1）：新记录全量保留，不再截断内存列表
    _records.insert(0, notificationRecord);
    _saveRecords(notificationRecord.toMap());
  }

  List<String> _getActiveChannels() {
    final channels = <String>[];
    try {
      final webhookService = GetIt.instance<WebhookService>();
      for (final c in webhookService.channels) {
        if (c['enabled'] == true) {
          final type = c['type']?.toString() ?? 'generic';
          channels.add(_webhookTypeLabel(type));
        }
      }
    } catch (_) {}
    try {
      // 从 GetIt 获取已缓存的 EmailService，同步读取已加载的通道
      final emailService = GetIt.instance<EmailService>();
      if (emailService.cachedChannels.any((c) => c.enabled)) {
        channels.add(channelTypeDisplayName('EMAIL'));
      }
    } catch (_) {}
    return channels;
  }

  String _webhookTypeLabel(String type) => channelTypeDisplayName(type);

  /// 初始送达状态：所有启用通道标记为 pending（发送中）
  Map<String, dynamic> _buildInitialDeliveries(List<String> channels) {
    final result = <String, dynamic>{};
    for (final c in channels) {
      result[c] = {'status': 'pending', 'message': ''};
    }
    return result;
  }

  /// Kotlin 端通道类型 → 显示标签（EMAIL/SMS/FILTER 与 webhook 渠道统一由
  /// channelTypeDisplayName 处理，语言随软件设置）
  String _deliveryLabel(String kotlinType) =>
      channelTypeDisplayName(kotlinType);

  /// 更新单条记录的送达状态（Kotlin 端 onDeliveryResult 回传），
  /// 终态（success/failed）同时写入 webhook_delivery_log 送达日志。
  Future<void> updateDelivery(
    String notificationId,
    String kotlinType,
    String status,
    String message, {
    int httpCode = 0,
    String channelUrl = '',
  }) async {
    if (notificationId.isEmpty) return;
    final idx = _records.indexWhere((r) => r.id == notificationId);
    // N9-诊断：idx<0 时此前静默跳过（只写送达日志、不更新状态）——
    // 合并成员卡「发送中」这类问题因此不可观测。此处记录被跳过的 id 供排查。
    final label = _deliveryLabel(kotlinType);
    // SUCCESS → 成功；PAUSED（用户暂停推送，未实际发送）→ paused；其余 → failed
    final normalized = switch (status) {
      'SUCCESS' => 'success',
      'PAUSED' => 'paused',
      _ => 'failed',
    };
    if (idx >= 0) {
      Map<String, dynamic> updated;
      if (kotlinType == 'FILTER' || kotlinType == 'SMS') {
        // 拦截伪通道（FILTER=通知被黑白名单/应用过滤拦截，SMS=短信被拦截）：
        // 实际不会投递，把记录所有真实通道统一置为 intercepted 并标注原因，
        // 否则真实通道永远停留 pending，历史里一直显示"发送中"
        final existing = _records[idx].deliveryStatus;
        updated = existing.isEmpty
            ? <String, dynamic>{
                label: {'status': 'intercepted', 'message': message},
              }
            : <String, dynamic>{
                for (final k in existing.keys)
                  k: {'status': 'intercepted', 'message': message},
              };
      } else if (kotlinType == 'MERGE') {
        // 聚合伪通道（P2 merge 动作）：成员被合并推送后由原生逐条回传聚合推送的
        // **真实结果**，把记录所有真实通道置为对应终态——成员在窗口期内停留
        // pending，到点批量转终态，避免一直显示"发送中"。
        //
        // ⚠ 必须按 normalized（而非写死 success）映射：聚合推送失败时若标成
        // success("已合并推送")，用户会以为内容已送达，而实际丢了——
        // 这类"假成功"比报失败危险得多（原生侧已改为回传真实结果，见
        // MergePushManager.markMembersDelivered）。
        final existing = _records[idx].deliveryStatus;
        updated = existing.isEmpty
            ? <String, dynamic>{
                label: {'status': normalized, 'message': message},
              }
            : <String, dynamic>{
                for (final k in existing.keys)
                  k: {'status': normalized, 'message': message},
              };
      } else {
        updated = Map<String, dynamic>.from(_records[idx].deliveryStatus);
        updated[label] = {'status': normalized, 'message': message};
      }
      final newRecord = _records[idx].copyWith(deliveryStatus: updated);
      _records[idx] = newRecord;
      try {
        await DatabaseHelper().updateNotificationDelivery(
          newRecord.id,
          updated,
        );
      } catch (e) {
        // DB 持久化失败不影响内存送达状态显示
        debugPrint('更新送达状态到 DB 失败: $e');
      }
    } else {
      // N9-兜底：内存未命中（分页未加载 / 内存裁剪 / 时序竞态）不等于记录不存在——
      // 合并成员在入组前已写历史（DB 必有该行）。直接按 id 从 DB 读取、合并
      // 通道终态写回，修复「合并成员卡发送中」且跨重启不自愈的问题。
      try {
        final row = await DatabaseHelper().getNotificationById(notificationId);
        if (row != null) {
          final rec = NotificationRecord.fromMap(row);
          final existing = rec.deliveryStatus;
          // ⚠ 与内存命中分支逐分支对齐（改内存分支必须同步这里）：
          // - FILTER/SMS/MERGE 伪通道 = 全通道统一终态（语义如此）；
          // - 普通通道结果 = 仅更新当前 label，保留其他通道状态
          //   （否则 webhook 结果会误覆盖 email 等通道的真实状态）。
          Map<String, dynamic> updated;
          if (kotlinType == 'FILTER' || kotlinType == 'SMS') {
            updated = existing.isEmpty
                ? <String, dynamic>{
                    label: {'status': 'intercepted', 'message': message},
                  }
                : <String, dynamic>{
                    for (final k in existing.keys)
                      k: {'status': 'intercepted', 'message': message},
                  };
          } else if (kotlinType == 'MERGE') {
            updated = existing.isEmpty
                ? <String, dynamic>{
                    label: {'status': normalized, 'message': message},
                  }
                : <String, dynamic>{
                    for (final k in existing.keys)
                      k: {'status': normalized, 'message': message},
                  };
          } else {
            updated = Map<String, dynamic>.from(existing);
            updated[label] = {'status': normalized, 'message': message};
          }
          await DatabaseHelper().updateNotificationDelivery(
            notificationId,
            updated,
          );
          debugPrint(
            '[updateDelivery] 兜底更新 DB 记录 id=$notificationId → $normalized',
          );
        }
      } catch (e) {
        debugPrint('送达状态 DB 兜底更新失败: $e');
      }
    }
    // 送达日志只记终态（paused 未实际发送，不落日志）
    if (normalized != 'paused') {
      try {
        await DatabaseHelper().insertDeliveryLog(
          channelUrl: channelUrl,
          notificationId: notificationId,
          tag: label,
          status: normalized,
          httpCode: httpCode,
          message: message,
        );
      } catch (e) {
        debugPrint('写入送达日志失败: $e');
      }
    }
  }

  /// 手动"现在推送"：把该记录状态重置为发送中，并通知原生立即补推当前所有启用通道。
  /// 用于历史记录中"用户暂停推送"状态下未实际发送的消息。
  Future<void> pushRecordNow(NotificationRecord record) async {
    final idx = _records.indexWhere((r) => r.id == record.id);
    // F2 修复：记录不在内存列表（典型场景：全量历史搜索打开的旧记录、
    // 或内存已裁剪）时，此前会 `return` 静默不补推。现改为不依赖内存列表：
    // 直接将送达状态重置为 pending 落库 + 调原生补推。
    var target = record;
    if (idx >= 0) {
      target = _records[idx].copyWith(
        deliveryStatus: _buildInitialDeliveries(_getActiveChannels()),
      );
      _records[idx] = target;
    } else {
      target = record.copyWith(
        deliveryStatus: _buildInitialDeliveries(_getActiveChannels()),
      );
    }
    try {
      await DatabaseHelper().updateNotificationDelivery(
        target.id,
        target.deliveryStatus,
      );
    } catch (e) {
      debugPrint('更新送达状态到 DB 失败: $e');
    }
    try {
      await _channel.invokeMethod('pushRecordNow', {'record': target.toMap()});
    } catch (e) {
      debugPrint('调用原生 pushRecordNow 失败: $e');
    }
  }

  /// 统一统计：总数（DB），三处统计共用同一数据源
  Future<int> getTotalCount() async {
    try {
      return await DatabaseHelper().getNotificationCount();
    } catch (e) {
      debugPrint('获取总记录数失败: $e');
      return _records.length;
    }
  }

  /// 统一统计：今日数（DB，本地时区），三处统计共用同一数据源
  Future<int> getTodayCount() async {
    try {
      return await DatabaseHelper().getTodayCount();
    } catch (e) {
      debugPrint('获取今日记录数失败: $e');
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      return _records.where((r) => r.time.startsWith(today)).length;
    }
  }

  /// 状态栏计数统一：把 DB 今日数同步为原生当日计数基数
  Future<void> syncDailyCountToNative() async {
    try {
      final count = await getTodayCount();
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await _channel.invokeMethod('syncDailyPushCount', {
        'count': count,
        'date': date,
      });
    } catch (e) {
      debugPrint('同步今日计数到原生失败: $e');
    }
  }

  Future<void> clearRecords() async {
    try {
      await _channel.invokeMethod('clearNotificationRecords');
    } catch (e) {
      // ignore
    }

    await DatabaseHelper().clearAllNotifications();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_records');
    _records.clear();
  }

  /// 构建导出 JSON 字符串。
  /// 全量数据直读 DB（不受内存 500 条上限约束）；DB 不可用时回退内存记录。
  /// 与旧 exportRecords 双轨实现已合并为本方法，字段统一为 recordCount。
  Future<String> buildExportJson(
    String deviceName,
    String deviceModel,
    String manufacturer,
  ) async {
    List<Map<String, dynamic>> records;
    try {
      records = (await DatabaseHelper().getAllNotifications())
          .map((e) => NotificationRecord.fromMap(e).toMap())
          .toList();
    } catch (e) {
      debugPrint('导出读取 DB 失败，回退内存记录: $e');
      records = _records.map((r) => r.toMap()).toList();
    }
    final data = {
      '_warning': '此文件包含设备通知记录，请妥善保管。',
      'exportTime': DateTime.now().toIso8601String(),
      'deviceName': deviceName,
      'deviceModel': deviceModel,
      'manufacturer': manufacturer,
      'recordCount': records.length,
      'records': records,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> _saveRecords(Map<String, dynamic> record) async {
    try {
      await DatabaseHelper().insertNotification(record);
    } catch (e) {
      // DB 持久化失败不阻塞内存记录显示（避免未处理异步异常）
      debugPrint('保存通知记录到 DB 失败: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getStats() async {
    return await DatabaseHelper().getNotificationStats();
  }

  Future<List<Map<String, dynamic>>> getDailyStats(int days) async {
    return await DatabaseHelper().getDailyStats(days);
  }

  Future<int> getCount({String? type}) async {
    return await DatabaseHelper().getNotificationCount(type: type);
  }

  Future<bool> startService() async {
    try {
      await _channel.invokeMethod('startNotificationListener');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('service_manually_stopped', false);
      _serviceRunning = true;
      _serviceManuallyStopped = false;
      return true;
    } catch (e) {
      debugPrint('启动服务失败: $e');
      return false;
    }
  }

  // ========== 每日自动归档 ==========
  // 使用 WorkManager 替代 Timer.periodic，支持 Doze 模式唤醒
  // 幂等保护：SharedPreferences 中记录 lastArchiveDate，防止重复归档

  void startDailyExport() {
    Workmanager().registerPeriodicTask(
      kArchiveTaskName,
      kArchiveTaskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.not_required),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      initialDelay: const Duration(minutes: 1),
    );
    debugPrint('[Archive] WorkManager 任务已注册');
    // 前台兜底：App 启动后立即检查并执行一次归档
    performArchiveOnBoot();
  }

  void dispose() {
    Workmanager().cancelByUniqueName(kArchiveTaskName);
  }

  // ========== 多种清除方式 ==========

  /// 清除今日通知
  Future<int> clearToday() async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final toDelete = _records.where((r) => r.time.startsWith(today)).toList();
    for (final r in toDelete) {
      await DatabaseHelper().deleteNotification(r.id);
    }
    _records.removeWhere((r) => r.time.startsWith(today));
    return toDelete.length;
  }

  /// 清除指定日期段内的通知
  Future<int> clearDateRange(DateTime start, DateTime end) async {
    final db = DatabaseHelper();
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    final toDelete = _records
        .where((r) => r.postTime >= startMs && r.postTime <= endMs)
        .toList();
    for (final r in toDelete) {
      await db.deleteNotification(r.id);
    }
    _records.removeWhere((r) => r.postTime >= startMs && r.postTime <= endMs);
    return toDelete.length;
  }

  /// 清除最近 N 条通知
  Future<int> clearLastN(int n) async {
    if (_records.isEmpty || n <= 0) return 0;
    final count = n < _records.length ? n : _records.length;
    final toDelete = _records.take(count).toList();
    for (final r in toDelete) {
      await DatabaseHelper().deleteNotification(r.id);
    }
    _records.removeRange(0, count);
    return count;
  }

  Future<bool> stopService() async {
    try {
      await _channel.invokeMethod('stopNotificationListener');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('service_manually_stopped', true);
      _serviceRunning = false;
      _serviceManuallyStopped = true;
      return true;
    } catch (e) {
      debugPrint('停止服务失败: $e');
      return false;
    }
  }
}
