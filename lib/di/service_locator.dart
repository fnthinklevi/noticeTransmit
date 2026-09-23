import 'package:get_it/get_it.dart';
import '../services/webhook_service.dart';
import '../services/battery_service.dart';
import '../services/temperature_service.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../services/filter_service.dart';
import '../services/update_service.dart';
import '../services/device_info_service.dart';
import '../services/theme_service.dart';
import '../services/email_service.dart';
import '../services/locale_service.dart';
import '../services/app_channel_service.dart';
import '../services/channel_descriptor_service.dart';
import '../services/channel_health_store.dart';
import '../services/installed_apps_service.dart';
import '../services/sms_service.dart';

final GetIt getIt = GetIt.instance;

void setupLocator() {
  getIt.registerLazySingleton<WebhookService>(() => WebhookService());
  getIt.registerLazySingleton<BatteryService>(() => BatteryService());
  getIt.registerLazySingleton<NotificationService>(() => NotificationService());
  getIt.registerLazySingleton<TemperatureService>(() => TemperatureService());
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
}
