import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// 统一的 compute isolate 编排入口
///
/// 与 [compute] 签名完全一致，作为全项目后台像素/解析计算的单一收敛点。
/// 约定：任务对象中的大字节块 (原始 RGBA / PNG 字节) 用 [IsolateBytes]
/// 包装，经 TransferableTypedData 零拷贝传输；小参数 (尺寸/枚举/配置)
/// 直接随消息拷贝。返回值中的大字节块同样用 [IsolateBytes] 包装回传。
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

/// 大字节块的零拷贝 isolate 传输容器
///
/// 构造时底层缓冲所有权转移给 [TransferableTypedData] (原列表变 detached，
/// 不可再用)，isolate 侧调用 [materialize] 取回字节；isolate 内用返回值
/// 构造 [IsolateBytes] 可零拷贝传回根 isolate。
///
/// 若传入的是大缓冲的切片视图 (offset 非零或长度不满)，会退化为一次
/// 精确拷贝以保证 materialize 长度语义正确。
class IsolateBytes {
  final TransferableTypedData _data;

  IsolateBytes(Uint8List bytes)
    : _data = TransferableTypedData.fromList([
        (bytes.offsetInBytes == 0 &&
                bytes.lengthInBytes == bytes.buffer.lengthInBytes)
            ? bytes
            : Uint8List.fromList(bytes),
      ]);

  /// 取回字节 (所有权一次性，只能调用一次)
  Uint8List materialize() => _data.materialize().asUint8List();
}
