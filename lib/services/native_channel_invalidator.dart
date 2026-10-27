import 'package:shared_preferences/shared_preferences.dart';

import 'platform_channel.dart';
import 'secure_storage_service.dart';

const String kChannelMirrorInvalidationPendingKey =
    'channel_mirror_invalidation_pending';

Future<bool> isChannelMirrorInvalidationPending() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getBool(kChannelMirrorInvalidationPendingKey) ?? false;
}

Future<void> invalidateNativeChannelMirrors() async {
  final began = await AppChannels.notification.invokeMethod<bool>(
    'invalidateChannelMirrors',
    {'phase': 'begin'},
  );
  if (began != true) {
    throw StateError('原生通道阻断未确认');
  }
  await SecureStorageService().delete('secure_webhook_channels');
  final confirmed = await AppChannels.notification.invokeMethod<bool>(
    'invalidateChannelMirrors',
    {'phase': 'finish'},
  );
  if (confirmed != true) {
    throw StateError('原生通道失效未确认');
  }
}
