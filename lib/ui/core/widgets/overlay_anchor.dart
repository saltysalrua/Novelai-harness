/// 坐标换算原子工具：窗口全局坐标 ↔ Overlay 布局坐标系。
///
/// 全局 UI 缩放 ([AppUiZoomScope]) 会把 Navigator 及其 Overlay 整体放进
/// `窗口逻辑尺寸 / zoom` 的缩小坐标系。而指针事件的 `globalPosition` 与
/// `RenderBox.localToGlobal` 产出的是窗口逻辑坐标——直接拿去给
/// OverlayEntry 的 `Positioned` 定位 (或与 `MediaQuery.sizeOf` 比较)，
/// 菜单/浮层会偏移 zoom 倍 (放大时飞向右下、缩小时挤向左上)。
///
/// 统一经 Overlay 的 `RenderBox.globalToLocal` 做逆变换，
/// 对任意祖先变换 (含 UI 缩放) 都天然正确，zoom=1.0 时退化为恒等。
library;

import 'package:flutter/material.dart';

/// 把窗口全局坐标换算成指定 [overlay] 布局坐标系下的位置。
///
/// [overlay] 必须已挂载且完成布局；否则原样返回全局坐标兜底。
Offset globalToOverlayPosition(OverlayState overlay, Offset global) {
  final box = overlay.context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.globalToLocal(global);
  }
  return global;
}

/// 便捷入口：取 [context] 所在 Overlay (默认根 Overlay) 并把窗口全局坐标
/// 换算成该 Overlay 布局坐标系下的位置。
Offset globalToOverlayOf(
  BuildContext context,
  Offset global, {
  bool rootOverlay = true,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: rootOverlay);
  return overlay == null ? global : globalToOverlayPosition(overlay, global);
}
