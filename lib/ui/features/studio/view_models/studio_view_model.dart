import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/harness/agent_harness.dart';
import '../../../../core/harness/providers/openai_provider.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../../core/harness/tools/novelai_tools.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/repositories/novelai_repository.dart';
import '../../../../data/services/config_service.dart';

class StudioViewModel extends ChangeNotifier {
  final ConfigService _configService;
  final NovelAiRepository _repository;
  late final ToolRegistry _toolRegistry;
  late final AgentHarness _harness;

  AppConfig _config = const AppConfig();
  NaiGenerationParams _params = const NaiGenerationParams(prompt: '');
  NaiAccountInfo? _accountInfo;
  bool _isLoadingAccount = false;
  bool _isGenerating = false;
  bool _isChatStreaming = false;
  String _currentStreamingThoughts = '';
  String _currentStreamingContent = '';
  NaiGeneratedImage? _selectedImage;
  String? _statusMessage;
  String? _errorMessage;

  StudioViewModel({
    ConfigService? configService,
    NovelAiRepository? repository,
  })  : _configService = configService ?? ConfigService(),
        _repository = repository ?? NovelAiRepository() {
    _toolRegistry = ToolRegistry();
    _harness = AgentHarness(
      tools: _toolRegistry,
      initialSkill: BuiltinSkills.v5PromptArchitect,
    );
  }

  // Getters
  AppConfig get config => _config;
  NaiGenerationParams get params => _params;
  NaiAccountInfo? get accountInfo => _accountInfo;
  bool get isLoadingAccount => _isLoadingAccount;
  bool get isGenerating => _isGenerating;
  bool get isChatStreaming => _isChatStreaming;
  String get currentStreamingThoughts => _currentStreamingThoughts;
  String get currentStreamingContent => _currentStreamingContent;
  NaiGeneratedImage? get selectedImage => _selectedImage;
  List<NaiGeneratedImage> get gallery => _repository.history;
  List<AgentMessage> get messages => _harness.messages;
  Skill get currentSkill => _harness.currentSkill;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;

  /// 初始化 Studio
  Future<void> init() async {
    _config = await _configService.loadConfig();

    _params = NaiGenerationParams(
      prompt: '',
      negativePrompt: _config.negativePrompt,
      model: _config.defaultModel,
      width: _config.customWidth,
      height: _config.customHeight,
      steps: _config.defaultSteps,
      scale: _config.defaultScale,
      cfgRescale: _config.defaultCfgRescale,
      sampler: _config.defaultSampler,
      noiseSchedule: _config.defaultNoiseSchedule,
      prefixPrompt: _config.prefixPrompt,
      suffixPrompt: _config.suffixPrompt,
    );

    _setupHarnessAndTools();
    notifyListeners();

    // 后台加载账号信息
    if (_config.novelAiKey.isNotEmpty) {
      await refreshAccountInfo();
    }
  }

  void _setupHarnessAndTools() {
    // 注册工具
    _toolRegistry.register(
      NovelAiGenerateTool(
        repository: _repository,
        configService: _configService,
        onGenerated: (image) {
          _selectedImage = image;
          notifyListeners();
        },
      ),
    );
    _toolRegistry.register(
      NovelAiUpscaleTool(
        repository: _repository,
        configService: _configService,
        onUpscaled: (image) {
          _selectedImage = image;
          notifyListeners();
        },
      ),
    );
    _toolRegistry.register(
      NovelAiSuggestTagsTool(
        repository: _repository,
        configService: _configService,
      ),
    );
    _toolRegistry.register(
      NovelAiAccountInfoTool(
        repository: _repository,
        configService: _configService,
      ),
    );

    // 配置 LLM Provider
    if (_config.llmApiKey.isNotEmpty) {
      _harness.provider = OpenAiCompatibleProvider(
        baseUrl: _config.llmBaseUrl,
        apiKey: _config.llmApiKey,
        model: _config.llmModel,
      );
    } else {
      _harness.provider = null;
    }
  }

  /// 保存全局配置
  Future<void> updateConfig(AppConfig newConfig) async {
    _config = newConfig;
    await _configService.saveConfig(newConfig);
    _setupHarnessAndTools();
    notifyListeners();

    if (_config.novelAiKey.isNotEmpty) {
      await refreshAccountInfo();
    }
  }

  /// 更新侧边栏参数
  void updateParams(NaiGenerationParams newParams) {
    _params = newParams;
    notifyListeners();
  }

  /// 快速切换官方分辨率预设 (分类 + 方向)
  void selectResolution(ResolutionCategory category, ResolutionOrientation orientation) {
    if (category == ResolutionCategory.custom) {
      if (orientation == ResolutionOrientation.landscape && _params.width < _params.height) {
        final tmp = _params.width;
        _params = _params.copyWith(width: _params.height, height: tmp);
      } else if (orientation == ResolutionOrientation.portrait && _params.width > _params.height) {
        final tmp = _params.width;
        _params = _params.copyWith(width: _params.height, height: tmp);
      }
    } else {
      final (w, h) = ResolutionPresetHelper.getDimensions(category, orientation);
      _params = _params.copyWith(width: w, height: h);
    }
    notifyListeners();
  }

  /// 快速交换宽高
  void swapResolution() {
    _params = _params.copyWith(
      width: _params.height,
      height: _params.width,
    );
    notifyListeners();
  }

  /// 快速切换分辨率预设 (兼容老调用)
  void selectResolutionPreset(ResolutionPreset preset) {
    _params = _params.copyWith(
      width: preset.width,
      height: preset.height,
    );
    notifyListeners();
  }

  /// 选择画板当前查看的图片
  void selectImage(NaiGeneratedImage image) {
    _selectedImage = image;
    notifyListeners();
  }

  /// 切换 Agent 当前技能
  void selectSkill(Skill skill) {
    _harness.setSkill(skill);
    _harness.addInfoMessage('已切换为技能: 【${skill.name}】\n${skill.description}');
    notifyListeners();
  }

  /// 手动快速生图 (使用左侧面板参数)
  Future<void> generateImage() async {
    if (_params.prompt.trim().isEmpty) {
      _errorMessage = '提示词不能为空，请先在左侧或对话框中输入描述。';
      notifyListeners();
      return;
    }

    if (_config.novelAiKey.trim().isEmpty) {
      _errorMessage = '未配置 NovelAI API Key，请点击右上角设置。';
      notifyListeners();
      return;
    }

    _isGenerating = true;
    _errorMessage = null;
    _statusMessage = '正在请求 NovelAI 生图 (${_params.width}x${_params.height}, ${_params.steps}步)...';
    notifyListeners();

    try {
      final results = await _repository.generate(
        apiKey: _config.novelAiKey,
        params: _params,
        saveDir: _config.saveDirectory,
      );

      if (results.isNotEmpty) {
        _selectedImage = results.first;
        _statusMessage = '生图完成，已保存在 ${_selectedImage?.localFilePath ?? '本地'}';
      }
    } catch (e) {
      _errorMessage = '生图失败: $e';
      _statusMessage = null;
    } finally {
      _isGenerating = false;
      notifyListeners();
      // 生图后异步刷新体力与点数
      refreshAccountInfo();
    }
  }

  /// 超分放大当前图片 (2x / 4x)
  Future<void> upscaleSelected({int scale = 4}) async {
    if (_selectedImage == null) {
      _errorMessage = '当前画板中无图片可供放大。';
      notifyListeners();
      return;
    }

    if (_config.novelAiKey.trim().isEmpty) {
      _errorMessage = '未配置 NovelAI API Key。';
      notifyListeners();
      return;
    }

    _isGenerating = true;
    _errorMessage = null;
    _statusMessage = '正在执行 ${scale}x 图像超分放大...';
    notifyListeners();

    try {
      final upscaled = await _repository.upscale(
        apiKey: _config.novelAiKey,
        sourceImage: _selectedImage!,
        scale: scale,
        saveDir: _config.saveDirectory,
      );
      _selectedImage = upscaled;
      _statusMessage = '放大完成 (${scale}x)';
    } catch (e) {
      _errorMessage = '放大失败: $e';
      _statusMessage = null;
    } finally {
      _isGenerating = false;
      notifyListeners();
      refreshAccountInfo();
    }
  }

  /// 刷新账号与体力信息
  Future<void> refreshAccountInfo() async {
    if (_config.novelAiKey.trim().isEmpty) return;

    _isLoadingAccount = true;
    notifyListeners();

    try {
      _accountInfo = await _repository.fetchAccountInfo(apiKey: _config.novelAiKey);
    } catch (_) {
      // ignore
    } finally {
      _isLoadingAccount = false;
      notifyListeners();
    }
  }

  /// 发送对话消息 (支持 Slash 命令行如 /nai, /tag, /upscale, /account, /clear, /help)
  Future<void> sendChatMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // 1. 处理 Slash 指令
    if (trimmed.startsWith('/')) {
      await _handleSlashCommand(trimmed);
      return;
    }

    // 2. 正常 Agent 对话循环
    _isChatStreaming = true;
    _currentStreamingThoughts = '';
    _currentStreamingContent = '';
    _errorMessage = null;
    notifyListeners();

    try {
      final stream = _harness.send(trimmed, temperature: _config.llmTemperature);

      await for (final event in stream) {
        if (event is ThoughtDeltaEvent) {
          _currentStreamingThoughts += event.delta;
          notifyListeners();
        } else if (event is ContentDeltaEvent) {
          _currentStreamingContent += event.delta;
          notifyListeners();
        } else if (event is ToolResultEvent) {
          notifyListeners();
        } else if (event is ErrorEvent) {
          _errorMessage = event.error;
          notifyListeners();
        }
      }
    } catch (e) {
      _errorMessage = '对话异常: $e';
    } finally {
      _isChatStreaming = false;
      _currentStreamingThoughts = '';
      _currentStreamingContent = '';
      notifyListeners();
    }
  }

  Future<void> _handleSlashCommand(String command) async {
    final parts = command.split(' ');
    final cmd = parts[0].toLowerCase();
    final args = parts.skip(1).join(' ').trim();

    switch (cmd) {
      case '/help':
        _harness.addInfoMessage('''快捷指令说明：
• /nai <提示词> [--landscape|--portrait|--square|--wallpaper] : 快速生成插画
• /upscale [2|4] : 超分放大当前图片
• /tag <关键词> : 查询 Danbooru 官方标签联想
• /account : 查询账号订阅等级与 V5 专属体力池
• /clear : 清空对话历史''');
        notifyListeners();
        break;

      case '/clear':
        _harness.clearMessages();
        notifyListeners();
        break;

      case '/account':
        await refreshAccountInfo();
        if (_accountInfo != null) {
          final info = _accountInfo!;
          _harness.addInfoMessage('''NovelAI 账号状态：
• 订阅等级: ${info.tierName}
• V5 专属体力池: ${info.staminaPercent.toStringAsFixed(1)}%
• 可用 Anlas: ${info.totalAnlas} (赠送: ${info.fixedAnlas}, 购买: ${info.purchasedAnlas})''');
        } else {
          _harness.addInfoMessage('查询账号信息失败，请检查 API Key 设置。');
        }
        notifyListeners();
        break;

      case '/tag':
        if (args.isEmpty) {
          _harness.addInfoMessage('用法: /tag <关键词> (例如: /tag silver)');
          notifyListeners();
          return;
        }
        final tags = await _repository.suggestTags(
          apiKey: _config.novelAiKey,
          query: args,
        );
        if (tags.isEmpty) {
          _harness.addInfoMessage('未找到与 "$args" 相关的标签。');
        } else {
          final listStr = tags
              .take(8)
              .map((t) => '• ${t.tag} (${t.count})')
              .join('\n');
          _harness.addInfoMessage('标签联想建议 ("$args"):\n$listStr');
        }
        notifyListeners();
        break;

      case '/upscale':
        final scale = int.tryParse(args) ?? 4;
        await upscaleSelected(scale: scale);
        _harness.addInfoMessage('已执行 ${scale}x 放大');
        notifyListeners();
        break;

      case '/nai':
        if (args.isEmpty) {
          _harness.addInfoMessage('用法: /nai <提示词>');
          notifyListeners();
          return;
        }

        String prompt = args;
        int w = _params.width;
        int h = _params.height;

        if (prompt.contains('--landscape')) {
          prompt = prompt.replaceAll('--landscape', '').trim();
          w = 1216;
          h = 832;
        } else if (prompt.contains('--portrait')) {
          prompt = prompt.replaceAll('--portrait', '').trim();
          w = 832;
          h = 1216;
        } else if (prompt.contains('--square')) {
          prompt = prompt.replaceAll('--square', '').trim();
          w = 1024;
          h = 1024;
        } else if (prompt.contains('--wallpaper')) {
          prompt = prompt.replaceAll('--wallpaper', '').trim();
          w = 1920;
          h = 1088;
        }

        _params = _params.copyWith(prompt: prompt, width: w, height: h);
        await generateImage();
        if (_selectedImage != null) {
          _harness.addInfoMessage('插画已生成: ${_selectedImage!.localFilePath ?? '完成'}\n尺寸: ${w}x$h, 种子: ${_selectedImage!.seed}');
        }
        notifyListeners();
        break;

      default:
        _harness.addInfoMessage('未知指令 "$cmd"，输入 /help 查看可用指令。');
        notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearStatus() {
    _statusMessage = null;
    notifyListeners();
  }
}
