/// 幻念推送（fnthink push）。
///
/// 目前只有协议契约一层（T71）：`protocol/fnthink-v1.json` 是 Dart 与服务端共同的唯一真值，
/// 本包负责读它、取值、并检查它自己是否自洽。凭证三件套（T26）、配对（T28）、签名与验签（T29）
/// 依次落在这个包裡，主 App 以 path 依赖引入。
library;

export 'src/contract.dart';
