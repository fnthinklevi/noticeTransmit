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
                '本应用采用多层安全机制保护您的数据：\n\n'
                '1. 本地数据库加密\n'
                '   - 所有通知历史记录、推送统计使用 AES-256 加密存储\n'
                '   - 加密密钥保存在 Android 系统密钥库（AndroidKeyStore）中\n'
                '   - 即使设备被他人获取，也无法直接读取数据库内容\n\n'
                '2. 敏感配置加密\n'
                '   - Webhook URL（含企业微信、钉钉、飞书认证密钥）'
                '使用 AndroidKeyStore 加密存储\n'
                '   - 不会以明文形式保存在 SharedPreferences 中\n\n'
                '3. 网络传输安全\n'
                '   - 全站强制 HTTPS，禁止明文 HTTP 传输\n'
                '   - 已部署 SSL 证书固定（Certificate Pinning）基础设施\n'
                '   - 管理后台 Token 仅通过 HTTP Header 传递，不出现在 URL 中\n\n'
                '4. 其他安全措施\n'
                '   - 管理后台二步验证（TOTP）\n'
                '   - 应用备份已禁用，防止通知数据通过云备份泄露\n'
                '   - 应用内广播接收器已加固，防止外部伪造通知数据',
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
                '本应用遵循最小权限原则，仅申请必要权限：\n\n'
                '• 通知访问权限：用于监听系统通知，实现推送功能\n'
                '• 网络权限：用于 Webhook 推送和版本更新检查\n'
                '• 前台服务：保活通知监听服务，确保消息及时推送\n'
                '• 开机自启动：开机后自动启动通知监听服务\n'
                '• 电量优化白名单：避免系统杀死后台服务\n'
                '• 短信/电话状态：增强短信和来电通知类型识别（可选）\n\n'
                '已移除的权限（v1.5.40 安全加固）：\n'
                '• WiFi 状态变更（CHANGE_WIFI_STATE）\n'
                '• WiFi 状态读取（ACCESS_WIFI_STATE）\n'
                '• 网络状态变更（CHANGE_NETWORK_STATE）',
            context: context,
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: '政策更新',
            content:
                '本隐私政策可能会不定期更新。更新后的政策将在应用内发布，'
                '继续使用即表示您同意更新后的政策。',
            context: context,
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              '最后更新：2026年7月19日',
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
