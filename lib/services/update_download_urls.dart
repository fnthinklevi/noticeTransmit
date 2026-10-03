/// 更新包下载地址的合成（T66 后续片）。
///
/// ⚠ **这一层存在的唯一理由**：归档文件名此前在三个地方各自"猜"过
/// （`_buildDownloadUrls` 猜 `notice_all_<version>.apk`、`_buildCandidateUrls` 猜
/// `notice_<平台>_<version>.apk`、CI 与本地发版脚本各写一份真实名字）。
/// 命名规则一改，猜的那两处就静默 404 —— 而它们只在 CDN 主地址挂掉时才被走到，
/// 日常一条用例都摸不到。这里把规则收成一处：**镜像上的资产名沿用主地址里那一个**，
/// 因为主地址与镜像上的是**同一个文件**（发版脚本一次构建、两处归档）。
library;

/// 把 version.json 下发的下载地址补成绝对地址（`serverUrl` 为 null 时原样返回）。
String absoluteUpdateUrl(String url, {String? serverUrl}) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (serverUrl == null || serverUrl.isEmpty) return url;
  if (url.startsWith('/')) return '$serverUrl$url';
  return '$serverUrl/$url';
}

/// 主下载地址里那一份 APK 的**文件名**。
///
/// 返回 null 表示"这不是一个 .apk 路径" ⇒ 调用方**不该**再拼镜像地址：
/// 猜一个名字出来，比不猜更坏（它看起来像个可用地址，只有真去下载时才发现是 404）。
String? apkAssetNameOf(String downloadUrl, {String? serverUrl}) {
  try {
    final segments = Uri.parse(
      absoluteUpdateUrl(downloadUrl, serverUrl: serverUrl),
    ).pathSegments;
    if (segments.isEmpty) return null;
    final last = segments.last;
    return last.endsWith('.apk') ? last : null;
  } catch (_) {
    return null;
  }
}

/// 镜像上的候选地址（顺序 = 传入的 `mirrors` 顺序）。
///
/// 每个地址都是 `<mirrorBase>/<version>/<主地址那一份的文件名>`。
/// 拿不到文件名、或没有版本 ⇒ 回空列表（不猜）。
/// [skip] 给调用方留一个"这一路今天不该走"的闸（如缺必需的上下文时）。
List<String> buildMirrorApkUrls({
  required String downloadUrl,
  required String? version,
  required List<String> mirrorBases,
  String? serverUrl,
  bool skip = false,
}) {
  final urls = <String>[];
  if (skip) return urls;
  if (version == null || version.isEmpty) return urls;
  final asset = apkAssetNameOf(downloadUrl, serverUrl: serverUrl);
  if (asset == null) return urls;
  for (final base in mirrorBases) {
    final trimmed = base.trim();
    if (trimmed.isEmpty) continue;
    final url = '$trimmed/$version/$asset';
    if (!urls.contains(url)) urls.add(url);
  }
  return urls;
}
