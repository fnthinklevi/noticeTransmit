import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:fnthink_push/fnthink_push.dart';
import '../database/database_helper.dart';
import '../services/webhook_service.dart';
import '../services/battery_service.dart';
import '../services/temperature_service.dart';
import '../services/device_state_service.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../services/filter_service.dart';
import '../services/fnthink_channel_service.dart';
import '../services/fnthink_contract_loader.dart';
import '../services/fnthink_identity_service.dart';
import '../services/fnthink_inbox_display.dart';
import '../services/fnthink_alert_display.dart';
import '../services/fnthink_inbox_service.dart';
import '../services/fnthink_peer_service.dart';
import '../services/fnthink_presence_scheduler.dart';
import '../services/fnthink_receive_coordinator.dart';
import '../services/fnthink_receiver_service.dart';
import '../services/fnthink_remote_command_handler.dart';
import '../services/fnthink_remote_executors.dart';
import '../services/fnthink_remote_runner.dart';
import '../services/fnthink_remote_settings.dart';
import '../services/fnthink_remote_wiring.dart';
import '../models/notification_record.dart';
import '../services/fnthink_notification_report.dart';
import '../services/fnthink_call_log_report.dart';
import '../services/fnthink_location_report.dart';
import '../services/fnthink_contacts_report.dart';
import '../services/fnthink_photo_report.dart';
import '../services/fnthink_read_settings.dart';
import '../services/fnthink_shortcut_registry.dart';
import '../services/fnthink_sms_search_report.dart';
import '../services/platform_channel.dart';
import '../services/remote_credential_store.dart';
import '../services/remote_execution_notifier.dart';
import '../services/secure_storage_service.dart';
import '../services/active_channels.dart';
import '../services/fnthink_settings.dart';
import '../services/update_service.dart';
import '../services/update_server_regions.dart';
import '../services/device_info_service.dart';
import '../services/theme_service.dart';
import '../services/email_service.dart';
import '../services/locale_service.dart';
import '../services/app_channel_service.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_display.dart';
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
  // T95：检查更新那一发同时是"这台更新服务器能不能用"的测量结果，接进健康度单点
  // （family=`update`、id=档位名）。⚠ 漏接的表现与幻念那一格当年同形：更新照常、
  // 页面照常，只有徽标永远"没测过"——所以这一处接线有守卫用例盯着。
  getIt.registerLazySingleton<UpdateService>(
    () => UpdateService(
      onProbe: ({required probe}) => getIt<ChannelHealthStore>().record(
        kUpdateHealthFamily,
        probe.region.name,
        reachable: probe.reachable,
        latencyMs: probe.latencyMs,
        httpCode: probe.httpCode,
      ),
    ),
  );
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
      display: (message) async {
        // T55 ③ 角标那个数：在**发通知这一刻**去数，而不是把循环开始时的数一直带着 ——
        // 一轮里可能落了好几条，中途插进来的那条也算未读。数法只有
        // `countFnthinkInboxUnread` 一处，与首页入口卡同源（不另写 list().length：
        // 那条列表带 limit，收到第 51 条起它就会开始少报）。
        final unread = await DatabaseHelper().countFnthinkInboxUnread();
        return FnthinkInboxDisplay().show(message, unreadCount: unread);
      },
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
      // 配对请求那一份账的作者与读口（T116）。缺 author 的后果与 `recordPeer` 同族且更狠：
      // 「我发起过什么」「对面答过没有」在本机一个字节都不留，重启即空，
      // 而界面上一切照常 —— 全场 Dart 测试仍然绿（协调者用例都把 hook 当参数传）。
      // 守卫在 `test/architecture/fnthink_receive_wiring_test.dart`。
      storePairRequest: DatabaseHelper().saveFnthinkPairRequest,
      loadPairRequests: () => DatabaseHelper().loadFnthinkPairRequests(),
      // 续排闹钟（T33 第二片）。漏接的表现不是崩，是**链条悄悄断**：收货照常、界面照常，
      // 只有"被 ROM 杀掉之后"那一天没人再去问一次货；而全场 Dart 测试仍然绿
      // （协调者的用例都把 hook 当参数传进来，不经过 DI）。守卫在
      // `test/architecture/fnthink_presence_guard_test.dart`，反证在 `outputs/_presence1b.report.txt`。
      presenceNotice: getIt<FnthinkPresenceScheduler>().notice,
      // 「我发过的」那一档的作者（T43）：发送被受理之后把这一条落进 `fnthink_messages`
      // （方向 out）。漏接时的表现不是崩，是那一档**永远是空的** —— 用户发过的每一条都查不到，
      // 而全场测试仍然绿。守卫在 `test/architecture/fnthink_device_send_guard_test.dart`。
      recordSent: DatabaseHelper().insertFnthinkInbox,
      // 远程执行历史的读咽喉（片3b-2）。页面**不许**自己开表（守卫
      // `test/architecture/fnthink_receive_wiring_test.dart`），所以这两个 hook 就是
      // 那一格唯一的取货口；漏接时的表现是历史页说"读不出来"，而不是崩。
      loadRemoteExecutions: (direction) =>
          DatabaseHelper().loadRemoteExecutionRecords(direction: direction),
      forgetRemoteExecution: DatabaseHelper().removeRemoteExecutionRecord,
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
      // T60（approach B）：发送的服务器可达性记进通道健康度，family=`fnthink-server`、id=服务器 host
      // （T104 片①：以前它与"这条通道最近手动测过没有"共用 `fnthink` 那个族名，两种主语挤一处）。
      // 协调者只在"拿到过服务器响应/传输失败"时调这里（本机没发出去那几种不进来）。
      // 守卫在 `test/architecture/fnthink_receive_wiring_test.dart`：漏接时发送与页面照常，
      // 只有幻念那一行的健康度永远是"没测过"。
      recordHealth: ({required host, required reachable, required latencyMs}) =>
          getIt<ChannelHealthStore>().record(
            kFnthinkServerFamily,
            host,
            reachable: reachable,
            latencyMs: latencyMs,
          ),
      // ⚠⚠ 远程执行那一格（片3c-4）。此前 `onCommand` **一个值都没接过** ——
      //   收货循环从 8.183 起就挂着它，DI 里却没有，于是远程指令消息
      //   **照常按通知弹出来而没有任何东西动手**（用户看到的："对方说发了指令，我这边响了一声"）。
      //   全场 Dart 测试仍然绿，因为循环的用例把 hook 当参数传进来、不经过 DI。
      //
      //   守卫在 `test/architecture/fnthink_receive_wiring_test.dart`：
      //   摘掉这一行，红的不是任何一条"远程执行能不能执行"的用例，
      //   而是"这一格有没有接上"这一条 —— 漏接的那两处（判据写对了、装配没接）
      //   在别的用例里长得一模一样（都绿）。
      onCommand: (message) async {
        // ⚠ 契约还没读到 ⇒ 判不了远程执行，**按普通通知处理**（照常显示）。
        //   不这么判的话下面那一行 `cached!` 会崩，而崩溃发生在收货循环里
        //   —— 一次崩溃把整轮收货带走，而那一轮里还有别的普通通知。
        if (getIt<FnthinkContractLoader>().cached == null) return false;
        return getIt<RemoteCommandWiring>().onCommand(message);
      },
    ),
  );
  // 收件（别人推给本机的消息）的读写咽喉：历史页的收件档、下一片的首页未读卡都从这里取同一个数。
  // 不注册时那些入口会各自 new 一份或直连表 —— 全场测试仍然绿，只有未读数和列表行数开始对不上。
  getIt.registerLazySingleton<FnthinkInboxService>(() => FnthinkInboxService());
  // 本机配对名单的唯一读写咽喉（T42「配对名单」那一格 + T31 的撤销）。
  // ⚠ 删行只在协调者撤销成功之后被调用，页面从不直接碰它 —— 先删行会让"授权还在而来源消失"。
  // ⚠ T49 追加：契约装载器也注入进来 —— `grantFor` 要拿档位词表才能判"够不够得着"，
  //   少注入时不是静默放行，而是那一发抛 `FnthinkContractUnavailable`。
  getIt.registerLazySingleton<FnthinkPeerService>(
    () => FnthinkPeerService(contracts: getIt<FnthinkContractLoader>()),
  );
  // 幻念通道的唯一写咽喉（T94 片3）。T104 片② 之前它**不在 DI 里**：四处调用点各自 new 一个
  // （`main_page` 的字段、通道列表页、通道详情页、配对名单页）——那时每个实例只服务自己那一次读写，
  // new 出第二份没有任何可见后果。现在它多了一份**内存列表**（`cachedChannels`，首页与通道状态页那张
  // 「当前推送通道」清单读的就是它），于是"谁装载的谁看得见"成了缺陷：装载发生在 `main_page`
  // 那一份上，而清单读另一份就永远是空表 —— 表现是配好的幻念通道在首页根本不出现，且一行错误都没有。
  getIt.registerLazySingleton<FnthinkChannelService>(
    () => FnthinkChannelService(),
  );

  // ── 远程执行（片3c-4：把判定层、执行器、执行链接到收货那一格）──
  // ⚠ 注册顺序无所谓（全 lazy），但**这五处都要在**。少任何一处的表现都是
  //   「那条指令不执行」或「那一格没接」，而**全场 Dart 测试仍然绿** ——
  //   远程执行的每一组用例都把依赖当参数传进来，压根不经过 DI。
  //   所以这一段的值不在用例里，在 `test/architecture/fnthink_receive_wiring_test.dart`。
  //
  // ⚠ 下面几处都用 `cached!`：它们只在**契约已读之后**才构造
  //   （入口是 `onCommand` 那一格，那里先判过 `cached != null`）。
  //   没发生过远程执行时一个都不会构造 ⇒ 契约也不会被读。

  // 总开关与延时窗口那一份。
  getIt.registerLazySingleton<FnthinkRemoteSettings>(
    () =>
        FnthinkRemoteSettings(contract: getIt<FnthinkContractLoader>().cached!),
  );
  // ⚠⚠ 这一处是**补注册**，不是新增功能：`DeviceL3Executor.collectInboxEnabled` 早就写着
  //   `getIt<FnthinkSettings>()`，而全仓没有任何 `register*<FnthinkSettings>`。
  //   症状与 `SecureStorageService` 那条同一族：所有注册都是 lazy ⇒ 谁先碰谁崩，
  //   而 widget 测试压根不构造这条链（守卫只 `isRegistered<T>()`，那不构造对象），
  //   所以**全量 App 测试 1977 条全绿也照样藏着**。它在模拟器跑集成冒烟时当场红出来。
  //   `FnthinkSettings` 需要 `contract`（无参 new 不了），所以正解是注册而不是改调用点。
  getIt.registerLazySingleton<FnthinkSettings>(
    () => FnthinkSettings(contract: getIt<FnthinkContractLoader>().cached!),
  );
  // 凭据（只存哈希；高级密钥与二步验证码的种子都在这一份里）。
  // ⚠⚠ `storage:` 必须**直接 new**，不能写 `getIt<SecureStorageService>()`：
  //   `SecureStorageService` 是 `factory SecureStorageService() => _instance` 的**进程单例**，
  //   全仓八处用法（database_helper / webhook_service / 两份 credential_store …）都是直接 new，
  //   **它从来没有在 DI 里注册过**。写成 getIt<> 的后果不是"少一个可选依赖"：
  //   `RemoteCredentialStore` 是 lazy singleton，谁先碰它谁崩 —— 而片3c-6 把
  //   `RemoteCommandWiring` 挂到**首页首帧后无条件 drain**，于是这一行会让
  //   **每次冷启动都崩在 getIt 上**，症状是"首页白屏，控制台一行 GetIt not registered"。
  //   （这条是在模拟器跑集成冒烟时当场红出来的；此前没人碰这条链，所以它一直藏着。）
  getIt.registerLazySingleton<RemoteCredentialStore>(
    () => RemoteCredentialStore(
      contract: getIt<FnthinkContractLoader>().cached!,
      storage: SecureStorageService(),
    ),
  );
  // 判定层（开关 → 渠道 → 凭据 → **本机名单里那一行** → 词表）。
  getIt.registerLazySingleton<RemoteCommandRecognizer>(
    () => RemoteCommandRecognizer(
      contract: getIt<FnthinkContractLoader>().cached!,
      settings: getIt<FnthinkRemoteSettings>(),
      credentials: getIt<RemoteCredentialStore>(),
      // ⚠⚠ T128 片2：这一行是「按设备设权限」在本机生效的**唯一**一处接线。
      //   摘掉它不会有任何可见症状（指令照常执行），而它守的是"配对到 L1 的那台能不能
      //   发 L2/L3"—— 远程指令在线上一条是 L1 通知，服务端的能力判据对它根本不响。
      //   守卫在 `test/architecture/fnthink_receive_wiring_test.dart`。
      grantForSender: (peer) => getIt<FnthinkPeerService>().grantFor(peer),
    ),
  );
  // 两个执行器。
  getIt.registerLazySingleton<DeviceL2Executor>(
    () => DeviceL2Executor(
      setListenerEnabled: ({required bool enabled}) async => enabled
          ? await getIt<NotificationService>().startService()
          : await getIt<NotificationService>().stopService(),
      setChannelEnabled: (target) =>
          updateChannelEnabled(target.family, target.id, target.enabled),
      pushDeviceStateNow: _pushDeviceStateOnce,
      reportNotificationsNow: _fnthinkReportNotificationsOnce,
      ringAlertNow: () => FnthinkAlertDisplay().ring(),
      searchSmsNow: _fnthinkSearchSmsOnce,
      searchCallsNow: _fnthinkSearchCallsOnce,
      getLocationNow: _fnthinkGetLocationOnce,
      snapPhotoNow: _fnthinkSnapPhotoOnce,
      searchContactsNow: _fnthinkSearchContactsOnce,
      launchAppNow: _fnthinkLaunchShortcutOnce,
    ),
  );
  getIt.registerLazySingleton<DeviceL3Executor>(
    () => DeviceL3Executor(
      grantNotificationListener:
          getIt<PermissionService>().requestNotificationListenerPermission,
      grantExactAlarm: getIt<PermissionService>().requestExactAlarmPermission,
      grantBatteryOptimization:
          getIt<PermissionService>().requestBatteryOptimization,
      // ⚠ 厂商自启动**没有统一入口**：本机五个方法各送一家（小米/魅族/华为/oppo/vivo），
      //   而「这一台是哪个厂商」是**读设备信息**那件事。选哪一家放在这里，
      //   执行器只收那一条被选中的（`DeviceL3Executor` 的类注释里同一段理由）。
      grantVendorAutoStart: () => _requestVendorAutoStart(getIt),
      serviceRunning: () async => getIt<NotificationService>().serviceRunning,
      setListenerEnabled: ({required bool enabled}) async => enabled
          ? await getIt<NotificationService>().startService()
          : await getIt<NotificationService>().stopService(),
      collectInboxEnabled: () async => getIt<FnthinkSettings>().receiveEnabled,
      setCollectInboxEnabled: (enabled) async {
        await getIt<FnthinkSettings>().setReceiveEnabled(enabled);
        return true;
      },
    ),
  );
  // 执行链（窗口 → 动手 → 两段回执 → 撤销咽喉）。
  // ⚠ 窗口秒数**每次现取**设置那一格，不在构造时缓存 ——
  //   用户在设置页改了一次，不该要重启进程才生效。
  getIt.registerLazySingleton<RemoteExecutionNotifier>(
    () => const RemoteExecutionNotifier(),
  );
  getIt.registerLazySingleton<RemoteCommandRunner>(
    () => RemoteCommandRunner(
      contract: getIt<FnthinkContractLoader>().cached!,
      // ⚠ `delaySeconds` 是 `Future<int?>`（null = 用户从没选过 ⇒ 落回契约默认），
      //   而执行链要的是一个确定的秒数。契约那一格在这里现取（不缓存）。
      windowSeconds: () async =>
          await getIt<FnthinkRemoteSettings>().delaySeconds ??
          getIt<FnthinkContractLoader>()
              .cached!
              .remoteExecutionDelayDefaultSeconds,
      l2: getIt<DeviceL2Executor>(),
      l3: getIt<DeviceL3Executor>(),
      saveRecord: (record) =>
          // ⚠ 直接 new 而不走 getIt：DatabaseHelper 是单例且全仓其余六处（上面 92–125 行）
          //   都是直接 new 的 —— 它**没有**在 DI 注册。写成 getIt<> 的后果是
          //   `RemoteCommandRunner` / `RemoteCommandWiring` 的 saveRecord 一调就崩，
          //   而留痕是执行链的每一格都要走的 ⇒ 每一次远程执行都失败。
          DatabaseHelper().saveRemoteExecutionRecord(record),
      sendReceipt: (peer, receipt) => _sendRemoteReceipt(getIt, peer, receipt),
      // 回传（T124 片B）：产出那段正文，走**同一条消息路**发给发起的那一台。
      // ⚠ 标题取契约声明的那一枚（`l2.reports[*].title`）—— 契约没声明就不发：
      //   没有标题就发出去，收件端把一次回传读成一条普通通知。
      sendReport: (peer, action, payload) async {
        final title = getIt<FnthinkContractLoader>().cached!.l2ReportTitle(
          action,
        );
        if (title == null) return false;
        final result = await getIt<FnthinkReceiveCoordinator>().sendNotice(
          peer: peer,
          title: title,
          text: payload,
        );
        return result.status == FnthinkSendStatus.accepted;
      },
      statusBar: getIt<RemoteExecutionNotifier>(),
      now: DateTime.now,
    ),
  );
  // 收货循环那一格与判定层之间那一段。
  getIt.registerLazySingleton<RemoteCommandWiring>(
    () => RemoteCommandWiring(
      contract: getIt<FnthinkContractLoader>().cached!,
      recognizer: getIt<RemoteCommandRecognizer>(),
      runner: getIt<RemoteCommandRunner>(),
      // ⚠ 与 runner 上面那个**同一个** lazy singleton：两者都只发方法调用，
      //   各拿一个实例不会有行为差异，但让读者以为它们是两件事就不好了。
      notifier: getIt<RemoteExecutionNotifier>(),
      // ⚠ 直接 new 而不走 getIt：DatabaseHelper 是单例且全仓其余六处（上面 92–125 行）
      //   都是直接 new 的 —— 它**没有**在 DI 注册。写成 getIt<> 的后果是
      //   `RemoteCommandRunner` / `RemoteCommandWiring` 的 saveRecord 一调就崩，
      //   而留痕是执行链的每一格都要走的 ⇒ 每一次远程执行都失败。
      saveRecord: (record) =>
          DatabaseHelper().saveRemoteExecutionRecord(record),
    ),
  );
}

/// 把一段回执发给某个对端（远程执行的两段回执与「被拒」那一档都经这里）。
///
/// ⚠ **走协调者而不是自己造收货服务**：造一份 `FnthinkLoopSpec` 要契约、baseUri、
///   签名器、地址码、nonce 全套，而那些的唯一组装处是协调者 `_resolveSpec` ——
///   这里再拼一份就等于给同一个协议找第二个作者（背景引擎那条纪律的同一条）。
/// ⚠ 回 false = 没送出去。**调用方不许拿它改执行状态**：本机做完了就是做完了，
///   对面没收到是另一件事（`RemoteCommandRunner.sendReceipt` 那一格同一句话）。
Future<bool> _sendRemoteReceipt(
  GetIt getIt,
  String peer,
  RemoteReceipt receipt,
) async {
  try {
    final result = await getIt<FnthinkReceiveCoordinator>().sendNotice(
      peer: peer,
      title: 'fnthink',
      text: RemoteReceiptEnvelope.encode(
        result: receipt.result,
        level: receipt.level,
        item: receipt.item,
        argument: receipt.argument,
        state: receipt.state,
      ),
    );
    return result.status == FnthinkSendStatus.accepted;
  } catch (e) {
    return false;
  }
}

/// 「立刻推一次设备状态」那一发（`device_state:push`）。
///
/// ⚠ **发去哪几台不由这里判**（T132 片2）：这一发以前读一次快照、再把名单里**每一台**都发一遍，
///   于是「默认只发主、主全不可用才切备、NONE 那一档永不参与」这三条对它就都不成立 —— 判据只有
///   原生 `dispatchToChannels`/`ChannelRouting.route` 那一份（T12 的结论），Dart 再算一遍就会漂出
///   第二套路由，所以走 [NotificationService.pushSynthesizedRecord] 那一个入口，与设备快照页
///   「推送设备信息」那一格同一条链。
///
/// 回 `true` 的口径是**已交给推送链**，不是"已经送达"：送达结果要等原生回传，此刻任何
/// "成功/失败"的说法都是猜（那条纪律写在 `device_snapshot_page.dart` 的 `_push` 旁边）。
/// 回 `false` = 快照根本没读到；**不抛** —— 一条推不出去的动作不该让整次执行崩在半路
/// （那一格会记成 `threw:` 而不是没成的理由，两者查起来是两回事）。
Future<bool> _pushDeviceStateOnce() async {
  try {
    final device = getIt<DeviceInfoService>();
    final snapshot = await device.getDeviceSnapshot();
    if (snapshot == null) return false;
    await getIt<NotificationService>().pushSynthesizedRecord(
      title: 'device-state',
      content: jsonEncode(snapshot),
      deviceName: device.deviceName,
    );
    return true;
  } catch (e) {
    return false;
  }
}

/// 「回传最近 N 条通知原文」那段正文的产出（`notifications:report`，T124 片B）。
///
/// ⚠ 它是**读口**（开真库），组装那段在 `fnthink_notification_report.dart`（纯函数）——
/// 形状与读口分开，理由写在那份文件头上。
/// 回 null = 读不出来（库打不开、查询抛了）。**"一条都没有"不回 null**：
/// 那由产出自带一句明说（空表不是失败，见那份文件第二条口径）。
Future<String?> _fnthinkReportNotificationsOnce(int count) async {
  try {
    final rows = await DatabaseHelper().getNotifications(limit: count);
    return formatFnthinkNotificationReport(
      rows.map(NotificationRecord.fromMap).toList(),
    );
  } catch (e) {
    return null;
  }
}

/// 「在本机短信里按关键词搜」那一发（T124 片B 的 `sms:search`）。
///
/// ⚠ **开关关着 = 这一发不给做**（不是"搜了没命中"）：短信监听那一族默认关，而它读的是短信
/// 正文 —— 关着时**连库都不碰**，回一句 `sms-search-disabled`，让对面知道该去哪一台开。
/// ⚠ **不落任何新库**：查询直连系统短信库（`READ_SMS`），命中就回、不存副本。
/// 行里那句"在**已监听到的**短信里搜"今天没有对应的本地存储（SMS 一进一出、正文不落库），
/// 造一个等于新增一处短信正文的**留存点** —— 那是隐私面的决定，不在这一片里顺手做。
Future<({String? payload, String? reason})> _fnthinkSearchSmsOnce(
  String keyword,
) async {
  try {
    if (!getIt<SmsService>().smsMonitorEnabled) {
      return (payload: null, reason: 'sms-search-disabled');
    }
    final raw = await AppChannels.notification.invokeMethod<List<Object?>>(
      'searchFnthinkSms',
      {'keyword': keyword},
    );
    if (raw == null) {
      // 没给 READ_SMS / 被系统拒：原生回 null —— **与"空表"不同**（空表的含义是"搜了、没有"）。
      return (payload: null, reason: 'sms-search-refused');
    }
    final rows = raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
    return (payload: formatFnthinkSmsSearchReport(keyword, rows), reason: null);
  } catch (e) {
    return (payload: null, reason: 'sms-search-failed');
  }
}

/// 「在本机通话记录里按关键词搜」那一发（T124 片C 的 `calls:search`）。
///
/// ⚠ **两格都要过，次序固定：先本机开关，再系统权限**。
///  ① 本机那枚开关（`fnthink.read.calls`，默认关）关着 ⇒ `calls-search-disabled`，
///     **连库都不碰** —— 与 `sms:search` 同一条纪律；
///  ② 系统权限那一格在原生判（没给 READ_CALL_LOG 就回 null）⇒ `calls-search-refused`。
/// 两格分开的理由：它们对用户的下一步不一样（来这台打开开关 / 去系统里给权限）。
/// ⚠ **不落任何新库**：直查系统通话记录，命中就回、不存副本（与短信那一条同源）。
Future<({String? payload, String? reason})> _fnthinkSearchCallsOnce(
  String keyword,
) async {
  try {
    if (!await fnthinkReadCallsEnabled()) {
      return (payload: null, reason: 'calls-search-disabled');
    }
    final raw = await AppChannels.notification.invokeMethod<List<Object?>>(
      'searchFnthinkCallLog',
      {'keyword': keyword},
    );
    if (raw == null) {
      // 没给 READ_CALL_LOG / 被系统拒：原生回 null —— **与"空表"不同**（空表的含义是"搜了、没有"）。
      return (payload: null, reason: 'calls-search-refused');
    }
    final rows = raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
    return (payload: formatFnthinkCallLogReport(keyword, rows), reason: null);
  } catch (e) {
    return (payload: null, reason: 'calls-search-failed');
  }
}

/// 「读本机最近一次定位」那一发（T124 片C-2 的 `location:get`）。
///
/// ⚠ 与另两条同一纪律：**先本机开关、后系统权限**，两格的失败理由分开：
///  ① 开关（`fnthink.read.location`，默认关）关着 ⇒ `location-disabled`（连系统都不碰）；
///  ② 原生那格（没给 FINE/COARSE）⇒ `location-refused`；
///  ③ 有权限但**一条最近定位都没有** ⇒ `location-unavailable`（不是失败，也不是空话 ——
///     对面要能分辨"这台现在没有可读的定位"与"读这一步没做成"）。
/// ⚠ **只读"最近一次"**：这一发不主动去点 GPS（那是制造新采集，不是"读"）——
/// 详见原生 `LocationFix` 文件头。
Future<({String? payload, String? reason})> _fnthinkGetLocationOnce() async {
  try {
    if (!await fnthinkReadLocationEnabled()) {
      return (payload: null, reason: 'location-disabled');
    }
    final raw = await AppChannels.notification
        .invokeMethod<Map<Object?, Object?>>('getFnthinkLocation');
    if (raw == null) {
      // 没给权限 / 查询被拒：原生回 null —— 与"有权限但没有最近定位"（空表）不同。
      return (payload: null, reason: 'location-refused');
    }
    if (raw.isEmpty) {
      return (payload: null, reason: 'location-unavailable');
    }
    final fix = Map<String, Object?>.from(raw);
    final text = formatFnthinkLocationReport(fix);
    if (text.isEmpty) {
      // 有权限、也回了一条，但那一条里连坐标都取不出来 ⇒ 归到"读不出来"，
      // 不拿一个空串冒充"读到了"。
      return (payload: null, reason: 'location-failed');
    }
    return (payload: text, reason: null);
  } catch (e) {
    return (payload: null, reason: 'location-failed');
  }
}

/// 「让这台现在拍一张」那一发（T124 片C-3 的 `camera:snap`）。
///
/// ⚠ 与另三条同一纪律：**先本机开关、后系统权限**，各格理由分开：
///  ① 开关（`fnthink.read.camera`，默认关）关着 ⇒ `camera-snap-disabled`；
///  ② 原生那格没权限 ⇒ `camera-snap-refused`（原生回 null）；
///  ③ 这台**没有可见界面** ⇒ `camera-snap-no-foreground`（Android 9+ 后台不许开相机、
///     11+ 前台服务开相机还要专门类型与 while-in-use 许可 —— 那是另一条权限面，不顺手开）；
///  ④ 拍/存失败 ⇒ `camera-snap-failed`。
/// ⚠ 画面不回传（图像传输＋收件端渲染是另一个子系统）：产出是"拍到了、存在这台哪里"那段文字。
Future<({String? payload, String? reason})> _fnthinkSnapPhotoOnce() async {
  try {
    if (!await fnthinkReadCameraEnabled()) {
      return (payload: null, reason: 'camera-snap-disabled');
    }
    final raw = await AppChannels.notification
        .invokeMethod<Map<Object?, Object?>>('snapFnthinkPhoto');
    if (raw == null) {
      return (payload: null, reason: 'camera-snap-refused');
    }
    final snap = Map<String, Object?>.from(raw);
    if (snap['snap'] != true) {
      final why = '${snap['why'] ?? ''}';
      return (
        payload: null,
        reason: why == 'no-foreground'
            ? 'camera-snap-no-foreground'
            : 'camera-snap-failed',
      );
    }
    final text = formatFnthinkPhotoReport(snap);
    if (text.isEmpty) {
      return (payload: null, reason: 'camera-snap-failed');
    }
    return (payload: text, reason: null);
  } catch (e) {
    return (payload: null, reason: 'camera-snap-failed');
  }
}

/// 「在本机通讯录里按关键词搜」那一发（T124 片C-4 的 `contacts:search`）。
///
/// 与 `sms:search`／`calls:search` 同一纪律：**先本机开关、后系统权限**；
/// 开关关着连库都不碰（`contacts-search-disabled`）；原生那格没权限回 null
/// （`contacts-search-refused`）；**不落任何新库**：直查系统通讯录、命中就回。
Future<({String? payload, String? reason})> _fnthinkSearchContactsOnce(
  String keyword,
) async {
  try {
    if (!await fnthinkReadContactsEnabled()) {
      return (payload: null, reason: 'contacts-search-disabled');
    }
    final raw = await AppChannels.notification.invokeMethod<List<Object?>>(
      'searchFnthinkContacts',
      {'keyword': keyword},
    );
    if (raw == null) {
      return (payload: null, reason: 'contacts-search-refused');
    }
    final rows = raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => Map<String, Object?>.from(m))
        .toList(growable: false);
    return (
      payload: formatFnthinkContactsSearchReport(keyword, rows),
      reason: null,
    );
  } catch (e) {
    return (payload: null, reason: 'contacts-search-failed');
  }
}

/// 「打开本机登记过的一条入口」那一发（T124 片B 的 `app:launch`）。
///
/// ⚠ **按名字精确匹配，对不上就是不做**（`app-launch-unknown-name`）：猜一条最像的
/// 等于替用户开了一个他没点的东西，而那台设备上的用户看到的是一扇自己开了的门。
/// ⚠ 本机的清单**不出门**：只有"请你打开 <名字>"这一句过线，名字到目标的映射留在本机。
Future<({bool ok, String? reason})> _fnthinkLaunchShortcutOnce(
  String entryName,
) async {
  try {
    final rows = await loadFnthinkShortcuts();
    final hit = findFnthinkShortcut(rows, entryName);
    if (hit == null) return (ok: false, reason: 'app-launch-unknown-name');
    final launched = await AppChannels.notification.invokeMethod<bool>(
      'launchFnthinkTarget',
      {'target': hit.target},
    );
    final ok = launched ?? false;
    return (ok: ok, reason: ok ? null : 'app-launch-refused');
  } catch (e) {
    return (ok: false, reason: 'app-launch-failed');
  }
}

/// 厂商自启动那一条入口（`autostart`）—— 按本机厂商选那一个方法。///
/// ⚠ 厂商名做**小写包含**匹配而不是相等：各家在 `Build.MANUFACTURER` 里写的串
///   各不相同（`Xiaomi` / `Redmi` / `Xiaomi Inc.`…），相等匹配的表现是
///   "这台明明是小米、却说什么都没有"。
/// ⚠ 都对不上 ⇒ **不送任何一家**（什么都不做），而不是随便挑一个 ——
///   弹一个别的厂商的自启动页比不弹更糟（用户会被送进一个无关页面）。
Future<void> _requestVendorAutoStart(GetIt getIt) async {
  final maker = getIt<DeviceInfoService>().manufacturer.toLowerCase();
  final permissions = getIt<PermissionService>();
  if (maker.contains('xiaomi')) {
    await permissions.requestXiaomiAutoStart();
  } else if (maker.contains('meizu')) {
    await permissions.requestMeizuBackground();
  } else if (maker.contains('huawei')) {
    await permissions.requestHuaweiLaunch();
  } else if (maker.contains('oppo')) {
    await permissions.requestOppoBackground();
  } else if (maker.contains('vivo')) {
    await permissions.requestVivoBackground();
  }
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
