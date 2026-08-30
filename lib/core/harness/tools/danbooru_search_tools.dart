import 'dart:async';

import '../../../data/models/tag_models.dart';
import '../../../data/services/danbooru_search_service.dart';
import '../types.dart';
import 'agent_tool.dart';

/// 工具执行超时兜底 (服务层已各自设了 60~120s 超时，这里再垫一层)
Future<T> _withToolTimeout<T>(Future<T> future, Duration timeout) async {
  try {
    return await future.timeout(timeout);
  } on TimeoutException {
    throw const DanbooruSearchException('请求超时，请稍后重试或简化查询');
  }
}

/// 1. Danbooru 语义搜词工具 (中文/英文自然语言描述 -> 标准标签)
///
/// 数据源为 SAkizuki/DanbooruSearch (HF Space 公开 API)，基于 4 维语义向量
/// 匹配，支持模糊描述、拼写容错与中文查词。适合把「想要什么画面」的
/// 自然语言转成 Danbooru 标签，与离线词库的前缀补全互补。
class DanbooruSearchTagsTool extends AgentTool {
  final DanbooruSearchService _service;

  DanbooruSearchTagsTool({DanbooruSearchService? service})
    : _service = service ?? DanbooruSearchService.instance,
      super(
        name: 'danbooru_search_tags',
        label: 'Danbooru 语义搜词',
        description:
            '用中文或英文的自然语言描述查找对应的 Danbooru 标准标签。'
            '基于语义向量匹配，支持模糊概念、整段画面描述、拼写容错与中文查询'
            '（例如"白色水手服的少女"或"雨中奔跑的城市街道"）。'
            '查询单一概念时结果更精准；返回标签附中文名、热度与一句话简介。'
            '注意：语义检索较慢（10~30 秒），不要在单轮对话里高频调用。',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': '自然语言描述或概念（中文或英文均可）'},
            'limit': {'type': 'integer', 'description': '返回条数上限（默认 20，最大 80）'},
            'use_segmentation': {
              'type': 'boolean',
              'description':
                  '是否开启智能分词：开启后自动拆分长句中的概念分别检索再合并'
                  '（适合完整画面描述）；查询单一概念时设为 false 更精准（默认 true）',
            },
          },
          'required': ['query'],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：查询描述不能为空。',
        isError: true,
      );
    }

    final limit = ((args['limit'] as num?)?.toInt() ?? 20).clamp(1, 80);
    final seg = args['use_segmentation'] as bool? ?? true;

    try {
      final results = await _withToolTimeout(
        _service.searchTags(query, limit: limit, useSegmentation: seg),
        const Duration(seconds: 100),
      );

      if (results.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '未找到与 "$query" 匹配的标签，可尝试更具体的描述。',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('语义搜词 "$query" 结果：');
      for (final r in results) {
        final zh = r.cnHead;
        buffer.writeln(
          '- ${r.tag}${zh != null ? ' ($zh)' : ''}'
          ' [热度: ${formatTagCount(r.count)}${r.category != DanbooruTagCategory.general ? ' / ${r.category.label}' : ''}]'
          '${r.wiki.isNotEmpty ? ' -- ${r.wiki}' : ''}',
        );
      }
      return ToolResult(
        toolCallId: toolCallId,
        content: buffer.toString().trim(),
      );
    } on DanbooruSearchException catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '语义搜词失败: ${e.message}',
        isError: true,
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '语义搜词失败: $e',
        isError: true,
      );
    }
  }
}

/// 2. Danbooru 关联推荐工具 (标签共现)
///
/// 给定若干已选标签，返回 Danbooru 图库中经常与它们共同出现的关联标签
/// (NPMI 共现，已过滤纯热度噪声)，辅助补全画面细节与角色特征。
class DanbooruRelatedTagsTool extends AgentTool {
  final DanbooruSearchService _service;

  DanbooruRelatedTagsTool({DanbooruSearchService? service})
    : _service = service ?? DanbooruSearchService.instance,
      super(
        name: 'danbooru_related_tags',
        label: 'Danbooru 关联推荐',
        description:
            '给定一组 Danbooru 标签，推荐在图库中经常与它们共同出现的关联标签'
            '（基于共现统计，NPMI 评分）。适合补全画面细节、查角色典型特征'
            '（服装/配件/表情）、或探索某主题的标签体系。支持多个标签组合取交集推荐。'
            '输入拼写错误会自动纠错为标准标签。响应约需 10~30 秒。',
        parameters: {
          'type': 'object',
          'properties': {
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '种子标签列表（Danbooru 英文标签名，如 ["maid", "twintails"]）',
            },
            'limit': {'type': 'integer', 'description': '返回条数上限（默认 20，最大 200）'},
            'category': {
              'type': 'string',
              'enum': ['General', 'Character', 'Copyright', 'Artist', 'Meta'],
              'description': '可选：仅返回指定类别的标签（默认不过滤）',
            },
          },
          'required': ['tags'],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final rawTags = args['tags'];
    final tags = rawTags is List
        ? rawTags
              .map((e) => e.toString().trim())
              .where((t) => t.isNotEmpty)
              .toList()
        : <String>[];
    if (tags.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：种子标签列表不能为空。',
        isError: true,
      );
    }

    final limit = ((args['limit'] as num?)?.toInt() ?? 20).clamp(1, 200);
    final category = switch (args['category'] as String?) {
      'Character' => DanbooruTagCategory.character,
      'Copyright' => DanbooruTagCategory.copyright,
      'Artist' => DanbooruTagCategory.artist,
      'Meta' => DanbooruTagCategory.meta,
      _ => null,
    };

    try {
      final corrections = <String, String>{};
      final results = await _withToolTimeout(
        _service.relatedTags(
          tags,
          limit: limit,
          categories: category != null ? [category] : null,
          corrections: corrections,
        ),
        const Duration(seconds: 70),
      );

      if (results.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content:
              '未找到与 ${tags.join(', ')} 关联的标签'
              '${corrections.isNotEmpty ? '（已自动纠错: ${corrections.entries.map((e) => '${e.key}->${e.value}').join(', ')}）' : ''}。',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('关联推荐（种子: ${tags.join(', ')}）：');
      if (corrections.isNotEmpty) {
        buffer.writeln(
          '已自动纠错: ${corrections.entries.map((e) => '${e.key} -> ${e.value}').join(', ')}',
        );
      }
      for (final r in results) {
        final zh = r.cnHead;
        buffer.writeln(
          '- ${r.tag.replaceAll('_', ' ')}${zh != null ? ' ($zh)' : ''}'
          '${r.wiki.isNotEmpty ? ' -- ${r.wiki}' : ''}'
          '${r.sources.isNotEmpty ? ' [来自: ${r.sources.join(',')}]' : ''}',
        );
      }
      return ToolResult(
        toolCallId: toolCallId,
        content: buffer.toString().trim(),
      );
    } on DanbooruSearchException catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '关联推荐失败: ${e.message}',
        isError: true,
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '关联推荐失败: $e',
        isError: true,
      );
    }
  }
}

/// 3. 推荐擅长画师工具 (标签-画师 NPMI 共现)
///
/// 给定标签列表，推荐擅长绘制这些元素的画师，附共现次数与该画师
/// 最常绘制的标签画像，可直接用于提示词的 artist: 或 by_ 画风控制。
class DanbooruRecommendArtistsTool extends AgentTool {
  final DanbooruSearchService _service;

  DanbooruRecommendArtistsTool({DanbooruSearchService? service})
    : _service = service ?? DanbooruSearchService.instance,
      super(
        name: 'danbooru_recommend_artists',
        label: '推荐擅长画师',
        description:
            '给定一组 Danbooru 标签（角色/画风/画面元素），推荐擅长绘制这些内容的画师'
            '（基于标签-画师 NPMI 共现统计）。适合根据角色或风格标签找画师、'
            '为提示词加入画师串。返回画师名、共现次数与其最常绘制的标签。'
            '注意：该查询较慢（30~60 秒），单轮对话调用一次即可。',
        parameters: {
          'type': 'object',
          'properties': {
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': '种子标签列表（如 ["flat_color", "1girl"] 或角色标签）',
            },
            'limit': {
              'type': 'integer',
              'description': '返回画师数量上限（默认 12，最大 100）',
            },
            'min_cooc': {
              'type': 'integer',
              'description': '单个 (标签, 画师) 对的最小共现次数门槛（默认 3）',
            },
          },
          'required': ['tags'],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final rawTags = args['tags'];
    final tags = rawTags is List
        ? rawTags
              .map((e) => e.toString().trim())
              .where((t) => t.isNotEmpty)
              .toList()
        : <String>[];
    if (tags.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：种子标签列表不能为空。',
        isError: true,
      );
    }

    final limit = ((args['limit'] as num?)?.toInt() ?? 12).clamp(1, 100);
    final minCooc = ((args['min_cooc'] as num?)?.toInt() ?? 3).clamp(1, 100);

    try {
      final corrections = <String, String>{};
      final results = await _withToolTimeout(
        _service.recommendArtists(
          tags,
          limit: limit,
          minCooc: minCooc,
          corrections: corrections,
        ),
        const Duration(seconds: 130),
      );

      if (results.isEmpty) {
        return ToolResult(
          toolCallId: toolCallId,
          content:
              '未找到擅长绘制 ${tags.join(', ')} 的画师'
              '${corrections.isNotEmpty ? '（已自动纠错: ${corrections.entries.map((e) => '${e.key}->${e.value}').join(', ')}）' : ''}，'
              '可尝试更通用的标签或降低 min_cooc 门槛。',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('擅长绘制 ${tags.join(', ')} 的画师推荐：');
      if (corrections.isNotEmpty) {
        buffer.writeln(
          '已自动纠错: ${corrections.entries.map((e) => '${e.key} -> ${e.value}').join(', ')}',
        );
      }
      for (final r in results) {
        buffer.writeln(
          '- ${r.artist} (共现: ${r.coocCount}, 总作品: ${formatTagCount(r.postCount)}'
          '${r.sources.isNotEmpty ? ', 命中: ${r.sources.join(',')}' : ''})',
        );
        if (r.topTags.isNotEmpty) {
          buffer.writeln('  常画: ${r.topTags.take(8).join(', ')}');
        }
      }
      return ToolResult(
        toolCallId: toolCallId,
        content: buffer.toString().trim(),
      );
    } on DanbooruSearchException catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '画师推荐失败: ${e.message}',
        isError: true,
      );
    } catch (e) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '画师推荐失败: $e',
        isError: true,
      );
    }
  }
}
