import 'package:get_it/get_it.dart';
import '../services/webhook_service.dart';
import '../services/battery_service.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../services/filter_service.dart';
import '../services/update_service.dart';
import '../services/device_info_service.dart';
import '../services/retry_service.dart';
import '../state/app_state.dart';

final GetIt getIt = GetIt.instance;

void setupLocator() {
  getIt.registerLazySingleton<AppState>(() => AppState());
  getIt.registerLazySingleton<WebhookService>(() => WebhookService());
  getIt.registerLazySingleton<BatteryService>(() => BatteryService());
  getIt.registerLazySingleton<NotificationService>(() => NotificationService());
  getIt.registerLazySingleton<PermissionService>(() => PermissionService());
  getIt.registerLazySingleton<FilterService>(() => FilterService());
  getIt.registerLazySingleton<UpdateService>(() => UpdateService());
  getIt.registerLazySingleton<DeviceInfoService>(() => DeviceInfoService());
  getIt.registerLazySingleton<RetryService>(() => RetryService());
}
