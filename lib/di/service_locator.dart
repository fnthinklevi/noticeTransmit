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
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_presence_scheduler.dart';
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
  // 「被杀之后还有人去问一次货」的那半（T33 第二片 / §4-9）。注册在协调者**之前**：
  // 协调者 factory 里那行 `getIt<FnthinkPresenceScheduler>()` 在第一次取协调者时才展开，
  // 顺序写反不会崩，但读代码的人会按这里的样子抄——装配点守卫钉的是"这一行在不在"。
  getIt.registerLazySingleton<FnthinkPresenceScheduler>(
    () => FnthinkPresenceScheduler(contracts: getIt<FnthinkContractLoader>()),
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
      // 名单那一行的删除者（T31 B 片第二片）。⚠ 走**服务层**而不是直连表：`remove` 今天有
      // 调用方（就是这一行），所以它不是空抽象；而绕过读咽喉去摸表，名单就有两本账。
      // 缺这一行的后果与上面那行同族：撤销在服务端生效了、对面从此推不进来，而这一台的名单
      // 还留着那一行 —— 用户看到的是"点了撤销没反应"，于是再点一次。守卫在同一个装配点测试里。
      removePeer: FnthinkPeerService().remove,
      // 续排闹钟（T33 第二片）。漏接的表现不是崩，是**链条悄悄断**：收货照常、界面照常，
      // 只有"被 ROM 杀掉之后"那一天没人再去问一次货；而全场 Dart 测试仍然绿
      // （协调者的用例都把 hook 当参数传进来，不经过 DI）。守卫在
      // `test/architecture/fnthink_presence_guard_test.dart`，反证在 `outputs/_presence1b.report.txt`。
      presenceNotice: getIt<FnthinkPresenceScheduler>().notice,
      // 「我发过的」那一档的作者（T43）：发送被受理之后把这一条落进 `fnthink_messages`
      // （方向 out）。漏接时的表现不是崩，是那一档**永远是空的** —— 用户发过的每一条都查不到，
      // 而全场测试仍然绿。守卫在 `test/architecture/fnthink_device_send_guard_test.dart`。
      recordSent: DatabaseHelper().insertFnthinkInbox,
      // 设备自登记（#177）：本机在服务端设备表里那一行是**其余每一发的共同前置** ——
      // 服务端按表里那把钥匙验签，而表里的行只能由 /register 建。缺这一行时全场 Dart 测试
      // 仍然绿，而真机上所有请求都换回同形的 403 `rejected_unsigned`（用户报的「建立端点：
      // 端点没建成（rejected-unsigned）」就是这条）。守卫在
      // `test/architecture/fnthink_receive_wiring_test.dart`。
      // 名字取设备信息服务里那份（原生启动时读过一次；读不到就是空串，服务端会截断到 60）。
      registerDevice: (spec) async {
        final service = buildFnthinkReceiveService(spec);
        try {
          return await service.register(
            name: getIt<DeviceInfoService>().deviceName,
          );
        } finally {
          service.dispose();
        }
      },
    ),
  );
  // 收件（别人推给本机的消息）的读写咽喉：历史页的收件档、下一片的首页未读卡都从这里取同一个数。
  // 不注册时那些入口会各自 new 一份或直连表 —— 全场测试仍然绿，只有未读数和列表行数开始对不上。
  getIt.registerLazySingleton<FnthinkInboxService>(() => FnthinkInboxService());
  // 本机配对名单的唯一读写咽喉（T42「配对名单」那一格 + T31 的撤销）。
  // ⚠ 删行只在协调者撤销成功之后被调用，页面从不直接碰它 —— 先删行会让"授权还在而来源消失"。
  getIt.registerLazySingleton<FnthinkPeerService>(() => FnthinkPeerService());
}

/// 后台引擎里"那一轮到底干什么"的**唯一实现**（T33 第二片 / §4-9 片1b；#178 真机现形后定的形状）。
///
/// 为什么是"自带装配的顶层函数"，而不是"在这里给 `runFnthinkPresenceRound` 赋值"：
/// 后台 isolate 里从没跑过 `runApp` ⇒ 也永远不会有人调 `setupLocator()` ⇒
/// 上一版那种"赋值写在 setupLocator 里"的形状，变量从头到尾都是占位实现。
/// 真机日志（2026-09-30）里每 20 秒一行「后台那一轮失败：没有装配」就是这里来的 ——
/// 而全场 Dart 测试仍然绿（没有任何用例跑过"空 getIt + 直接进这一轮"这条路）。
/// 现在 `fnthink_presence_scheduler.dart` 里那份默认值直接指向本函数：谁起的那颗引擎都自带装配。
///
/// ⚠ 与前台必须是同一条收货路（同一套判据、同一个内核）：在这儿拼第二个 poll 循环，
///   就等于给同一个协议找第二个作者。守卫钉在 `test/architecture/fnthink_presence_guard_test.dart`。
Future<void> fnthinkBackgroundRound() async {
  // 前台进程里整棵树已经装好了（`registerLazySingleton` 二次注册会抛，别重复装）；
  // 后台 isolate 里 getIt 是空的 —— 那一次由这里补上，且必须在收货之前。
  if (!getIt.isRegistered<FnthinkReceiveCoordinator>()) setupLocator();
  await getIt<FnthinkReceiveCoordinator>().receiveOnce();
}
