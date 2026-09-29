import 'package:get_it/get_it.dart';
import '../database/database_helper.dart';
import '../services/webhook_service.dart';
import '../services/battery_service.dart';
import '../services/temperature_service.dart';
import '../services/device_state_service.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../services/filter_service.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_identity_service.dart';
import '../services/fnthink_inbox_display.dart';
import '../services/fnthink_inbox_service.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_receiver_service.dart';
import '../services/update_service.dart';
import '../services/device_info_service.dart';
import '../services/theme_service.dart';
import '../services/email_service.dart';
import '../services/locale_service.dart';
import '../services/app_channel_service.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_health_store.dart';
import '../services/channel_probe_service.dart';
import '../services/installed_apps_service.dart';
import '../services/sms_service.dart';

final GetIt getIt = GetIt.instance;

void setupLocator() {
  getIt.registerLazySingleton<WebhookService>(() => WebhookService());
  getIt.registerLazySingleton<BatteryService>(() => BatteryService());
  getIt.registerLazySingleton<NotificationService>(() => NotificationService());
  getIt.registerLazySingleton<TemperatureService>(() => TemperatureService());
  // T24：设备状态告警（亮度 + 网络），与电量/温度同族同形（规则住 engine_rules 表）
  getIt.registerLazySingleton<DeviceStateService>(() => DeviceStateService());
  getIt.registerLazySingleton<PermissionService>(() => PermissionService());
  getIt.registerLazySingleton<FilterService>(() => FilterService());
  getIt.registerLazySingleton<UpdateService>(() => UpdateService());
  getIt.registerLazySingleton<DeviceInfoService>(() => DeviceInfoService());
  getIt.registerLazySingleton<ThemeService>(() => ThemeService());
  getIt.registerLazySingleton<EmailService>(() => EmailService());
  getIt.registerLazySingleton<LocaleService>(() => LocaleService());
  getIt.registerLazySingleton<SmsService>(() => SmsService());
  getIt.registerLazySingleton<AppChannelService>(() => AppChannelService());
  // 通道描述符缓存：设置页的表单字段 / 类型选择器 / 显隐都按它渲染（第 5 步）
  getIt.registerLazySingleton<ChannelDescriptorService>(
    () => ChannelDescriptorService(),
  );
  // 健康度缓存单点（第 6 步）：webhook / 应用通道 / 邮件三族共用一份读写与时效口径
  getIt.registerLazySingleton<ChannelHealthStore>(() => ChannelHealthStore());
  getIt.registerLazySingleton<InstalledAppsService>(
    () => InstalledAppsService(),
  );
  // 6e：三族「进页刷新通道状态」的非侵入探测调度（依赖上面的健康单点，注册顺序要紧）
  getIt.registerLazySingleton<ChannelProbeService>(() => ChannelProbeService());

  // ── 幻念推送 · 收货链路（#126 第四片）──
  // ⚠ 注册的是"能启停的对象"，**不是"已经在跑的循环"**：起不起由总开关决定，而开关默认是关的
  //    （这台设备从没同意过"通知内容经服务器中转"，T44 与 T56 的一次性同意没接上之前不该被翻开）。
  // 都是 lazy：注册本身不做 IO —— 契约要读随包资源、地址码要读 EncryptedSharedPreferences，
  // 那两件事发生在第一次 startIfEnabled 里，不在 setupLocator 里。
  getIt.registerLazySingleton<FnthinkContractLoader>(
    () => FnthinkContractLoader(),
  );
  getIt.registerLazySingleton<FnthinkReceiveCoordinator>(
    () => FnthinkReceiveCoordinator(
      contracts: getIt<FnthinkContractLoader>(),
      signer: FnthinkKeystoreSigner(FnthinkIdentityService()),
      persist: DatabaseHelper().insertFnthinkInbox,
      // 收件显示（通知栏）。这一行与上面那行是"能不能报 displayed"的两半：只接 persist，
      // 消息会安全落到表里但永远不进通知栏，而 ack 一律报 delivered —— 服务端据此留着正文重发，
      // 于是"能慢不能丢"做成了"能存不能见"。装配点的那条守卫在
      // `test/architecture/fnthink_receive_wiring_test.dart`。
      display: FnthinkInboxDisplay().show,
      // 回执那一列的作者。缺它 ⇒ `ack_result`/`acked_at` 永远空着，而 T48 的收件详情
      // 一旦显示这一列就是在猜（任务 #155 那条"只有漏接才现形"的形状）。
      recordAck: DatabaseHelper().recordFnthinkInboxAck,
      // 本机配对名单的作者。T42 第五片之前这张表**一个生产写入者都没有**（表与 upsert 在
      // 前置那片就落好了，但没人调用），缺这一行的后果是：同意之后服务端那边配通了，
      // 而这一台的名单是空的 —— 下一片那个"取消配对"的入口就没有东西可取消。
      // 这条漏接全场测试仍然绿，守卫在 `test/architecture/fnthink_receive_wiring_test.dart`。
      recordPeer: DatabaseHelper().upsertFnthinkPeer,
    ),
  );
  // 收件（别人推给本机的消息）的读写咽喉：历史页的收件档、下一片的首页未读卡都从这里取同一个数。
  // 不注册时那些入口会各自 new 一份或直连表 —— 全场测试仍然绿，只有未读数和列表行数开始对不上。
  getIt.registerLazySingleton<FnthinkInboxService>(() => FnthinkInboxService());
}
