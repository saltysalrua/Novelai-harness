import 'package:flutter/material.dart';
import '../../../core/theme/theme_context_extensions.dart';

/// 带可见性切换的密钥输入框 (NovelAI Key / LLM Key 复用)
///
/// 阶段 3 垂直切片后本文件仅存此件：卡片/下拉/操作钮/分组标题等旧组件
/// 已全部由 `lib/ui/core/widgets/` 原子组件 (AppSettingTile / AppDropdown /
/// AppActionButton / AppSectionHeader) 接管，此处只保留尚无原子对应物的密钥框。
class SettingsKeyField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final double width;

  const SettingsKeyField({
    super.key,
    required this.controller,
    required this.hintText,
    this.width = 250,
  });

  @override
  State<SettingsKeyField> createState() => _SettingsKeyFieldState();
}

class _SettingsKeyFieldState extends State<SettingsKeyField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: widget.width,
      height: 36,
      child: TextField(
        controller: widget.controller,
        obscureText: _obscure,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: widget.hintText,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off : Icons.visibility,
              size: 15,
              color: colors.textMuted,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
    );
  }
}
