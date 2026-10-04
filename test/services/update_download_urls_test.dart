import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/update_download_urls.dart';

import '../support/source_guards.dart';

/// T66 后续：更新包镜像地址的合成（**命名规则只有一处**）。
///
/// ⚠ 这一组存在的理由是一条很贵的静默失败：归档文件名此前在两个地方按版本号**猜**过
/// （`notice_all_<版本>.apk` 与 `notice_<平台>_<版本>.apk`）。T66 给真实归档名加了构件号
/// （`notice_arm64_1.5.76+117.apk`），那两个猜出来的名字当场变成 404 ——
/// 而它们只在 CDN 主地址挂掉时才被走到，所以本地与 CI 都测不出来。
/// 现在的规则是：**镜像上那一份沿用主地址的文件名**（本来就是同一个文件），
/// 拿不到文件名就一个地址都不产（宁可不回退，也不给界面一个看起来能用、实际 404 的地址）。
void main() {
  const cdnApk =
      'https://cdn.example.test/app/notice/update/1.5.76/notice_arm64_1.5.76+117.apk';
  const mirror = 'https://github.example.test/o/r/releases/download';

  group('镜像地址沿用主地址的文件名', () {
    test('带构件号的归档名原样带到镜像上，不是按版本号猜的那一个', () {
      final urls = buildMirrorApkUrls(
        downloadUrl: cdnApk,
        version: '1.5.76',
        mirrorBases: [mirror],
      );
      expect(urls, ['$mirror/v1.5.76/notice_arm64_1.5.76+117.apk']);
      expect(
        urls.single,
        isNot(contains('notice_all_1.5.76.apk')),
        reason: '这就是 T66 之前那个猜出来的名字：它 404，而没一条用例会走到',
      );
    });

    test('两个镜像按传入顺序产出，重复的那一份只留一次', () {
      final urls = buildMirrorApkUrls(
        downloadUrl: cdnApk,
        version: '1.5.76',
        mirrorBases: [mirror, mirror, '  $mirror  '],
      );
      expect(urls, hasLength(1));
      final two = buildMirrorApkUrls(
        downloadUrl: cdnApk,
        version: '1.5.76',
        mirrorBases: [
          mirror,
          'https://direct.example.test/o/r/releases/download',
        ],
      );
      expect(two.first, startsWith(mirror));
      expect(two.last, startsWith('https://direct.example.test'));
    });

    test('相对主地址先补 serverUrl，再取那一份的文件名', () {
      final urls = buildMirrorApkUrls(
        downloadUrl: '/app/notice/update/1.5.76/notice_all_1.5.76+117.apk',
        version: '1.5.76',
        serverUrl: 'https://cdn.example.test',
        mirrorBases: [mirror],
      );
      expect(urls, ['$mirror/v1.5.76/notice_all_1.5.76+117.apk']);
    });
  });

  group('拿不到文件名就一个都不产', () {
    test('主地址不是 .apk ⇒ 空列表（不猜一个名字给界面当"可用地址"）', () {
      expect(
        buildMirrorApkUrls(
          downloadUrl: 'https://cdn.example.test/app/latest',
          version: '1.5.76',
          mirrorBases: [mirror],
        ),
        isEmpty,
      );
    });

    test('version 缺失或为空 ⇒ 空列表', () {
      for (final v in [null, '']) {
        expect(
          buildMirrorApkUrls(
            downloadUrl: cdnApk,
            version: v,
            mirrorBases: [mirror],
          ),
          isEmpty,
          reason: '没有版本号就拼不出 tag 段，硬拼会造出一个指向错误 tag 的地址',
        );
      }
    });

    test('skip=true ⇒ 空（这一路今天不该走，例如缺必需的上下文）', () {
      expect(
        buildMirrorApkUrls(
          downloadUrl: cdnApk,
          version: '1.5.76',
          mirrorBases: [mirror],
          skip: true,
        ),
        isEmpty,
      );
    });

    test('主地址解析不了 ⇒ 不抛异常，回空列表', () {
      expect(
        apkAssetNameOf('http://[bad-url'),
        isNull,
        reason: '这里抛出去，表现是"检查更新"整条流程红 —— 一个坏地址不该拖垮别的路',
      );
      expect(
        buildMirrorApkUrls(
          downloadUrl: 'http://[bad-url',
          version: '1.5.76',
          mirrorBases: [mirror],
        ),
        isEmpty,
      );
    });

    test('镜像 base 为空串或全空格 ⇒ 不产出空地址', () {
      expect(
        buildMirrorApkUrls(
          downloadUrl: cdnApk,
          version: '1.5.76',
          mirrorBases: ['', '   '],
        ),
        isEmpty,
        reason: '一条空地址会被当成"第一个下载源"，失败得莫名其妙',
      );
    });
  });

  group('命名规则只有一处', () {
    test('update_manager 里不许再出现拼出来的 APK 文件名', () {
      final src = File('lib/update_manager.dart').readAsStringSync();
      final offenders = <String>[];
      for (final (i, line) in src.split('\n').indexed) {
        final code = line.split('//').first;
        if (code.contains(r'notice_')) {
          offenders.add('${i + 1}: ${code.trim()}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '镜像上那一份沿用主地址的文件名；再拼一次就是第二份命名规则，'
            '而它不会跟着发版脚本改（T66 就是这么坏的）',
      );
    });
  });

  group('Release 的 tag 段（#234）', () {
    test('versionName 不带 v ⇒ tag 段补上（CI 只对 refs/tags/v 建 Release）', () {
      expect(releaseTagFor('1.5.76'), 'v1.5.76');
    });

    test('已经带 v 的原样返回（幂等：不许拼成 vv1.5.76）', () {
      expect(releaseTagFor('v1.5.76'), 'v1.5.76');
    });

    test('空/空白/null ⇒ null（不猜一个 tag 出来）', () {
      expect(releaseTagFor(null), isNull);
      expect(releaseTagFor(''), isNull);
      expect(releaseTagFor('   '), isNull);
    });

    test('⚠ 合成出来的候选地址里 tag 段只有一个 v，且与文件名的版本号一致', () {
      // 这一条钉的是**整条形状**：文件名里的版本号不带 v（那是 pubspec 的口径），
      // 而目录段带 v（那是 tag 的口径）。两者混成一个就是 404。
      final urls = buildMirrorApkUrls(
        downloadUrl: 'https://cdn.example.test/app/notice_arm64_1.5.76+117.apk',
        version: '1.5.76',
        mirrorBases: ['https://gh.example.test/o/r/releases/download'],
      );
      expect(urls, hasLength(1));
      final url = urls.single;
      expect(url, contains('/v1.5.76/'));
      expect(url.contains('/vv'), isFalse, reason: 'tag 段前缀被拼了两次');
      expect(
        url.endsWith('notice_arm64_1.5.76+117.apk'),
        isTrue,
        reason: '文件名沿用主地址那一份，它的版本号不带 v —— 两个口径各管一段',
      );
    });

    test('CI 的建 Release 那一格仍然认 v 前缀（两边不会各自漂掉）', () {
      // 读 CI 源文件本身：`startsWith(github.ref, 'refs/tags/v')` 一旦改了，
      // 这里就红 —— 而不是等到某次 CDN 挂掉、回退地址 404 才���现。
      final workflow = File(
        '${projectRoot()}/.github/workflows/build-apk.yml',
      ).readAsStringSync();
      expect(
        workflow.contains("startsWith(github.ref, 'refs/tags/v')"),
        isTrue,
        reason: 'CI 不再只对 v 开头的 tag 建 Release ⇒ tag 段的前缀要与它对齐',
      );
    });
  });
}
