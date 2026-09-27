import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 跨语言守卫（T26 第三片）：**同一个数字不许有两个出处**。
///
/// 这里对的是三处互不相识的文本：
///  - `protocol/fnthink-v1.json` 的 `identity.identityKey`（协议真值，双端契约测试读它）；
///  - Kotlin 里的 `NATIVE_MIN_SDK_VERSION` 与枚举的 `contractValue`（决定设备上走哪条路）；
///  - `android/app/build.gradle.kts` 的依赖坐标（30 以下那把曲线实现从哪来）。
///
/// 为什么值得钉：它们各自都对的时候，改一处另两处不会报错。门槛写成 24 的表现是
/// "一部分设备一生成身份就 NoSuchAlgorithmException"；依赖版本漂了的表现是
/// 协议声称用的是 A，实际编译进去的是 B —— 审计时看不出来。
void main() {
  const kotlinPath =
      'android/app/src/main/kotlin/com/fnthink/notice/FnthinkIdentityCodec.kt';
  const gradlePath = 'android/app/build.gradle.kts';
  const contractPath = 'protocol/fnthink-v1.json';

  final kotlin = File(kotlinPath);
  final gradle = File(gradlePath);

  test('三份文本都在（缺一个就等于守卫空转）', () {
    expect(kotlin.existsSync(), isTrue, reason: 'Kotlin 纯层被挪走了：$kotlinPath');
    expect(gradle.existsSync(), isTrue);
    expect(File(contractPath).existsSync(), isTrue);
  });

  group('契约 ↔ Kotlin', () {
    final source = kotlin.existsSync() ? kotlin.readAsStringSync() : '';
    final contract = File(contractPath).existsSync()
        ? File(contractPath).readAsStringSync()
        : '';

    test('API 门槛：Kotlin 的常量必须等于契约里那一个', () {
      final inKotlin = RegExp(
        r'const val NATIVE_MIN_SDK_VERSION\s*=\s*(\d+)',
      ).firstMatch(_withoutComments(source))?.group(1);
      final inContract = RegExp(
        r'"nativeMinSdkVersion"\s*:\s*(\d+)',
      ).firstMatch(contract)?.group(1);
      expect(inContract, isNotNull, reason: '契约里找不到 nativeMinSdkVersion');
      expect(
        inKotlin,
        inContract,
        reason: 'Kotlin=$inKotlin 契约=$inContract：门槛有两个出处，改一处另一处静默跟着',
      );
    });

    test('降级路径的名字：Kotlin 枚举的 contractValue 必须等于契约字符串', () {
      final inKotlin = RegExp(
        r'KEYSTORE_WRAPPED\("([^"]+)"\)',
      ).firstMatch(_withoutComments(source))?.group(1);
      final inContract = RegExp(
        r'"belowNativeSdk"\s*:\s*"([^"]+)"',
      ).firstMatch(contract)?.group(1);
      expect(inKotlin, inContract, reason: 'Kotlin=$inKotlin 契约=$inContract');
    });

    test('契约若被翻成"软件明文存私钥"，Kotlin 侧不许存在这个可返回的值', () {
      expect(
        RegExp('"softwarePlaintext"').hasMatch(_withoutComments(source)),
        isFalse,
        reason: 'Kotlin 里不许出现 softwarePlaintext 字面量：有它就能返回 true，红线名存实亡',
      );
    });
  });

  group('契约 ↔ 构建', () {
    final gradleText = gradle.existsSync() ? gradle.readAsStringSync() : '';
    final contract = File(contractPath).existsSync()
        ? File(contractPath).readAsStringSync()
        : '';

    test('30 以下用的曲线实现：契约声明的坐标必须就是编进去的那一个', () {
      final declared = RegExp(
        r'"softwareLibrary"\s*:\s*"([^"]+)"',
      ).firstMatch(contract)?.group(1);
      expect(declared, startsWith('net.i2p.crypto:eddsa:'));
      final applied = RegExp(
        r'implementation\("(net\.i2p\.crypto:eddsa:[^"]+)"\)',
      ).firstMatch(_stripGradleComments(gradleText))?.group(1);
      expect(
        applied,
        declared,
        reason: 'build.gradle.kts=$applied 契约=$declared',
      );
    });

    test('不许顺手把整套 BouncyCastle 拉进 app（体积与攻击面都太大）', () {
      expect(
        RegExp('implementation\\("org\\.bouncycastle').hasMatch(gradleText),
        isFalse,
        reason: '为一个 Ed25519 引一整套 provider 不值得；要引请单独决策并记进契约',
      );
    });
  });
}

/// 剥掉 // 与 /* */ 注释（守卫判的是代码，不是注释里的字）。
String _withoutComments(String source) {
  final out = StringBuffer();
  var inBlock = false;
  for (final line in source.split('\n')) {
    var text = line;
    if (inBlock) {
      if (text.contains('*/')) {
        text = text.substring(text.indexOf('*/') + 2);
        inBlock = false;
      } else {
        continue;
      }
    }
    while (text.contains('/*')) {
      out.write(text.substring(0, text.indexOf('/*')));
      final rest = text.substring(text.indexOf('/*') + 2);
      if (rest.contains('*/')) {
        text = rest.substring(rest.indexOf('*/') + 2);
      } else {
        text = '';
        inBlock = true;
      }
    }
    final lineComment = text.indexOf('//');
    if (lineComment >= 0) text = text.substring(0, lineComment);
    out.writeln(text);
  }
  return out.toString();
}

String _stripGradleComments(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');
