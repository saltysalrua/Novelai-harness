import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// 统一的 compute isolate 编排入口
///
/// 与 [compute] 签名完全一致，作为全项目后台像素/解析计算的单一收敛点。
/// 约定：任务对象中的大字节块 (原始 RGBA / PNG 字节) 用 [IsolateBytes]
/// 包装，创建时复制一次、跨线程发送常数时间；小参数 (尺寸/枚举/配置)
/// 直接随消息拷贝。一次性 compute 返回的字节优先直接返回 Uint8List。
///
/// ```dart
/// final task = _Task(image: IsolateBytes(rgba), width: w, height: h);
/// final result = await runIsolated(_taskIsolate, task);
/// final out = result.materialize();
/// ```
///
/// 注意：常驻 worker isolate 暂缓——先统一入口，实测仍有卡顿再升级。
Future<R> runIsolated<Q, R>(R Function(Q) action, Q message) =>
    compute(action, message);

/// 跨 isolate 传输容器：fromList 会复制一次，发送/接收阶段为常数时间。
/// 输入原列表仍有效，不会 detached；切片视图也无需额外预复制。
/// compute 的返回值可直接用 Uint8List，利用 Isolate.exit 的所有权移交避免再次复制。
class IsolateBytes {
  final TransferableTypedData _data;

  IsolateBytes(Uint8List bytes)
    : _data = TransferableTypedData.fromList([bytes]);

  /// 取回字节 (所有权一次性，只能调用一次)
  Uint8List materialize() => _data.materialize().asUint8List();
}
