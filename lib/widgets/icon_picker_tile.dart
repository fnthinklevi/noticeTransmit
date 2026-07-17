import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/icon_service.dart';

/// 真实图标预览：彩色圆角方底 + 实际铃铛字形（默认图标为白/深底 + 蓝铃）。
class AppIconPreview extends StatelessWidget {
  final IconOption option;
  final double size;
  const AppIconPreview({super.key, required this.option, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDefault = option.isDefault;
    final Color bg = isDefault
        ? (isDark ? const Color(0xFF1C1C1E) : Colors.white)
        : Color(option.color);
    final String bell = isDefault
        ? 'assets/icons/bell_blue.png'
        : 'assets/icons/bell_white.png';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.225),
        border: isDefault
            ? Border.all(color: AppColors.separator(context), width: 1)
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.22),
        child: Image.asset(
          bell,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

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

  Future<void> _select(IconOption opt) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await IconService.setIcon(opt.key);
    if (!mounted) return;
    setState(() => _current = opt.key);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '已切换至「${opt.label}」，桌面稍后刷新' : '切换失败')),
    );
  }

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
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 14,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),
              itemCount: IconService.options.length,
              itemBuilder: (_, i) {
                final opt = IconService.options[i];
                final selected = _current == opt.key;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _select(opt),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: selected
                                    ? AppColors.blue
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: AppIconPreview(option: opt, size: 44),
                          ),
                          if (selected)
                            const Positioned(
                              right: -4,
                              top: -4,
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: AppColors.blue,
                                child: Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        opt.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? AppColors.blue
                              : AppColors.secondaryLabel(context),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
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
            AppIconPreview(option: _currentOption, size: 30),
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
