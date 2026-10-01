import 'package:fnthink_push/fnthink_push.dart' show FnthinkContract;
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'channel_config_codec.dart';
import 'fnthink_contract_loader.dart';
import 'fnthink_settings.dart';

/// 备份里那一格「幻念推送」（T59）。
///
/// **判据（维护者 2026-10-01 定，覆盖此前口径）：备份恢复的是「意图」，
/// 不恢复「身份」，也不携带「凭证」。**
///
/// 进这一格的只有四项：接收总开关、所选服务地址、同意门的版本号（第几版中转政策）、
/// 用户选的那一档收取间隔（T88 之后）。
/// 能力档位与端点的名字要等 T49 —— 本机此刻还没有"可存的那一份"，与其写一个空键占位，
/// 不如等真的有值再进（写了就是"备份里有这一类"的假承诺）。
///
/// 绝不进（每一条都有理由，守卫 `test/architecture/fnthink_backup_privacy_guard_test.dart` 钉住）：
/// ① **Ed25519 身份私钥** —— KeyStore 里的密钥物理不可导出，而且两台设备共用一个身份会
///    破坏服务端「地址码 ↔ 公钥」的一对一；
/// ② **配对口令与端点口令** —— 端点口令是长期凭证（不像配对口令几分钟过期），泄露即等于
///    任何人都能往这台手机推通知，而服务端只存摘要、**无法归因**。也不做"显式勾选才进 +
///    提示风险"那一支：勾选项的真实用户是"愿意勾的人"，代价却由"文件将来泄露的那一天"付，
///    而备份的流转路径恰恰最不可控（云备份／微信传文件／U 盘／恢复码）。
///    替代方案更便宜：换机后重建端点 + 重新配对（T87 的教程与一键复制正是为这件事准备的）；
/// ③ **可信发送方名单（peers）** —— 恢复过来的名单配的是一把不在新机 KeyStore 里的私钥，
///    表现是界面显示"已配对"而一发就签不出来；
/// ④ **收件标题与正文**（第三方隐私，里面常常就是验证码）与**发出记录**（那是历史不是配置）。
///
/// ⚠ 恢复完必须告诉用户一件事：**NAS 上那条 curl 会开始 401** —— 端点口令不在这份备份里，
/// 得重建端点并把新口令填回 NAS。这句要出现在发版说明与帮助页（"换机要做的三件事"之一）。
///
/// 这一层只做"读哪几个键、怎么写回"，所以它只依赖 SharedPreferences：
/// 备份那两套测试工装没有数据库、也没有随包资产（#181 那个 blocker 的真身就是"直连
/// `FnthinkPeerService` ⇒ 整片红"），把这一格做成 prefs-only 之后，两条路都不需要新抽象。
class FnthinkBackup {
  /// [requiredConsentVersion] 是"该恢复同意门吗"那个判据的注入口，默认从已装配的契约读。
  /// 之所以留这个口：备份的两套测试工装既没有随包资产也没有数据库（#181 那个 blocker 的
  /// 真身），而"版本号不够就不恢复"这一档必须能被演出来 —— 不许因为测不到就写成"总是恢复"。
  FnthinkBackup({
    FnthinkContractLoader? contractLoader,
    int? Function()? requiredConsentVersion,
  }) : _injected = contractLoader,
       _required = requiredConsentVersion;

  final FnthinkContractLoader? _injected;
  final int? Function()? _required;

  /// 类别名（`BackupService` 的三处对称都以它为键）。
  static const category = 'fnthink';
  static const fieldReceiveEnabled = 'receive_enabled';
  static const fieldHost = 'host';
  static const fieldConsentVersion = 'consent_version';

  /// 用户选的那一档收取间隔（T88 之后才有意义；没选过就不写这个键）。
  /// 归到「意图」而不是「身份」：它说的是"这台希望多久问一次货"，不带任何凭证，
  /// 越界的那一档由 [apply] 按契约范围判掉（宁可不恢复也不写进 prefs）。
  static const fieldPollSeconds = 'poll_seconds';

  /// 已装配好的那一份契约（null = 现在读不到）。
  ///
  /// 只读 `cached`、不触发一次资产 IO：恢复链上没有"为了问一个版本号/一对范围去读包内文件"
  /// 的理由，而装配链（收货循环 / 幻念页）本来就会把它读到。
  FnthinkContract? get _cachedContract {
    final loader = _injected ?? _fromLocator();
    return loader?.cached;
  }

  /// 契约取不到时的返回：`null` 表示"没法判断该不该恢复同意" ⇒ 一律**不恢复**（fail-closed）。
  ///
  /// 没装配时宁可让用户再点一次同意，也不替他点（T56 那条不变量）。
  int? get _requiredConsentVersion {
    if (_required != null) return _required();
    final value = _cachedContract?.intOf(const [
      'privacy',
      'relayConsentVersion',
    ]);
    return (value == null || value <= 0) ? null : value;
  }

  FnthinkContractLoader? _fromLocator() {
    try {
      return GetIt.instance<FnthinkContractLoader>();
    } catch (_) {
      // 未注册（早期启动 / 测试环境）⇒ 与"契约没读到"同处理：不恢复同意门。
      return null;
    }
  }

  /// 收集。总是给出这一类（`receive_enabled` 缺省 `false`），但只写**本机真有的值**：
  /// 地址与同意版本没设过就不写键 —— 省得恢复时把"空"当成"用户选了空地址"。
  Future<Map<String, dynamic>> collect() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      fieldReceiveEnabled:
          prefs.getBool(FnthinkSettings.keyReceiveEnabled) ?? false,
      ...{
        if (prefs.getString(FnthinkSettings.keyHost) case final String host
            when host.isNotEmpty)
          fieldHost: host,
        if (prefs.getInt(FnthinkSettings.keyConsentVersion)
            case final int version)
          fieldConsentVersion: version,
        if (prefs.getInt(FnthinkSettings.keyPollSeconds) case final int poll)
          fieldPollSeconds: poll,
      },
    };
  }

  /// 这台到底配过幻念推送没有（冲突判定用：从没配过的设备，恢复时这一格不算"会覆盖掉东西"）。
  Future<bool> hasContent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(FnthinkSettings.keyReceiveEnabled) == true ||
        prefs.getString(FnthinkSettings.keyHost) != null ||
        prefs.getInt(FnthinkSettings.keyConsentVersion) != null ||
        prefs.getInt(FnthinkSettings.keyPollSeconds) != null;
  }

  /// 形状兜底：文件是外部输入，值类型不受控。缺项一律**不写键**（保持本机现值），
  /// 坏地址也丢掉 —— 落一个非法主机名进 prefs，代价是收货循环一路 400 而没人怀疑到设置上。
  static Map<String, dynamic> normalize(Map<dynamic, dynamic> raw) {
    final out = <String, dynamic>{};
    if (raw[fieldReceiveEnabled] case final bool enabled) {
      out[fieldReceiveEnabled] = enabled;
    }
    if (ChannelConfigCodec.nullableText(raw[fieldHost])
        case final String host) {
      try {
        out[fieldHost] = FnthinkSettings.validateHost(host);
      } on FnthinkSettingsInvalid {
        // 坏地址：宁可不恢复，也不写进 prefs
      }
    }
    if (raw[fieldConsentVersion] case final num version) {
      out[fieldConsentVersion] = version.toInt();
    }
    // 间隔这一档只判类型，范围留给 apply：那一半需要契约（min/max 的唯一作者），
    // 而 `normalize` 是静态的形状兜底，手里没有契约。
    if (raw[fieldPollSeconds] case final num seconds) {
      out[fieldPollSeconds] = seconds.toInt();
    }
    return out;
  }

  /// 落回本机。返回 `null` = 全部按预期恢复；返回一句话 = 有一项**没有**恢复，
  /// 由 `BackupService` 原样放进恢复报告（这一格最容易"悄悄没恢复"的就是同意门）。
  Future<String?> apply(Map<String, dynamic> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (values[fieldReceiveEnabled] case final bool enabled) {
      await prefs.setBool(FnthinkSettings.keyReceiveEnabled, enabled);
    }
    if (values[fieldHost] case final String host) {
      // 再校验一次：`normalize` 是主路径上的兜底，但这一格也可能被别的调用方直接喂值
      // （写进 prefs 的坏主机名会以"一路 400"的形式回来，代价全在用户那侧）。
      await prefs.setString(
        FnthinkSettings.keyHost,
        FnthinkSettings.validateHost(host),
      );
    }
    // 两项"可能没恢复"的各自留一句说明，最后并成一行 —— 只报第一条的话，
    // 用户会以为其余那一项已经回来了。
    final notes = <String>[];
    if (values[fieldConsentVersion] case final int granted) {
      final required = _requiredConsentVersion;
      if (required != null && granted >= required) {
        await prefs.setInt(FnthinkSettings.keyConsentVersion, granted);
      } else {
        notes.add(
          '接收开关与服务地址已恢复，但**中转同意没有恢复**：这份备份记的是第 $granted 版，'
          '而本机现在要求 ${required ?? '读不到契约（装配未完成）'} —— 要重新点一次同意，'
          '否则服务器那头的每一发都会被本机挡下。',
        );
      }
    }
    if (values[fieldPollSeconds] case final int seconds) {
      // 范围判据来自契约（min/max 的唯一作者）。读不到契约或那一档越界 ⇒ **不写**：
      // 写进 prefs 的代价是这台被服务端按额度持续 429，而界面上只显示"收不到货"。
      final contract = _cachedContract;
      if (contract == null) {
        notes.add('收取间隔那一档也没有恢复：本机现在读不到契约，没有可校验的范围。');
      } else {
        try {
          await prefs.setInt(
            FnthinkSettings.keyPollSeconds,
            contract.checkedPollIntervalSeconds(seconds),
          );
        } on StateError catch (e) {
          notes.add('收取间隔那一档没有恢复：${e.message}');
        }
      }
    }
    return notes.isEmpty ? null : notes.join('；');
  }
}

/// 恢复这一格时"有一项没成"的说明（不带栈、也不是异常控制流 —— 就是要原样进报告那一行）。
class FnthinkRestorePartial implements Exception {
  const FnthinkRestorePartial(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
