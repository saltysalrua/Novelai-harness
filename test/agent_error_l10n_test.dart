import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'English Studio localizes missing-provider error without an account',
    () async {
      SharedPreferences.setMockInitialValues({
        'novelai_locale_preference': 'en',
        'novelai_enable_tag_dictionary_auto_update': false,
        'novelai_enable_image_persistence': false,
        'llm_api_key': '',
      });
      final sessionDirectory = Directory.systemTemp.createTempSync(
        'agent_error_l10n_',
      );
      final viewModel = StudioViewModel(
        sessionLogBaseDir: sessionDirectory.path,
      );
      addTearDown(() async {
        await viewModel.flushPendingSaves();
        viewModel.dispose();
        if (sessionDirectory.existsSync()) {
          sessionDirectory.deleteSync(recursive: true);
        }
      });
      await viewModel.init();

      await viewModel.sendChatMessage('Hello');

      expect(
        viewModel.errorMessage,
        'No LLM provider is configured. Add a provider and API key in Settings.',
      );
    },
  );

  test(
    'typed app errors localize while external provider details stay verbatim',
    () {
      final l10n = lookupAppLocalizations(const Locale('en'));

      expect(
        localizeHarnessError(
          l10n,
          const ErrorEvent(
            '上下文超过安全窗口',
            code: HarnessErrorCode.contextWindowInsufficient,
          ),
        ),
        contains("context is still over the model's safe window"),
      );
      expect(
        localizeHarnessError(
          l10n,
          const ErrorEvent('模型请求失败', code: HarnessErrorCode.modelRequestFailed),
        ),
        'The model request failed. Check the provider and model settings, then try again.',
      );

      const providerDetail =
          'LLM API response error (HTTP 400): protocol_error: invalid role';
      expect(
        localizeHarnessError(l10n, const ErrorEvent(providerDetail)),
        providerDetail,
      );
    },
  );
}
