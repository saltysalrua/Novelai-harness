import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_progress_bar.dart';

/// 侧边栏页面标题与副标题 (参数设置 / 提示词管理页首复用)
class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const PageHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// 参数小节标题 (模型 / Seed / Sampler 等)
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.colors.textPrimary,
      ),
    );
  }
}

/// 轻量"清空"文字按钮 (提示词输入框右上角复用)
class ClearTextLink extends StatelessWidget {
  final VoidCallback onTap;

  const ClearTextLink({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          '清空',
          style: TextStyle(fontSize: 11, color: context.colors.textMuted),
        ),
      ),
    );
  }
}

/// 按 NovelAI 分词规则粗略估算提示词 Token 数 (上限按模型分词器区分)
int estimatePromptTokens(String text, {int limit = 225}) {
  if (text.trim().isEmpty) return 0;
  final parts = text.split(RegExp(r'[,，\s\n]+')).where((s) => s.isNotEmpty);
  return (parts.length * 1.35).round().clamp(0, limit);
}

/// 提示词 Token 占用进度条 (上限按模型)
class TokenProgressBar extends StatelessWidget {
  final int tokens;
  final int tokenLimit;

  const TokenProgressBar({
    super.key,
    required this.tokens,
    this.tokenLimit = 225,
  });

  @override
  Widget build(BuildContext context) {
    return AppProgressBar(
      value: (tokens / tokenLimit).clamp(0.0, 1.0),
      height: 3,
    );
  }
}
