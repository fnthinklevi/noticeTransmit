/// 幻念推送（fnthink push）。
///
/// 第一层是协议契约（T71）：`protocol/fnthink-v1.json` 是 Dart 与服务端共同的唯一真值，
/// 本包负责读它、取值、并检查它自己是否自洽。第二层是凭证（T26）：地址码与配对口令的
/// 生成/归一化/摘要，跨端一致性由 `protocol/fnthink-vectors-v1.json` 双端各断言一遍。
/// 配对（T28）、签名与验签（T29）、能力清单（T30）、投递状态机（T34）依次落在这个包里，
/// 主 App 以 path 依赖引入。
library;

export 'src/canonical_bytes.dart';
export 'src/capabilities.dart';
export 'src/contract.dart';
export 'src/credentials.dart';
export 'src/delivery.dart';
export 'src/pairing.dart';
export 'src/receive_kernel.dart';
export 'src/remote_command.dart';
export 'src/send_kernel.dart';
export 'src/title_envelope.dart';
export 'src/crockford.dart';
