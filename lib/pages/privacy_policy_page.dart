import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(title: const Text('隐私政策')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: '隐私政策概述',
            content:
                '通知推送助手（以下简称"本应用"）非常重视用户的隐私保护。本隐私政策将帮助您了解我们如何收集、使用和保护您的信息。',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '信息收集与使用',
            content:
                '本应用仅收集以下类型的信息：\n\n'
                '1. 崩溃统计信息\n'
                '   - 通过腾讯 Bugly SDK 收集应用崩溃时的堆栈信息\n'
                '   - 收集设备型号、系统版本、应用版本号、CPU 架构等基础信息\n'
                '   - 用于定位和修复崩溃问题，提升应用稳定性\n\n'
                '2. 通知内容（本地处理）\n'
                '   - 应用通过通知监听服务获取系统通知内容\n'
                '   - 所有通知内容仅在设备本地处理，不会上传到任何服务器\n'
                '   - 仅通过用户自行配置的 Webhook URL 进行推送',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '我们不收集的信息',
            content:
                '本应用不会收集以下个人隐私信息：\n\n'
                '• 通讯录、短信内容\n'
                '• 位置信息\n'
                '• 通话记录\n'
                '• 相册、文件\n'
                '• 麦克风、摄像头数据\n'
                '• 其他个人身份信息',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '数据存储与安全',
            content:
                '• 所有通知历史记录仅保存在设备本地\n'
                '• 配置数据仅保存在设备本地的 SharedPreferences 中\n'
                '• 不会将您的任何个人数据上传到开发者服务器\n'
                '• Webhook 推送通过您自行配置的地址发送，请确保您信任该地址',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '第三方服务',
            content:
                '本应用使用以下第三方服务：\n\n'
                '腾讯 Bugly（崩溃统计）\n'
                '• 服务商：深圳市腾讯计算机系统有限公司\n'
                '• 用途：收集应用崩溃信息，帮助定位和修复问题\n'
                '• 隐私政策：https://privacy.qq.com/\n'
                '• 采集数据：崩溃堆栈、设备型号、系统版本、应用版本',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '权限说明',
            content:
                '本应用申请的权限及其用途：\n\n'
                '• 通知访问权限：用于监听系统通知，实现推送功能\n'
                '• 网络权限：用于 Webhook 推送和版本更新检查\n'
                '• 前台服务：保活通知监听服务，确保消息及时推送\n'
                '• 开机自启动：开机后自动启动通知监听服务\n'
                '• 电量优化白名单：避免系统杀死后台服务',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '政策更新',
            content: '本隐私政策可能会不定期更新。更新后的政策将在应用内发布，继续使用即表示您同意更新后的政策。',
            context: context,
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              '最后更新：2026年7月2日',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String content,
    required BuildContext context,
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 10),
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
