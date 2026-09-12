import 'package:flutter/widgets.dart';

/// 懒加载视口 (PageView / 横滑卡片) 中的保活页壳。
///
/// PageView 视口默认 `cacheExtent = 0`：只有当前页会被构建，其余页在滑动
/// 离开视口时**整个 Element 树被卸载**。表现就是切页回来后滚动位置回顶、
/// 折叠状态与输入框高度一并被重置，与常驻页面 ([AppPageStack]) 的行为不一致。
///
/// 本组件把子页包成自动保活客户端，离开视口时保留 State 与 RenderObject，
/// 返回视口时原样复用；同时 [active] 为 false 的隐藏页暂停 Ticker，
/// 避免离屏动画空转。宿主视口必须开启 `addAutomaticKeepAlives`
/// (PageView / ListView 默认开启) 才会生效。
class AppKeepAlivePage extends StatefulWidget {
  final Widget child;

  /// 是否为当前可见页：false 时暂停离屏动画，交互本就被视口裁剪拦截。
  final bool active;

  const AppKeepAlivePage({super.key, required this.child, this.active = true});

  @override
  State<AppKeepAlivePage> createState() => _AppKeepAlivePageState();
}

class _AppKeepAlivePageState extends State<AppKeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(enabled: widget.active, child: widget.child);
  }
}
