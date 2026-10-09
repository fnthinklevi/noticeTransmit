/// 「可被远程读取的内容」那几枚本机开关的**读写单点**（T124 片C）。
///
/// ## 为什么与系统权限是**两格**
/// 系统权限那一格回答的是"这个应用**能不能**读"（装在系统里、去设置里改）；
/// 这一格回答的是"这台设备的持有者**允不允许对面**读"（在本应用里随时可关，关掉立即生效）。
/// 两格都要过：只有权限没有开关 ⇒ 装上就默认允许对面读；只有开关没有权限 ⇒ 点了开也读不到。
///
/// ## 默认关（与短信监听那一族同一条纪律）
/// `?? false`：读不到就按**关**处理 —— 回退到开等于"没表过态就算同意过"。
///
/// ## 为什么不进备份/恢复
/// 备份恢复的是「意图」，而这几枚是**本机对"谁可以读这台什么"的一次表态**，
/// 与远程执行凭据同一类（那一份也不进备份，见 `fnthink_backup.dart` 文件头 ⑤）：
/// 恢复一份把它们打开的备份，等于**别人替这台设备表了态**。换机后重新开一次。
///
/// ## 键名只在这里出现
/// 页面与看门那一格（`service_locator.dart` 的那几发）都从这一处取：
/// 两处各写一份的表现是"界面上开着、执行时读到另一个键、判成关着"——而那种偏差
/// 在两个方向的用例里都是绿的。
library;

import 'package:shared_preferences/shared_preferences.dart';

/// 「远程可查通话记录」那一枚（`calls:search`）。
const String kFnthinkReadCallsKey = 'fnthink.read.calls';

/// 「远程可读最近一次定位」那一枚（`location:get`，T124 片C-2）。
const String kFnthinkReadLocationKey = 'fnthink.read.location';

/// 「远程可让这台拍一张」那一枚（`camera:snap`，T124 片C-3）。
const String kFnthinkReadCameraKey = 'fnthink.read.camera';

/// 读：缺键/读不到 ⇒ **关**（见文件头那条纪律）。
Future<bool> fnthinkReadCallsEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kFnthinkReadCallsKey) ?? false;
}

/// 写：开关的唯一作者（页面翻它）。
Future<void> setFnthinkReadCallsEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kFnthinkReadCallsKey, enabled);
}

/// 读：缺键/读不到 ⇒ **关**（同一条纪律，逐条各一枚键）。
Future<bool> fnthinkReadLocationEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kFnthinkReadLocationKey) ?? false;
}

/// 写：开关的唯一作者（页面翻它）。
Future<void> setFnthinkReadLocationEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kFnthinkReadLocationKey, enabled);
}

/// 读：缺键/读不到 ⇒ **关**（同一条纪律，逐条各一枚键）。
Future<bool> fnthinkReadCameraEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kFnthinkReadCameraKey) ?? false;
}

/// 写：开关的唯一作者（页面翻它）。
Future<void> setFnthinkReadCameraEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kFnthinkReadCameraKey, enabled);
}
