import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/copy_helpers.dart';

class SchemasPage extends StatefulWidget {
  const SchemasPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SchemasPage> createState() => _SchemasPageState();
}

class _SchemasPageState extends State<SchemasPage> {
  Future<void> _openSchemaEditor({
    PlatformSchema? base,
    bool cloneAsNew = false,
  }) async {
    final platCtrl = TextEditingController(text: base?.platform ?? 'Custom');
    final modelCtrl = TextEditingController(
      text: cloneAsNew ? '${base?.modelName ?? ""} (自定义)' : (base?.modelName ?? ''),
    );
    var syntax = base?.defaultSyntax ?? PromptSyntax.sdParens;
    final fields = List<ParamFieldDef>.of(
      base?.fields ??
          [
            ParamFieldDef(
              key: 'steps',
              label: '步数 (Steps)',
              fieldType: ParamFieldType.stepper,
              defaultValue: 28,
              min: 1,
              max: 60,
              step: 1,
            ),
            ParamFieldDef(
              key: 'cfg',
              label: 'CFG Scale',
              fieldType: ParamFieldType.slider,
              defaultValue: 5.0,
              min: 1.0,
              max: 15.0,
              step: 0.5,
            ),
          ],
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            base == null
                ? '新建自定义模型模板'
                : (cloneAsNew ? '克隆并自定义模型模板' : '编辑模型模板'),
          ),
          content: SizedBox(
            width: 580,
            height: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: platCtrl,
                        decoration: const InputDecoration(labelText: '生图平台'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: modelCtrl,
                        decoration: const InputDecoration(labelText: '底模名称'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PromptSyntax>(
                  initialValue: syntax,
                  decoration: const InputDecoration(labelText: '默认权重语法方言'),
                  items: PromptSyntax.values
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlg(() => syntax = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text('可交互参数控件列表',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final added = await _addParamDialog(ctx);
                        if (added != null) {
                          setDlg(() => fields.add(added));
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('新增参数项'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.separated(
                    itemCount: fields.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, idx) {
                      final f = fields[idx];
                      return ListTile(
                        dense: true,
                        tileColor: StyleLoomTheme.surfaceHigh,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        title: Text('${f.label} (${f.key})'),
                        subtitle: Text(
                            '类型: ${f.fieldType.wire} · 默认: ${f.defaultValue}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          onPressed: () => setDlg(() => fields.removeAt(idx)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final id = (base == null || cloneAsNew) ? '' : base.id;
                await widget.controller.saveSchema(
                  PlatformSchema(
                    id: id,
                    platform: platCtrl.text.trim().isEmpty
                        ? 'Custom'
                        : platCtrl.text.trim(),
                    modelName: modelCtrl.text.trim().isEmpty
                        ? 'Custom Model'
                        : modelCtrl.text.trim(),
                    defaultSyntax: syntax,
                    fields: fields,
                    isBuiltin: (base != null && !cloneAsNew)
                        ? base.isBuiltin
                        : false,
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('保存模板'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存平台/模型模板')));
    }
  }

  Future<ParamFieldDef?> _addParamDialog(BuildContext context) async {
    final keyCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final defCtrl = TextEditingController(text: '1.0');
    final optsCtrl = TextEditingController();
    var ftype = ParamFieldType.slider;

    return showDialog<ParamFieldDef>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('添加自定义参数控件'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                      labelText: '参数键名 (英文)', hintText: '例如 flow_shift'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                      labelText: '显示名称', hintText: '例如 Flow Shift'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ParamFieldType>(
                  initialValue: ftype,
                  decoration: const InputDecoration(labelText: '控件类型'),
                  items: ParamFieldType.values
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t.wire)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlg(() => ftype = v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: defCtrl,
                  decoration: const InputDecoration(labelText: '默认值'),
                ),
                if (ftype == ParamFieldType.select) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: optsCtrl,
                    decoration: const InputDecoration(
                        labelText: '可选项（逗号分隔）', hintText: 'euler, dpmpp_2m'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final k = keyCtrl.text.trim();
                final l = labelCtrl.text.trim();
                if (k.isEmpty || l.isEmpty) return;
                dynamic defVal = defCtrl.text.trim();
                if (ftype == ParamFieldType.slider) {
                  defVal = double.tryParse(defVal.toString()) ?? 1.0;
                } else if (ftype == ParamFieldType.stepper) {
                  defVal = int.tryParse(defVal.toString()) ?? 20;
                } else if (ftype == ParamFieldType.toggle) {
                  defVal = defVal.toString().toLowerCase() == 'true';
                } else if (ftype == ParamFieldType.loraList) {
                  defVal = <dynamic>[];
                }
                final opts = optsCtrl.text
                    .split(RegExp(r'[,，]'))
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                Navigator.pop(
                  ctx,
                  ParamFieldDef(
                    key: k,
                    label: l,
                    fieldType: ftype,
                    defaultValue: defVal,
                    min: (ftype == ParamFieldType.slider ||
                            ftype == ParamFieldType.stepper)
                        ? 0
                        : null,
                    max: ftype == ParamFieldType.stepper
                        ? 100
                        : (ftype == ParamFieldType.slider ? 20 : null),
                    step: ftype == ParamFieldType.slider ? 0.1 : 1,
                    options: opts,
                  ),
                );
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schemas = widget.controller.schemas;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: StyleLoomTheme.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('平台与模型参数模板（Schema 引擎）',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(
                      '已内置 NovelAI V5/V4.5/V3、ComfyUI Anima/MOSS/Illustrious/NoobAI/Lumina/Chroma 与 WebUI，支持克隆或自由新增新模型。',
                      style: TextStyle(
                          fontSize: 12, color: StyleLoomTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _openSchemaEditor(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新建模型模板'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: schemas.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, idx) {
              final s = schemas[idx];
              return Card(
                child: ListTile(
                  title: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${s.platform} · ${s.modelName}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Chip(
                        label: Text(s.isBuiltin ? '官方内置' : '自定义',
                            style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '默认语法: ${s.defaultSyntax.label} · 参数控件(${s.fields.length}): ${s.fields.map((f) => f.label).join(" / ")}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: StyleLoomTheme.textSecondary),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '克隆修改为新模板',
                        icon: const Icon(Icons.copy_all_rounded, size: 18),
                        onPressed: () =>
                            _openSchemaEditor(base: s, cloneAsNew: true),
                      ),
                      if (!s.isBuiltin) ...[
                        IconButton(
                          tooltip: '编辑',
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          onPressed: () => _openSchemaEditor(base: s),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          onPressed: () => runActionWithFeedback(context, () => widget.controller.deleteSchema(s.id)),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
