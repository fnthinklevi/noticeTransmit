import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/icon_service.dart';

class IconPickerTile extends StatefulWidget {
  const IconPickerTile({super.key});

  @override
  State<IconPickerTile> createState() => _IconPickerTileState();
}

class _IconPickerTileState extends State<IconPickerTile> {
  String _current = 'default';

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final cur = await IconService.getCurrent();
    if (mounted) setState(() => _current = cur);
  }

  IconOption get _currentOption => IconService.optionByKey(_current);

  void _openPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          '应用图标',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            ...IconService.options.map(
              (opt) => ListTile(
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await IconService.setIcon(opt.key);
                  if (!mounted) return;
                  setState(() => _current = opt.key);
                  Navigator.of(context).pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(ok ? '已切换至「${opt.label}」，桌面稍后刷新' : '切换失败'),
                    ),
                  );
                },
                leading: _Swatch(color: opt.color),
                title: Text(
                  opt.label,
                  style: TextStyle(color: AppColors.primaryLabel(context)),
                ),
                trailing: _current == opt.key
                    ? const Icon(Icons.check, color: AppColors.blue)
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openPicker,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _Swatch(color: _currentOption.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '应用图标',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '当前：${_currentOption.label}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.tertiaryLabel(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final int color;
  const _Swatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Color(color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.notifications_active,
        size: 18,
        color: Colors.white,
      ),
    );
  }
}
