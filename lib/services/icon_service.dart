import 'package:flutter/services.dart';

class IconOption {
  final String key;
  final String label;
  final int color; // ARGB，用于预览色块
  const IconOption(this.key, this.label, this.color);
}

class IconService {
  static const _platform = MethodChannel('com.fnthink.notice/notification');

  static const List<IconOption> options = [
    IconOption('default', '经典蓝铃', 0xFF4070E0),
    IconOption('blue', '蓝色', 0xFF007AFF),
    IconOption('purple', '紫色', 0xFFAF52DE),
  ];

  static IconOption optionByKey(String key) {
    return options.firstWhere((o) => o.key == key, orElse: () => options.first);
  }

  static Future<String> getCurrent() async {
    try {
      final v = await _platform.invokeMethod('getLauncherIcon');
      return (v as String?) ?? 'default';
    } catch (_) {
      return 'default';
    }
  }

  static Future<bool> setIcon(String key) async {
    try {
      await _platform.invokeMethod('changeLauncherIcon', {'icon': key});
      return true;
    } catch (_) {
      return false;
    }
  }
}
