import 'package:flutter/material.dart';
import '../../../../data/models/tag_models.dart';
import '../../../../data/services/prompt_ast_engine.dart';

/// 提示词光标操作工具 (快捷键与快捷按钮共用)
///
/// 统一收敛“定位光标所在标签 -> 执行 AST 变换 -> 写回控制器”的流程，
/// 由 ResizableTextField 的键盘快捷键与 PromptEditorCard 的快捷按钮复用。
class PromptEditActions {
  PromptEditActions._();

  /// 定位光标所在标签并执行变换，成功时写回控制器并触发 onChanged
  static bool _applyTokenOp(
    TextEditingController controller,
    ValueChanged<String> onChanged,
    (String, int) Function(String text, NaiPromptToken tok) op,
  ) {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid || text.isEmpty) return false;

    final tokens = PromptAstEngine.parsePromptTokens(text);
    final idx = PromptAstEngine.tokIndexAt(text, selection.start, tokens);
    if (idx < 0 || idx >= tokens.length) return false;

    final (newText, newCursor) = op(text, tokens[idx]);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: newCursor.clamp(0, newText.length),
      ),
    );
    onChanged(newText);
    return true;
  }

  /// 光标所在标签数值权重 ±0.1 (`Ctrl+Up` / `Ctrl+Down`)
  static void adjustWeight(
    TextEditingController controller,
    ValueChanged<String> onChanged, {
    required bool up,
  }) {
    _applyTokenOp(
      controller,
      onChanged,
      (text, tok) => PromptAstEngine.adjustNumericWeight(
        text,
        tok,
        up: up,
        cursorOffset: controller.selection.start,
      ),
    );
  }

  /// 切换光标所在标签禁用状态 (`Ctrl+/`)
  static void toggleDisabled(
    TextEditingController controller,
    ValueChanged<String> onChanged,
  ) {
    _applyTokenOp(controller, onChanged, (text, tok) {
      final newText = PromptAstEngine.toggleDisabled(text, tok);
      return (newText, controller.selection.start);
    });
  }

  /// 全文格式化与 SD 语法转换 (`Ctrl+Shift+F`)
  static void formatPrompt(
    TextEditingController controller,
    ValueChanged<String> onChanged,
  ) {
    final text = controller.text;
    if (text.isEmpty) return;

    final newText = PromptAstEngine.formatAndBeautify(text);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    onChanged(newText);
  }
}
