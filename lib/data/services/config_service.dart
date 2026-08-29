import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/novelai_models.dart';

/// 全局配置数据模型
class AppConfig {
  // NovelAI 设置
  final String novelAiKey;
  final NaiModel defaultModel;
  final NaiSampler defaultSampler;
  final NoiseSchedule defaultNoiseSchedule;
  final ResolutionPreset defaultResolution;
  final int customWidth;
  final int customHeight;
  final int defaultSteps;
  final double defaultScale;
  final double defaultCfgRescale;
  final bool opusFreeMode;
  final String prefixPrompt;
  final String suffixPrompt;
  final String negativePrompt;
  final String saveDirectory;

  // LLM 设置
  final String llmBaseUrl;
  final String llmApiKey;
  final String llmModel;
  final double llmTemperature;

  const AppConfig({
    this.novelAiKey = '',
    this.defaultModel = NaiModel.v5Full,
    this.defaultSampler = NaiSampler.kEuler,
    this.defaultNoiseSchedule = NoiseSchedule.karras,
    this.defaultResolution = ResolutionPreset.portrait,
    this.customWidth = 832,
    this.customHeight = 1216,
    this.defaultSteps = 28,
    this.defaultScale = 5.0,
    this.defaultCfgRescale = 0.0,
    this.opusFreeMode = true,
    this.prefixPrompt = '',
    this.suffixPrompt = '',
    this.negativePrompt =
        'blurry, lowres, error, worst quality, bad quality, jpeg artifacts, ugly, duplicate, mutilated, out of frame, extra fingers, mutated hands, poorly drawn hands, poorly drawn face, mutation, deformed, bad anatomy, bad proportions, extra limbs, cloned face, disfigured, gross proportions, malformed limbs, missing arms, missing legs, extra arms, extra legs, fused fingers, too many fingers, long neck, username, watermark, signature',
    this.saveDirectory = '',
    this.llmBaseUrl = 'https://api.deepseek.com/v1',
    this.llmApiKey = '',
    this.llmModel = 'deepseek-chat',
    this.llmTemperature = 0.7,
  });

  AppConfig copyWith({
    String? novelAiKey,
    NaiModel? defaultModel,
    NaiSampler? defaultSampler,
    NoiseSchedule? defaultNoiseSchedule,
    ResolutionPreset? defaultResolution,
    int? customWidth,
    int? customHeight,
    int? defaultSteps,
    double? defaultScale,
    double? defaultCfgRescale,
    bool? opusFreeMode,
    String? prefixPrompt,
    String? suffixPrompt,
    String? negativePrompt,
    String? saveDirectory,
    String? llmBaseUrl,
    String? llmApiKey,
    String? llmModel,
    double? llmTemperature,
  }) {
    return AppConfig(
      novelAiKey: novelAiKey ?? this.novelAiKey,
      defaultModel: defaultModel ?? this.defaultModel,
      defaultSampler: defaultSampler ?? this.defaultSampler,
      defaultNoiseSchedule: defaultNoiseSchedule ?? this.defaultNoiseSchedule,
      defaultResolution: defaultResolution ?? this.defaultResolution,
      customWidth: customWidth ?? this.customWidth,
      customHeight: customHeight ?? this.customHeight,
      defaultSteps: defaultSteps ?? this.defaultSteps,
      defaultScale: defaultScale ?? this.defaultScale,
      defaultCfgRescale: defaultCfgRescale ?? this.defaultCfgRescale,
      opusFreeMode: opusFreeMode ?? this.opusFreeMode,
      prefixPrompt: prefixPrompt ?? this.prefixPrompt,
      suffixPrompt: suffixPrompt ?? this.suffixPrompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      saveDirectory: saveDirectory ?? this.saveDirectory,
      llmBaseUrl: llmBaseUrl ?? this.llmBaseUrl,
      llmApiKey: llmApiKey ?? this.llmApiKey,
      llmModel: llmModel ?? this.llmModel,
      llmTemperature: llmTemperature ?? this.llmTemperature,
    );
  }
}

/// 配置持久化与自适应加载服务
class ConfigService {
  static const String _keyNovelAiKey = 'novelai_key';
  static const String _keyModel = 'novelai_model';
  static const String _keySampler = 'novelai_sampler';
  static const String _keyNoiseSchedule = 'novelai_noise_schedule';
  static const String _keyResolution = 'novelai_resolution';
  static const String _keyCustomWidth = 'novelai_custom_width';
  static const String _keyCustomHeight = 'novelai_custom_height';
  static const String _keySteps = 'novelai_steps';
  static const String _keyScale = 'novelai_scale';
  static const String _keyCfgRescale = 'novelai_cfg_rescale';
  static const String _keyOpusFreeMode = 'novelai_opus_free_mode';
  static const String _keyPrefix = 'novelai_prefix';
  static const String _keySuffix = 'novelai_suffix';
  static const String _keyNegative = 'novelai_negative';
  static const String _keySaveDir = 'novelai_save_dir';

  static const String _keyLlmBaseUrl = 'llm_base_url';
  static const String _keyLlmApiKey = 'llm_api_key';
  static const String _keyLlmModel = 'llm_model';
  static const String _keyLlmTemperature = 'llm_temperature';

  /// 加载配置 (优先 SharedPreferences，首次启动尝试自动读取 ~/.pi/agent/novelai.json 与环境变量)
  Future<AppConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    String naiKey = prefs.getString(_keyNovelAiKey) ?? '';
    String prefix = prefs.getString(_keyPrefix) ?? '';
    String suffix = prefs.getString(_keySuffix) ?? '';
    String negative = prefs.getString(_keyNegative) ?? '';
    String modelId = prefs.getString(_keyModel) ?? '';
    String samplerId = prefs.getString(_keySampler) ?? '';
    String scheduleId = prefs.getString(_keyNoiseSchedule) ?? '';
    String resKey = prefs.getString(_keyResolution) ?? '';
    int? customW = prefs.getInt(_keyCustomWidth);
    int? customH = prefs.getInt(_keyCustomHeight);
    int steps = prefs.getInt(_keySteps) ?? 28;
    double scale = prefs.getDouble(_keyScale) ?? 5.0;
    double rescale = prefs.getDouble(_keyCfgRescale) ?? 0.0;
    bool opusFree = prefs.getBool(_keyOpusFreeMode) ?? true;
    String saveDir = prefs.getString(_keySaveDir) ?? '';

    // 首次启动且无配置时，尝试自动读取本地 ~/.pi/agent/novelai.json
    if (naiKey.isEmpty) {
      final piConfig = _tryLoadLocalPiNovelAiJson();
      if (piConfig != null) {
        if (piConfig['apiKey'] is String) naiKey = piConfig['apiKey'];
        if (piConfig['prefixPrompt'] is String) prefix = piConfig['prefixPrompt'];
        if (piConfig['suffixPrompt'] is String) suffix = piConfig['suffixPrompt'];
        if (piConfig['negativePrompt'] is String) negative = piConfig['negativePrompt'];
        if (piConfig['defaultModel'] is String) modelId = piConfig['defaultModel'];
        if (piConfig['defaultSampler'] is String) samplerId = piConfig['defaultSampler'];
        if (piConfig['defaultNoiseSchedule'] is String) {
          scheduleId = piConfig['defaultNoiseSchedule'];
        }
        if (piConfig['defaultScale'] is num) {
          scale = (piConfig['defaultScale'] as num).toDouble();
        }
        if (piConfig['defaultCfgRescale'] is num) {
          rescale = (piConfig['defaultCfgRescale'] as num).toDouble();
        }
        if (piConfig['opusFreeMode'] is bool) {
          opusFree = piConfig['opusFreeMode'];
        }
      }
    }

    // 环境变量后备
    if (naiKey.isEmpty) {
      naiKey = Platform.environment['NOVELAI_API_KEY'] ??
          Platform.environment['NAI_API_KEY'] ??
          '';
    }

    // 确定默认保存目录
    if (saveDir.isEmpty) {
      saveDir = await _getDefaultSaveDirectory();
    }

    // LLM 配置
    String llmBase = prefs.getString(_keyLlmBaseUrl) ?? 'https://api.deepseek.com/v1';
    String llmKey = prefs.getString(_keyLlmApiKey) ??
        Platform.environment['DEEPSEEK_API_KEY'] ??
        Platform.environment['OPENAI_API_KEY'] ??
        '';
    String llmModel = prefs.getString(_keyLlmModel) ?? 'deepseek-chat';
    double llmTemp = prefs.getDouble(_keyLlmTemperature) ?? 0.7;

    return AppConfig(
      novelAiKey: naiKey,
      defaultModel: modelId.isNotEmpty ? NaiModel.fromId(modelId) : NaiModel.v5Full,
      defaultSampler: samplerId.isNotEmpty ? NaiSampler.fromId(samplerId) : NaiSampler.kEuler,
      defaultNoiseSchedule:
          scheduleId.isNotEmpty ? NoiseSchedule.fromId(scheduleId) : NoiseSchedule.karras,
      defaultResolution:
          resKey.isNotEmpty ? ResolutionPreset.fromKey(resKey) : ResolutionPreset.portrait,
      customWidth: customW ?? 832,
      customHeight: customH ?? 1216,
      defaultSteps: steps,
      defaultScale: scale,
      defaultCfgRescale: rescale,
      opusFreeMode: opusFree,
      prefixPrompt: prefix,
      suffixPrompt: suffix,
      negativePrompt: negative.isNotEmpty
          ? negative
          : const AppConfig().negativePrompt,
      saveDirectory: saveDir,
      llmBaseUrl: llmBase,
      llmApiKey: llmKey,
      llmModel: llmModel,
      llmTemperature: llmTemp,
    );
  }

  /// 保存配置
  Future<void> saveConfig(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_keyNovelAiKey, config.novelAiKey);
    await prefs.setString(_keyModel, config.defaultModel.id);
    await prefs.setString(_keySampler, config.defaultSampler.id);
    await prefs.setString(_keyNoiseSchedule, config.defaultNoiseSchedule.id);
    await prefs.setString(_keyResolution, config.defaultResolution.key);
    await prefs.setInt(_keyCustomWidth, config.customWidth);
    await prefs.setInt(_keyCustomHeight, config.customHeight);
    await prefs.setInt(_keySteps, config.defaultSteps);
    await prefs.setDouble(_keyScale, config.defaultScale);
    await prefs.setDouble(_keyCfgRescale, config.defaultCfgRescale);
    await prefs.setBool(_keyOpusFreeMode, config.opusFreeMode);
    await prefs.setString(_keyPrefix, config.prefixPrompt);
    await prefs.setString(_keySuffix, config.suffixPrompt);
    await prefs.setString(_keyNegative, config.negativePrompt);
    await prefs.setString(_keySaveDir, config.saveDirectory);

    await prefs.setString(_keyLlmBaseUrl, config.llmBaseUrl);
    await prefs.setString(_keyLlmApiKey, config.llmApiKey);
    await prefs.setString(_keyLlmModel, config.llmModel);
    await prefs.setDouble(_keyLlmTemperature, config.llmTemperature);
  }

  Map<String, dynamic>? _tryLoadLocalPiNovelAiJson() {
    try {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null) return null;
      final configPath = p.join(home, '.pi', 'agent', 'novelai.json');
      final file = File(configPath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<String> _getDefaultSaveDirectory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outputDir = Directory(p.join(dir.path, 'NovelAI_Output'));
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }
      return outputDir.path;
    } catch (_) {
      return '';
    }
  }
}
