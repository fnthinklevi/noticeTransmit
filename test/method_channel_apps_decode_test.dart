// 回归测试：MethodChannel 返回应用列表（codec 解码为 List<dynamic>）后，
// Dart 端不同接收写法的类型安全。
//
// 背景：规则引擎「选择适用应用」页曾用 `final x = await channel.invokeMethod(...)`
// 无类型接收，T 推断为 dynamic；随后在 dynamic 接收器上动态调用泛型
// map().toList() 时类型参数实例化为 dynamic，得到 List<dynamic>，
// 赋给 List<Map<String, dynamic>>? 触发隐式 downcast：
//   type 'List<dynamic>' is not a subtype of type 'List<Map<String, dynamic>>?'
// 两个加载 try 块全部失败，页面应用列表恒为空（应用筛选页因显式 List<dynamic>
// 接收而正常）。本测试锁定正确解码写法。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('diag/installed_apps');

  // 模拟原生 getInstalledApps/getCachedInstalledApps 返回：
  // 经 StandardMethodCodec 编解码后接收侧实际为 List<Object?>（= List<dynamic>）
  void mockHandler(List<Map<String, dynamic>> payload) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => payload);
  }

  final sample = <Map<String, dynamic>>[
    <String, dynamic>{
      'packageName': 'com.a',
      'appName': 'A',
      'isSystemApp': false,
    },
    <String, dynamic>{
      'packageName': 'com.b',
      'appName': 'B',
      'isSystemApp': true,
    },
  ];

  setUp(() => mockHandler(sample));

  test('显式 List<dynamic> 接收 + 静态 map 转换（应用筛选页/规则页正确写法）', () async {
    final List<dynamic> cached = await channel.invokeMethod(
      'getCachedInstalledApps',
    );
    final apps = cached.map((e) => Map<String, dynamic>.from(e)).toList();
    expect(apps, isA<List<Map<String, dynamic>>>());
    expect(apps.length, 2);
    expect(apps.first['packageName'], 'com.a');
    expect(apps.last['isSystemApp'], isTrue);
  });

  test('as List 显式转型后 map（规则测试器页写法）', () async {
    final dynamic raw = await channel.invokeMethod('getInstalledApps');
    final apps = (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    expect(apps, isA<List<Map<String, dynamic>>>());
    expect(apps.map((a) => a['packageName']).toList(), ['com.a', 'com.b']);
  });

  test('反例：dynamic 接收 + 动态泛型 map 赋给 List<Map> 变量必抛 downcast 异常', () async {
    // 锁定根因：此写法编译可过但运行时必抛，防止后续代码再次出现
    List<Map<String, dynamic>>? apps;
    expect(() async {
      final cached = await channel.invokeMethod('getCachedInstalledApps');
      apps = cached.map((e) => Map<String, dynamic>.from(e)).toList();
    }, throwsA(isA<TypeError>()));
    expect(apps, isNull);
  });
}
