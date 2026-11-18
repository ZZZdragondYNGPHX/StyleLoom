import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:styleloom_app/bridge/core_client.dart';
import 'package:styleloom_app/main.dart';
import 'package:styleloom_app/models/core_models.dart';
import 'package:styleloom_app/state/app_controller.dart';
import 'package:styleloom_app/ui/recipe/dynamic_schema_form.dart';
import 'package:styleloom_app/ui/recipe/recipe_detail_panel.dart';
import 'package:styleloom_app/ui/widgets/prompt_capsule_editor.dart';

class DelayedClient extends StyleLoomClient {
  DelayedClient() : super(vaultDir: 'unused');
  final queries = <Completer<List<StyleRecipe>>>[];
  final renders = <Completer<String>>[];
  Completer<StyleRecipe>? pendingSave;

  @override
  Future<List<StyleRecipe>> listRecipes({
    String? query,
    String? platform,
    String? schemaId,
    String? tag,
    bool favoriteOnly = false,
  }) {
    final result = Completer<List<StyleRecipe>>();
    queries.add(result);
    return result.future;
  }

  @override
  Future<String> nodesToRaw(List<PromptNode> nodes, PromptSyntax syntax) {
    final result = Completer<String>();
    renders.add(result);
    return result.future;
  }

  @override
  Future<StyleRecipe> saveRecipe(StyleRecipe recipe) async =>
      pendingSave == null ? recipe : pendingSave!.future;
}

void main() {
  test('late filter results cannot replace the current results', () async {
    final client = DelayedClient();
    final controller = AppController(client: client);
    final old = controller.updateFilters(query: 'old');
    final current = controller.updateFilters(query: 'current');
    client.queries[1].complete([
      StyleRecipe(id: 'current', title: 'current', schemaId: 'nai_v5'),
    ]);
    await current;
    client.queries[0].complete([
      StyleRecipe(id: 'old', title: 'old', schemaId: 'nai_v5'),
    ]);
    await old;
    expect(controller.recipes.single.id, 'current');
    controller.dispose();
  });

  test('saving after closing the editor cannot reopen it', () async {
    final client = DelayedClient()..pendingSave = Completer<StyleRecipe>();
    final controller = AppController(client: client);
    final recipe = StyleRecipe(id: 'saved', title: 'saved', schemaId: 'nai_v5');
    controller.selectRecipe(recipe);
    final saving = controller.saveRecipe(recipe);
    controller.closeRecipeDrawer();
    client.pendingSave!.complete(recipe);
    await Future<void>.delayed(Duration.zero);
    client.queries.single.complete([recipe]);
    await saving;
    expect(controller.selectedRecipe, isNull);
    controller.dispose();
  });

  testWidgets(
    'mobile new recipe opens an editor and system back clears the draft',
    (tester) async {
      final controller = AppController(client: DelayedClient())
        ..initialized = true;
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(StyleLoomApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();
      expect(find.text('新建画师串预设'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.selectedRecipe, isNull);
      expect(find.byType(RecipeDetailPanel), findsNothing);
    },
  );

  testWidgets(
    'repeated weight changes and late serialization preserve the latest edit',
    (tester) async {
      final client = DelayedClient();
      var nodes = <PromptNode>[const TokenNode(id: 't', text: 'cat')];
      var raw = 'cat';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PromptCapsuleEditor(
                label: 'prompt',
                client: client,
                nodes: nodes,
                rawText: raw,
                modelSyntax: PromptSyntax.sdParens,
                availableSnippets: const [],
                onChanged: (next, text) => setState(() {
                  nodes = next;
                  raw = text;
                }),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('权重 +0.05'));
      await tester.tap(find.byTooltip('权重 +0.05'));
      expect(nodes.single.weight, 1.1);
      client.renders[1].complete('(cat:1.1)');
      await tester.pump();
      client.renders[0].complete('(cat:1.05)');
      await tester.pump();
      expect(raw, '(cat:1.1)');
      expect(nodes.single.weight, 1.1);
      await tester.tap(find.text('源码'));
      client.renders[2].complete('(cat:1.1)');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new text');
      expect(raw, 'new text');
      expect(nodes, isEmpty);
    },
  );

  testWidgets(
    'resolution and LoRA editing keep focus and composing text across rebuilds',
    (tester) async {
      final schema = PlatformSchema(
        id: 'custom',
        platform: 'Custom',
        modelName: 'Custom',
        defaultSyntax: PromptSyntax.sdParens,
        fields: [
          ParamFieldDef(
            key: 'resolution',
            label: 'size',
            fieldType: ParamFieldType.resolution,
            defaultValue: '832x1216',
          ),
          ParamFieldDef(
            key: 'loras',
            label: 'LoRA',
            fieldType: ParamFieldType.loraList,
            defaultValue: const [],
          ),
        ],
      );
      var values = <String, dynamic>{
        'resolution': '832x1216',
        'loras': [
          {'name': '', 'weight': 1.0},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => DynamicSchemaForm(
                schema: schema,
                values: values,
                onChanged: (next) => setState(() => values = next),
              ),
            ),
          ),
        ),
      );
      final resolution = find.byType(TextField).first;
      await tester.tap(resolution);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '1024x',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect((tester.widget<TextField>(resolution).controller!).text, '1024x');
      final lora = find.byType(TextField).last;
      await tester.tap(lora);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '测试',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(lora).controller!.value.composing,
        const TextRange(start: 0, end: 2),
      );
      expect(tester.testTextInput.isVisible, isTrue);
    },
  );
}
