import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';

/// 桌面小部件添加引导页
///
/// Android 桌面小部件由各厂商桌面（Launcher）托管，系统没有统一 API
/// 允许应用代码直接添加到桌面，必须由用户手动添加。
/// Android 8.0+ 提供 requestPinAppWidget 可从应用内发起添加（系统弹窗确认），
/// 本页顶部提供「一键添加」入口（2×2 / 4×2 两种规格）。
///
/// 品牌适配：根据 [manufacturer] 自动识别当前设备品牌，把对应品牌的添加路径
/// 置顶展示并标记「当前设备」；一键添加失败且桌面不支持 pin 时，自动弹出
/// 当前品牌的分步引导对话框。
class WidgetGuidePage extends StatelessWidget {
  /// 设备厂商（Build.MANUFACTURER，来自 DeviceInfoService），空串表示未知
  final String manufacturer;

  const WidgetGuidePage({super.key, this.manufacturer = ''});

  // ===== 品牌识别（与 permission_settings_page 的判定口径保持一致） =====
  bool get _isXiaomi =>
      _m.contains('xiaomi') || _m.contains('redmi') || _m.contains('mi ');
  bool get _isHuawei => _m.contains('huawei') || _m.contains('honor');
  bool get _isOppo =>
      _m.contains('oppo') || _m.contains('realme') || _m.contains('oneplus');
  bool get _isVivo => _m.contains('vivo') || _m.contains('iqoo');
  bool get _isSamsung => _m.contains('samsung');

  String get _m => manufacturer.toLowerCase();

  Future<void> _requestPinWidget(
    BuildContext context, {
    required bool wide,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await AppChannels.notification.invokeMethod<bool>(
        'requestPinWidget',
        {'wide': wide},
      );
      if (ok == true) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.widgetPinSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // 发起失败：区分"桌面不支持 pin"（转品牌引导）与其他失败（提示重试）
      final supported = await AppChannels.notification.invokeMethod<bool>(
        'isPinWidgetSupported',
        {'wide': wide},
      );
      if (supported == false) {
        if (!context.mounted) return;
        await _showBrandGuideDialog(context, l10n);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.widgetPinUnsupported),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('requestPinWidget error: ${e.code} ${e.message}');
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.widgetPinLowApi),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 当前品牌的分步添加引导对话框
  Future<void> _showBrandGuideDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          l10n.widgetPinUnsupported,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        content: Text(
          _currentBrandGuide(l10n),
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: AppColors.primaryLabel(ctx),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.ok)),
        ],
      ),
    );
  }

  /// 当前设备品牌的添加路径文案；无法识别品牌时回退为通用手动添加步骤
  String _currentBrandGuide(AppLocalizations l10n) {
    if (_isXiaomi) return l10n.widgetBrandXiaomi;
    if (_isHuawei) return l10n.widgetBrandHuawei;
    if (_isOppo) return l10n.widgetBrandOppo;
    if (_isVivo) return l10n.widgetBrandVivo;
    if (_isSamsung) return l10n.widgetBrandSamsung;
    return [
      l10n.widgetGuideStep1,
      l10n.widgetGuideStep2,
      l10n.widgetGuideStep3,
    ].join('\n');
  }

  /// 分品牌路径内容：当前设备品牌置顶并标记「当前设备」，其余保持原顺序
  String _brandGuideContent(AppLocalizations l10n) {
    final current = <String>[];
    final others = <String>[];
    void add(bool matches, String text) {
      if (matches) {
        current.add('【${l10n.widgetBrandCurrentDevice}】$text');
      } else {
        others.add(text);
      }
    }

    add(_isXiaomi, l10n.widgetBrandXiaomi);
    add(_isHuawei, l10n.widgetBrandHuawei);
    add(_isOppo, l10n.widgetBrandOppo);
    add(_isVivo, l10n.widgetBrandVivo);
    add(_isSamsung, l10n.widgetBrandSamsung);
    others.add(l10n.widgetBrandOthers);

    if (current.isEmpty) return others.join('\n\n');
    return '${current.join('\n\n')}\n\n${others.join('\n\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: Text(l10n.widgetGuide)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 一键添加（推荐）：Android 8.0+ 系统弹窗确认
          _buildSection(
            title: l10n.widgetPinTitle,
            content: l10n.widgetPinDesc,
            context: context,
            trailing: Column(
              children: [
                _buildPinButton(
                  context: context,
                  label: l10n.widgetPinAction,
                  subtitle: l10n.widgetPin2x2,
                  wide: false,
                ),
                const SizedBox(height: 10),
                _buildPinButton(
                  context: context,
                  label: l10n.widgetPinWideAction,
                  subtitle: l10n.widgetPin4x2,
                  wide: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.widgetGuideDesc,
            content: l10n.widgetGuideIntro,
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.widgetGuide,
            content: [
              l10n.widgetGuideStep1,
              l10n.widgetGuideStep2,
              l10n.widgetGuideStep3,
            ].join('\n'),
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.widgetGuideBrand,
            content: _brandGuideContent(l10n),
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: l10n.widgetTipsTitle,
            content: [
              '• ${l10n.widgetTip1}',
              '• ${l10n.widgetTip2}',
              '• ${l10n.widgetTip3}',
              '• ${l10n.widgetTip4}',
            ].join('\n'),
            context: context,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPinButton({
    required BuildContext context,
    required String label,
    required String subtitle,
    required bool wide,
  }) {
    return Material(
      color: AppColors.systemBlue(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _requestPinWidget(context, wide: wide),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String content,
    required BuildContext context,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (trailing != null) ...[trailing, const SizedBox(height: 8)],
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ],
      ),
    );
  }
}
