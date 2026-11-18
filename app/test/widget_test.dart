import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:styleloom_app/bridge/core_client.dart';
import 'package:styleloom_app/main.dart';
import 'package:styleloom_app/models/core_models.dart';
import 'package:styleloom_app/state/app_controller.dart';
import 'package:styleloom_app/theme/app_theme.dart';

void main() {
  testWidgets(
    'StyleLoom Editorial Scheme A: pill dock, night mode, spread modal & popover ungroup',
    (WidgetTester tester) async {
      final tmpVault = Directory.systemTemp.createTempSync(
        'styleloom_flutter_test_${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() {
        if (tmpVault.existsSync()) {
          tmpVault.deleteSync(recursive: true);
        }
      });

      final libPath = File('../rust/target/release/libstyleloom_core.so')
          .absolute
          .path;
      final client = StyleLoomClient(
        vaultDir: tmpVault.path,
        libraryPath: libPath,
      );
      final controller = AppController(client: client);

      await tester.runAsync(() async {
        await controller.initialize();
        expect(controller.schemas.length, 11);

        final snA = await controller.saveSnippet(
          PromptSnippet(
            id: 'sn_a',
            name: '预设A',
            categories: const ['人物'],
            rawText: '1girl, beautiful',
          ),
        );
        final snB = await controller.saveSnippet(
          PromptSnippet(
            id: 'sn_b',
            name: '预设B',
            categories: const ['身材'],
            rawText: 'huge breasts',
          ),
        );

        final recipe = await controller.saveRecipe(
          StyleRecipe(
            id: '',
            title: '测试画师串卡片',
            schemaId: 'nai_v5',
            positiveNodes: [
              const TokenNode(id: 't1', text: 'huge'),
              SnippetRefNode(
                id: 'r1',
                snippetId: snA.id,
                fallbackName: snA.name,
                fallbackRaw: snA.rawText,
              ),
              SnippetRefNode(
                id: 'r2',
                snippetId: snB.id,
                fallbackName: snB.name,
                fallbackRaw: snB.rawText,
              ),
            ],
            negativeRaw: 'lowres',
          ),
        );

        final copied = await client.renderRecipePrompt(
          recipeId: recipe.id,
          side: 'positive',
        );
        expect(copied, 'huge, 1girl, beautiful, huge breasts');

        final converted = await client.renderRecipePrompt(
          recipeId: recipe.id,
          side: 'positive',
          targetSyntax: TargetSyntax.mossSpace,
        );
        expect(converted, 'huge, 1girl, beautiful, huge breasts');

        controller.closeRecipeDrawer();
      });

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(StyleLoomApp(controller: controller));
      await tester.pumpAndSettle();

      // Verify desktop floating pill dock & day editorial theme
      expect(find.text('StyleLoom'), findsOneWidget);
      expect(find.text('画册'), findsOneWidget);
      expect(find.text('积木'), findsOneWidget);
      expect(find.text('透镜'), findsOneWidget);
      expect(find.text('底模'), findsOneWidget);
      expect(find.text('云匣'), findsOneWidget);
      expect(find.text('测试画师串卡片'), findsOneWidget);
      expect(controller.isNightMode, isFalse);

      // Toggle day/night editorial palette
      await tester.tap(find.text('夜读'));
      await tester.pumpAndSettle();
      expect(controller.isNightMode, isTrue);
      expect(find.text('宣纸'), findsOneWidget);
      await tester.tap(find.text('宣纸'));
      await tester.pumpAndSettle();
      expect(controller.isNightMode, isFalse);

      // Tap the recipe card to open the centered 2-page spread lightbox modal
      await tester.tap(find.text('测试画师串卡片'));
      await tester.pumpAndSettle();

      expect(find.text('画师串预设详情'), findsOneWidget);
      expect(find.text('咒语编织'), findsOneWidget);
      expect(find.text('🧩 预设A'), findsOneWidget);
      expect(find.text('🧩 预设B'), findsOneWidget);

      // Zero-noise capsule: '打散' is hidden until clicking the snippet capsule
      expect(find.text('打散'), findsNothing);
      await tester.tap(find.text('🧩 预设A'));
      await tester.pumpAndSettle();
      expect(find.text('打散'), findsOneWidget);

      // Click '打散' in the floating popover to expand snippet in place
      await tester.runAsync(() async {
        await tester.tap(find.text('打散'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();

      expect(find.text('🧩 预设A'), findsNothing);
      expect(find.text('1girl'), findsOneWidget);
      expect(find.text('beautiful'), findsOneWidget);
      expect(find.text('🧩 预设B'), findsOneWidget);

      // Verify EditorialColors fallback works safely
      expect(EditorialColors.day.bg, const Color(0xFFF6F3EC));
    },
  );

  testWidgets(
    'Mobile layout renders floating nav pill and switches all 5 tabs without overflow',
    (WidgetTester tester) async {
      final tmpVault = Directory.systemTemp.createTempSync(
        'styleloom_mobile_test_${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() {
        if (tmpVault.existsSync()) {
          tmpVault.deleteSync(recursive: true);
        }
      });

      final libPath = File('../rust/target/release/libstyleloom_core.so')
          .absolute
          .path;
      final client = StyleLoomClient(
        vaultDir: tmpVault.path,
        libraryPath: libPath,
      );
      final controller = AppController(client: client);
      await tester.runAsync(() => controller.initialize());

      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(StyleLoomApp(controller: controller));
      await tester.pumpAndSettle();

      for (final tab in ['积木', '透镜', '底模', '云匣', '画册']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }

      // Narrow mobile phone (360x780): open saved card detail and switch all 3 editorial tabs
      tester.view.physicalSize = const Size(360, 780);
      await tester.runAsync(() async {
        await controller.saveRecipe(
          StyleRecipe(
            id: '',
            title: '窄屏测试卡片',
            schemaId: 'nai_v5',
            positiveRaw: '1girl, warm sunlight',
          ),
        );
      });
      await tester.pumpAndSettle();
      controller.closeRecipeDrawer();
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.setColumns(mobile: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('窄屏测试卡片'));
      await tester.pumpAndSettle();
      expect(find.text('画师串预设详情'), findsOneWidget);
      for (final tab in ['底模参数', '溯源手记', '咒语编织']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }
    },
  );
}
