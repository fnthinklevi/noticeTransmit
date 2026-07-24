import 'platform_channel.dart';

class IconOption {
  final String key;
  final String label;
  final int color; // ARGB，图标背景色（预览用）
  const IconOption(this.key, this.label, this.color);

  /// 默认图标（跟随主题的白/深底 + 蓝铃），预览需特殊处理
  bool get isDefault => key == 'default';
}

class IconService {
  static const _channel = AppChannels.notification;

  static const List<IconOption> options = [
    IconOption('default', '默认图标', 0xFF4070E0),
    IconOption('blue', '蓝色', 0xFF007AFF),
    IconOption('cyan', '天蓝', 0xFF32ADE6),
    IconOption('teal', '青色', 0xFF30B0C7),
    IconOption('mint', '薄荷', 0xFF00C7BE),
    IconOption('green', '绿色', 0xFF34C759),
    IconOption('yellow', '黄色', 0xFFFFCC00),
    IconOption('orange', '橙色', 0xFFFF9500),
    IconOption('red', '红色', 0xFFFF3B30),
    IconOption('pink', '粉色', 0xFFFF2D55),
    IconOption('rose', '玫红', 0xFFE91E63),
    IconOption('purple', '紫色', 0xFFAF52DE),
    IconOption('indigo', '靛蓝', 0xFF5856D6),
    IconOption('brown', '棕色', 0xFFA2845E),
    IconOption('gray', '灰色', 0xFF8E8E93),
    IconOption('graphite', '深灰', 0xFF48484A),
    IconOption('black', '墨黑', 0xFF1C1C1E),
  ];

  static IconOption optionByKey(String key) {
    return options.firstWhere((o) => o.key == key, orElse: () => options.first);
  }

  static Future<String> getCurrent() async {
    try {
      final v = await _channel.invokeMethod('getLauncherIcon');
      return (v as String?) ?? 'default';
    } catch (_) {
      return 'default';
    }
  }

  static Future<bool> setIcon(String key) async {
    try {
      await _channel.invokeMethod('changeLauncherIcon', {'icon': key});
      return true;
    } catch (_) {
      return false;
    }
  }
}
