part of 'history_page.dart';

// T184 B：行/通道配色、快捷屏蔽与服务定位。
// 纯搬移：函数体、判据、注释语义与拆分前一致。
// ignore_for_file: invalid_use_of_protected_member
extension _HistoryPageServices on _HistoryPageState {
  Color _getTypeColor(BuildContext context, String? type) {
    switch (type) {
      case 'sms':
        return AppColors.orange;
      case 'call_incoming':
      case 'call_answered':
      case 'call_ended':
        return AppColors.green;
      case 'wechat':
        return AppColors.brandWeChat;
      case 'qq':
        return AppColors.brandQQ;
      case 'alipay':
        return AppColors.brandAlipay;
      case 'system':
        return AppColors.secondaryLabel(context);
      case 'battery_charging':
      case 'battery_full':
      case 'battery_low_30':
      case 'battery_low_20':
        return AppColors.blue;
      default:
        return AppColors.indigo;
    }
  }

  Color _getAppColor(String appName) {
    if (appName.isEmpty) return AppColors.indigo;
    final hash = appName.hashCode;
    return AppColors.avatarPalette[hash.abs() % AppColors.avatarPalette.length];
  }

  Color _getChannelColor(BuildContext context, String channel) {
    // channel 是送达键（chan:<slug>），早期记录也可能是本地化显示名——channelKey
    // 两种都认。品牌色只从 `channel_visuals` 那张唯一表取：这里是第二个作者时，
    // 同一家企业微信在通道卡与历史行就会是两种绿（本仓实测过）。
    final slug = channelKey(channel);
    if (!hasChannelVisual(slug)) return AppColors.secondaryLabel(context);
    return channelVisual(slug).color;
  }

  // 状态那一格（词表→人话、词表→颜色）住 `services/delivery_display.dart`，
  // 是**唯一作者**（T150 片1）：这一页以前自己拿 `default:` 兜底成「发送中」，
  // 于是任何对不上号的状态串都会被界面替本机说一句"这条正在发"。

  bool _sameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  // ── 快捷屏蔽（长按记录菜单与详情页按钮共用）──

  FilterService get _filterService => GetIt.instance<FilterService>();

  /// 收件的读写一律从这一层走。页面上那句 `_dbHelper.loadFnthinkInbox(...)` 更短，代价是
  /// **排序口径与「标已读命中没有」各长一份** —— 首页入口卡的未读数与这里的行数迟早对不上。
  /// 写成 getter 而不是字段：注入替身的 widget 测试从不注册它，解析只能发生在默认分支上。
  FnthinkInboxService get _inboxService =>
      GetIt.instance<FnthinkInboxService>();

  /// 收件详情拆回传正文用的契约（T124② 片2）。注入优先；生产取 loader 的缓存，
  /// 还没加载好就返回 null（详情退化成正文原样显示，不藏消息）。
  FnthinkContract? _reportContract() {
    final injected = widget.reportContract;
    if (injected != null) return injected;
    if (!GetIt.instance.isRegistered<FnthinkContractLoader>()) return null;
    return GetIt.instance<FnthinkContractLoader>().cached;
  }
}
