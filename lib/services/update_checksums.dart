/// 更新包校验清单（Release 里的 `sha256sums.txt`）的地址合成与解析。
///
/// **为什么需要第二份 sha**：`version.json` 的 `sha256` 由 `release_local.sh`
/// 按**本地构建**的包回填，而 App 的 GitHub 兜底源（xget 镜像 / github.com）
/// 上是 **CI 构建**的包 —— 同一份源码、不同的构建环境，产物不是逐字节相同的
/// （2026-11-21 实测 v1.6.7 arm64：本地 30,323,579 / CI 30,323,482 字节）。
/// 拿 CDN 那份 sha 去判兜底包，正常下载也会被 N3 判成"损坏"并删除。
///
/// 约定：CI 在 Release 里同时上传 `sha256sums.txt`（`sha256sum` 格式），
/// 客户端走兜底源时就近取同一目录下这一份清单，按**文件名**取期望值；
/// 清单缺席（旧 Release）才退回"只验签名"——签名仍是可信根。
library;

/// 校验清单的文件名（CI 与解析侧共用这一个常量）。
const String checksumManifestName = 'sha256sums.txt';

/// 由某个 APK 的下载地址推出同目录清单地址；不是可解析地址时回 null。
///
/// 保序保留 scheme/host/其余路径段，只替换最后一段 —— xget 镜像与
/// github.com 直链都因此得到 `<release>/<tag>/sha256sums.txt`。
String? checksumManifestUrlFor(String apkUrl) {
  try {
    final uri = Uri.parse(apkUrl);
    // 必须是绝对地址：空串/相对路径下 pathSegments 会给出 ['']
    // 或推出一个没有 host 的 "sha256sums.txt"，那不是可下载的清单。
    if (!uri.hasScheme || uri.host.isEmpty) return null;
    final segments = List<String>.of(uri.pathSegments);
    if (segments.isEmpty || segments.last.isEmpty) return null;
    segments[segments.length - 1] = checksumManifestName;
    return uri.replace(pathSegments: segments).toString();
  } catch (_) {
    return null;
  }
}

/// 从 `sha256sum` 清单里取指定 APK 的期望 sha256（64 位小写十六进制）。
///
/// 查找顺序：
/// 1. 文件名逐字匹配（主路径：清单与下载地址来自同一个 Release）；
/// 2. 给了 [abi] 时按 `notice_<abi>_` 兜底（清单里的归档名与下载名不同时）；
/// 3. 都没有 ⇒ null（调用方跳过 sha，不猜一个哈希出来）。
///
/// 认不出的行（注释、坏哈希、空行）直接跳过，不让一行噪声否定整份清单。
String? pickSha256ForAsset(
  String manifest, {
  required String assetName,
  String? abi,
}) {
  final byName = <String, String>{};
  final linePattern = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$');
  for (final raw in manifest.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final match = linePattern.firstMatch(line);
    if (match == null) continue;
    final hash = match.group(1)!.toLowerCase();
    final name = match.group(2)!.trim().split('/').last.trim();
    if (name.isEmpty) continue;
    byName[name] = hash;
  }
  if (assetName.isNotEmpty && byName.containsKey(assetName)) {
    return byName[assetName];
  }
  if (abi != null && abi.isNotEmpty) {
    final needle = 'notice_${abi}_';
    for (final entry in byName.entries) {
      if (entry.key.contains(needle)) return entry.value;
    }
  }
  return null;
}
