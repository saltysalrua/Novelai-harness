import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/watermark_pad_picker.dart';

void main() {
  group('Advanced Settings Metadata and Watermark UI Tests', () {
    late StudioViewModel viewModel;

    setUp(() {
      viewModel = StudioViewModel(
        configService: ConfigService(),
        repository: NovelAiRepository(),
      );
    });

    testWidgets(
      'Advanced Settings expands and toggles metadata/watermark switches',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 2400,
                child: ParametersPage(viewModel: viewModel),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 展开 Advanced Settings
        final advFinder = find.text('Advanced Settings');
        await tester.tap(advFinder);
        await tester.pumpAndSettle();

        expect(find.text('删除元数据'), findsOneWidget);
        expect(find.text('添加水印'), findsOneWidget);

        // 初始状态下“保持原图像”不出现
        expect(find.text('保持原图像'), findsNothing);
        expect(find.byType(WatermarkPadPicker), findsNothing);

        // 1. 开启“删除元数据”
        final stripSwitch = find.ancestor(
          of: find.text('删除元数据'),
          matching: find.byType(Row),
        );
        await tester.tap(
          find.descendant(of: stripSwitch, matching: find.byType(Switch)),
        );
        await tester.pumpAndSettle();

        expect(viewModel.stripMetadata, isTrue);
        // 开启后，“保持原图像”开关出现
        expect(find.text('保持原图像'), findsOneWidget);

        // 2. 开启“添加水印”
        final wmSwitch = find.ancestor(
          of: find.text('添加水印'),
          matching: find.byType(Row),
        );
        await tester.tap(
          find.descendant(of: wmSwitch, matching: find.byType(Switch)),
        );
        await tester.pumpAndSettle();

        expect(viewModel.enableWatermark, isTrue);
        // 水印 2D 调节面板展开
        expect(find.byType(WatermarkPadPicker), findsOneWidget);

        // 3. 点击水印位置胶囊激活画板 2D 交互定位
        expect(find.textContaining('位置:'), findsOneWidget);
        await tester.tap(find.textContaining('位置:'));
        await tester.pumpAndSettle();
        expect(viewModel.isEditingWatermarkPosition, isTrue);

        // 4. 开启“保持原图像”
        final keepSwitch = find.ancestor(
          of: find.text('保持原图像'),
          matching: find.byType(Row),
        );
        final keepSwitchToggle = find.descendant(
          of: keepSwitch,
          matching: find.byType(Switch),
        );
        await tester.tap(keepSwitchToggle);
        await tester.pumpAndSettle();
        expect(viewModel.keepOriginalImage, isTrue);
      },
    );

    testWidgets(
      'Watermark panel toggles smart position, auto contrast and blind watermark',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 2400,
                child: ParametersPage(viewModel: viewModel),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 展开面板并开启水印，面板展开
        await tester.tap(find.text('Advanced Settings'));
        await tester.pumpAndSettle();

        Future<void> toggle(String label) async {
          final row = find.ancestor(
            of: find.text(label),
            matching: find.byType(Row),
          );
          final sw = find.descendant(of: row, matching: find.byType(Switch));
          await tester.tap(sw.first);
          await tester.pumpAndSettle();
        }

        await toggle('添加水印');
        await toggle('自动选位');
        await toggle('自动对比度');
        expect(viewModel.watermarkConfig.autoPosition, isTrue);
        expect(viewModel.watermarkConfig.autoContrast, isTrue);

        // 开启盲水印并输入载荷文本
        await toggle('启用');
        await tester.enterText(find.byType(TextFormField), 'copyright 2026');
        await tester.pumpAndSettle();
        expect(viewModel.watermarkConfig.blindEnabled, isTrue);
        expect(viewModel.watermarkConfig.blindText, 'copyright 2026');
      },
    );
  });
}
