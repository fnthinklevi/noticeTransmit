import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/sms_service.dart';
import '../theme/app_colors.dart';

/// 短信/来电监听设置页：总开关、监听卡选择（同时作用于短信和电话）、验证码开关
class SmsMonitorSettingsPage extends StatefulWidget {
  final SmsService smsService;

  const SmsMonitorSettingsPage({super.key, required this.smsService});

  @override
  State<SmsMonitorSettingsPage> createState() => _SmsMonitorSettingsPageState();
}

class _SmsMonitorSettingsPageState extends State<SmsMonitorSettingsPage> {
  late bool _smsMonitorEnabled;
  late String _simFilter;
  late bool _codeMonitorEnabled;

  @override
  void initState() {
    super.initState();
    _smsMonitorEnabled = widget.smsService.smsMonitorEnabled;
    _simFilter = widget.smsService.simFilter;
    _codeMonitorEnabled = widget.smsService.codeMonitorEnabled;
  }

  Future<void> _toggleSmsMonitor(bool value) async {
    setState(() => _smsMonitorEnabled = value);
    await widget.smsService.saveSmsMonitorEnabled(value);
  }

  Future<void> _toggleCodeMonitor(bool value) async {
    setState(() => _codeMonitorEnabled = value);
    await widget.smsService.saveCodeMonitorEnabled(value);
  }

  Future<void> _selectSimFilter(String value) async {
    setState(() => _simFilter = value);
    await widget.smsService.saveSimFilter(value);
    // 选择指定卡时提醒：部分短信（通知兜底链路）无法识别所属卡，设置对其无效
    if (value != 'all' && mounted) {
      final l10n = AppLocalizations.of(context);
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            l10n.simFilterRemindTitle,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(ctx),
            ),
          ),
          content: Text(
            l10n.simFilterRemindMsg,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.primaryLabel(ctx),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(
          l10n.smsMonitorSettings,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildSwitchCard(
            icon: Icons.sms_outlined,
            iconColor: AppColors.green,
            title: l10n.smsMonitor,
            subtitle: l10n.smsMonitorTotalDesc,
            value: _smsMonitorEnabled,
            onChanged: _toggleSmsMonitor,
          ),
          const SizedBox(height: 12),
          _buildSimFilterCard(l10n),
          const SizedBox(height: 12),
          _buildSwitchCard(
            icon: Icons.password,
            iconColor: AppColors.orange,
            title: l10n.codeMonitor,
            subtitle: l10n.codeMonitorDesc,
            value: _codeMonitorEnabled,
            onChanged: _toggleCodeMonitor,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// 监听卡选择：全部 / 仅卡1 / 仅卡2（分段按钮），同时作用于短信和电话。
  /// 单卡设备（simCardCount <= 1）时整体置灰，不可选择。
  Widget _buildSimFilterCard(AppLocalizations l10n) {
    final singleSim = widget.smsService.simCardCount <= 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sim_card, size: 20, color: AppColors.blue),
              const SizedBox(width: 8),
              Text(
                l10n.simFilterTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLabel(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            singleSim ? l10n.simFilterSingleSim : l10n.simFilterDesc,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: singleSim ? 0.4 : 1.0,
            child: AbsorbPointer(
              absorbing: singleSim,
              child: Row(
                children: [
                  _buildSimChip(l10n.simFilterAll, 'all'),
                  const SizedBox(width: 8),
                  _buildSimChip(l10n.simFilterSim1, '1'),
                  const SizedBox(width: 8),
                  _buildSimChip(l10n.simFilterSim2, '2'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimChip(String label, String value) {
    final selected = _simFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectSimFilter(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.blue.withValues(alpha: 0.12)
                : AppColors.inputBg(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.blue : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected
                  ? AppColors.blue
                  : AppColors.secondaryLabel(context),
            ),
          ),
        ),
      ),
    );
  }
}
