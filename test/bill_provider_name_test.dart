import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/llm_models.dart';
import 'package:novelai_harness/data/services/usage_ledger_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 账单供应商名称显示回归测试:
/// 旧账本/旧会话记录的供应商可能是 id (如 provider_时间戳)，
/// 展示时必须映射为用户设定的供应商名称，且同名行需合并。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioViewModel viewModel;
  late Directory sessionBase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sessionBase = Directory.systemTemp.createTempSync('nai_bill_name_test_');
    viewModel = StudioViewModel(sessionLogBaseDir: sessionBase.path);
    await viewModel.init();
  });

  tearDown(() {
    viewModel.dispose();
    try {
      sessionBase.deleteSync(recursive: true);
    } catch (_) {
      // 目录清理失败不影响断言
    }
  });

  test('内置供应商 id 映射为设定名称且同名行合并', () {
    // 旧记录用 id，新记录直接用名称，两条应合并为一行
    viewModel.usageLedger.record(
      key: 'usage_a',
      provider: 'deepseek',
      model: 'deepseek-chat',
      usage: const TokenUsage(input: 1000, output: 200),
    );
    viewModel.usageLedger.record(
      key: 'usage_b',
      provider: 'DeepSeek',
      model: 'deepseek-chat',
      usage: const TokenUsage(input: 500, output: 100),
    );

    final summary = viewModel.buildBillSummary(BillPeriod.all);
    expect(summary.models.length, equals(1));
    expect(summary.models.first.name, equals('DeepSeek/deepseek-chat'));
    expect(summary.models.first.requests, equals(2));
    expect(summary.models.first.usage.input, equals(1500));
    expect(summary.models.first.usage.output, equals(300));
  });

  test('provider_ 前缀的迁移 id 映射为用户设定的名称', () async {
    const legacyId = 'provider_1730000000000';
    const custom = LlmProviderConfig(
      id: legacyId,
      name: '我的中转站',
      baseUrl: 'https://example.com/v1',
      apiKey: '',
      activeModelId: 'gpt-test',
      models: [LlmModelConfig(id: 'gpt-test', name: 'GPT Test')],
    );
    await viewModel.updateConfig(
      viewModel.config.copyWith(
        llmProviders: const [custom],
        activeLlmProviderId: legacyId,
      ),
    );

    expect(
      viewModel.displayNameForModelKey('$legacyId/gpt-test'),
      equals('我的中转站/gpt-test'),
    );

    viewModel.usageLedger.record(
      key: 'usage_c',
      provider: legacyId,
      model: 'gpt-test',
      usage: const TokenUsage(input: 300),
    );
    final summary = viewModel.buildBillSummary(BillPeriod.all);
    expect(summary.models, isNotEmpty);
    expect(summary.models.first.name, equals('我的中转站/gpt-test'));
  });

  test('未配置的供应商 id 保持原样展示', () {
    expect(
      viewModel.displayNameForModelKey('provider_111111/gpt-x'),
      equals('provider_111111/gpt-x'),
    );
    // 无斜杠分隔的键不处理
    expect(viewModel.displayNameForModelKey('plain'), equals('plain'));
  });
}
