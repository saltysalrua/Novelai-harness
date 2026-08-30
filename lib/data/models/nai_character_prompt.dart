/// NovelAI 多角色提示词与位置布局模型 (V4+ 多角色隔离)。
library;

/// 多角色自动布局 (归一化坐标 X=水平 Y=垂直，与 Aaalice NAI Launcher 的
/// CharacterPositionLayout 规则一致)
abstract final class NaiCharacterPositionLayout {
  /// V4/V4.5 官方网格定位的量化步长 (5x5 网格 → 1/4 步长)
  static double gridQuantize(double value) {
    return ((value.clamp(0.0, 1.0) * 4).round() / 4);
  }

  /// 按启用角色数量返回稳定的默认位置列表
  static List<({double x, double y})> positionsForCount(int count) {
    switch (count) {
      case <= 0:
        return const [];
      case 1:
        return const [(x: 0.5, y: 0.5)];
      case 2:
        return const [(x: 0.25, y: 0.5), (x: 0.75, y: 0.5)];
      case 3:
        return const [(x: 0.2, y: 0.5), (x: 0.5, y: 0.5), (x: 0.8, y: 0.5)];
      case 4:
        return const [
          (x: 0.25, y: 0.25),
          (x: 0.75, y: 0.25),
          (x: 0.25, y: 0.75),
          (x: 0.75, y: 0.75),
        ];
      case 5:
        return const [
          (x: 0.2, y: 0.2),
          (x: 0.8, y: 0.2),
          (x: 0.5, y: 0.5),
          (x: 0.2, y: 0.8),
          (x: 0.8, y: 0.8),
        ];
      case 6:
        return const [
          (x: 0.2, y: 0.25),
          (x: 0.5, y: 0.25),
          (x: 0.8, y: 0.25),
          (x: 0.2, y: 0.75),
          (x: 0.5, y: 0.75),
          (x: 0.8, y: 0.75),
        ];
      default:
        return List.generate(count, (index) {
          const columns = 3;
          final rows = (count / columns).ceil();
          final row = index ~/ columns;
          final column = index % columns;
          return (x: (column + 1) / (columns + 1), y: (row + 1) / (rows + 1));
        });
    }
  }

  /// 取第 index 个 (共 total 个) 角色的自动位置
  static ({double x, double y}) positionForIndex(int index, int total) {
    final positions = positionsForCount(total);
    if (index >= 0 && index < positions.length) return positions[index];
    return const (x: 0.5, y: 0.5);
  }

  /// 钨制到 [0.0, 1.0] 区间
  static double clamp(double value) => value.clamp(0.0, 1.0);
}

/// 角色性别预设 (官方添加角色的三个预设：女 / 男 / 其他)
enum NaiCharacterGender {
  female('女'),
  male('男'),
  other('其他');

  final String label;
  const NaiCharacterGender(this.label);

  /// 解析持久化/工具传回的性别名，未知值回退到 other
  static NaiCharacterGender fromName(String? name) {
    return NaiCharacterGender.values.firstWhere(
      (g) => g.name == name,
      orElse: () => NaiCharacterGender.other,
    );
  }
}

/// 单个角色提示词 (V4+ 多角色物理防串色隔离)
///
/// 仅 V4 及以上模型生效：发送 characterPrompts 与 v4_prompt 的
/// char_captions，v3 模型会直接忽略。位置默认由 AI 自动布局，
/// 开启自定义后按 5x5 网格坐标发送。
class NaiCharacterPrompt {
  /// 8 位十六进制短 ID，供 UI 与 Agent 工具稳定引用
  final String id;

  /// 显示名 (不进入 payload，仅本地标识)
  final String name;

  /// 角色正向提示词
  final String prompt;

  /// 角色专属负面提示词
  final String negativePrompt;

  /// 是否参与生成
  final bool enabled;

  /// 是否被手动指定过坐标 (仅当全局关闭 AI 自动布局时生效；
  /// 官方 AI's Choice 下角色定位全部由模型自行安排)
  final bool useCustomPosition;

  /// 自定义坐标 X (0.0=最左 1.0=最右，仅 useCustomPosition 为 true 时生效)
  final double positionX;

  /// 自定义坐标 Y (0.0=最上 1.0=最下)
  final double positionY;

  /// 官方三预设添加角色时的默认角色负面提示词 (与 Aaalice 启动器一致)
  static const String presetNegativePrompt = 'lowres, aliasing, ';

  const NaiCharacterPrompt({
    required this.id,
    required this.name,
    this.prompt = '',
    this.negativePrompt = '',
    this.enabled = true,
    this.useCustomPosition = false,
    this.positionX = 0.5,
    this.positionY = 0.5,
  });

  static int _idCounter = 0;

  /// 生成新角色的 8-hex 短 ID
  static String generateId() {
    final ms = DateTime.now().millisecondsSinceEpoch & 0xFFFFFF;
    return ((ms << 8) | ((++_idCounter) & 0xFF))
        .toRadixString(16)
        .padLeft(8, '0');
  }

  /// 新建角色 (自动命名 + 自动布局)
  factory NaiCharacterPrompt.create({
    String? name,
    String prompt = '',
    String negativePrompt = '',
  }) {
    return NaiCharacterPrompt(
      id: generateId(),
      name: name ?? 'Character',
      prompt: prompt,
      negativePrompt: negativePrompt,
    );
  }

  /// 解析该角色实际发送的坐标：自定义坐标优先，否则按启用顺序自动布局
  ({double x, double y}) resolveCenter(int enabledIndex, int enabledTotal) {
    if (useCustomPosition) {
      return (
        x: NaiCharacterPositionLayout.clamp(positionX),
        y: NaiCharacterPositionLayout.clamp(positionY),
      );
    }
    return NaiCharacterPositionLayout.positionForIndex(
      enabledIndex,
      enabledTotal,
    );
  }

  NaiCharacterPrompt copyWith({
    String? id,
    String? name,
    String? prompt,
    String? negativePrompt,
    bool? enabled,
    bool? useCustomPosition,
    double? positionX,
    double? positionY,
  }) {
    return NaiCharacterPrompt(
      id: id ?? this.id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      enabled: enabled ?? this.enabled,
      useCustomPosition: useCustomPosition ?? this.useCustomPosition,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'negativePrompt': negativePrompt,
    'enabled': enabled,
    'useCustomPosition': useCustomPosition,
    'positionX': positionX,
    'positionY': positionY,
  };

  factory NaiCharacterPrompt.fromJson(Map<String, dynamic> json) {
    double parseDouble(String key, double fallback) {
      final raw = json[key];
      return raw is num ? raw.toDouble() : fallback;
    }

    return NaiCharacterPrompt(
      id: json['id'] as String? ?? NaiCharacterPrompt.generateId(),
      name: json['name'] as String? ?? 'Character',
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: json['negativePrompt'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      useCustomPosition: json['useCustomPosition'] as bool? ?? false,
      positionX: parseDouble('positionX', 0.5),
      positionY: parseDouble('positionY', 0.5),
    );
  }
}
