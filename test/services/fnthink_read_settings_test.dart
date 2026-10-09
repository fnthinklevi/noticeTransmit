import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_read_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「可被远程读取的内容」那几枚本机开关的读写单点（T124 片C）。
///
/// 钉两件：
///  ① **默认关** —— 没写过 prefs 时读出来必须是 `false`
///     （回退到 true 就是"没表过态就算同意过"，与短信那一族同一条纪律）；
///  ② 往返是同一个键 —— 键名只在这一处出现（页面与看门那一格都从它取）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认关：没写过 prefs ⇒ false', () async {
    expect(await fnthinkReadCallsEnabled(), isFalse);
  });

  test('写 true / 写 false 都能读回来', () async {
    await setFnthinkReadCallsEnabled(true);
    expect(await fnthinkReadCallsEnabled(), isTrue);
    await setFnthinkReadCallsEnabled(false);
    expect(await fnthinkReadCallsEnabled(), isFalse);
  });

  test('键名是那一枚（跨进程/跨页面只许有一个作者）', () {
    expect(kFnthinkReadCallsKey, 'fnthink.read.calls');
  });

  test('put 过别的键不影响这一枚（缺键回退是关，不是"跟着别人走"）', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('some.other.key', true);
    expect(await fnthinkReadCallsEnabled(), isFalse);
  });
}
