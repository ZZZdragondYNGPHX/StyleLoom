import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/copy_helpers.dart';

class SchemasPage extends StatefulWidget {
  const SchemasPage({
    super.key,
    required this.controller,
    this.isDesktop = true,
  });

  final AppController controller;
  final bool isDesktop;

  @override
  State<SchemasPage> createState() => _SchemasPageState();
}

class _SchemasPageState extends State<SchemasPage> {
  Future<void> _openSchemaEditor({
    PlatformSchema? base,
    bool cloneAsNew = false,
  }) async {
    final c = EditorialColors.of(context);
    final platCtrl = TextEditingController(text: base?.platform ?? 'Custom');
    final modelCtrl = TextEditingController(
      text: cloneAsNew
          ? '${base?.modelName ?? ""} (自定义)'
          : (base?.modelName ?? ''),
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

    var saving = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: c.hairline),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 580),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          base == null
                              ? '新建自定义模型模板'
                              : (cloneAsNew ? '克隆并自定义模型模板' : '编辑模型模板'),
                          style: StyleLoomTheme.serifStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        icon: Icon(Icons.close_rounded, color: c.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s, child: Text(s.label)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlg(() => syntax = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '可交互参数控件列表',
                          style: StyleLoomTheme.serifStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final added = await _addParamDialog(ctx);
                          if (added != null) {
                            setDlg(() => fields.add(added));
                          }
                        },
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('新增参数项'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: fields.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, idx) {
                        final f = fields[idx];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: c.trough,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${f.label} (${f.key})',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: c.ink,
                                      ),
                                    ),
                                    Text(
                                      '类型: ${f.fieldType.wire} · 默认: ${f.defaultValue}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: c.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: c.muted,
                                ),
                                onPressed: () =>
                                    setDlg(() => fields.removeAt(idx)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (saving) return;
                                setDlg(() => saving = true);
                                try {
                                  final id = (base == null || cloneAsNew)
                                      ? ''
                                      : base.id;
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
                                  if (ctx.mounted &&
                                      ModalRoute.of(ctx)?.isCurrent == true) {
                                    Navigator.pop(ctx, true);
                                  }
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  setDlg(() => saving = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('保存失败：$e')),
                                  );
                                }
                              },
                        child: const Text('保存模板'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存平台/模型模板')));
    }
  }

  Future<ParamFieldDef?> _addParamDialog(BuildContext context) async {
    final c = EditorialColors.of(context);
    final keyCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final defCtrl = TextEditingController(text: '1.0');
    final optsCtrl = TextEditingController();
    var ftype = ParamFieldType.slider;

    return showDialog<ParamFieldDef>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: c.surface,
          title: const Text('添加自定义参数控件'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                    labelText: '参数键名 (英文)',
                    hintText: '例如 flow_shift',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: '显示名称',
                    hintText: '例如 Flow Shift',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ParamFieldType>(
                  initialValue: ftype,
                  decoration: const InputDecoration(labelText: '控件类型'),
                  items: ParamFieldType.values
                      .map(
                        (t) => DropdownMenuItem(value: t, child: Text(t.wire)),
                      )
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
                      labelText: '可选项（逗号分隔）',
                      hintText: 'euler, dpmpp_2m',
                    ),
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
                    min:
                        (ftype == ParamFieldType.slider ||
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
    final c = EditorialColors.of(context);
    final schemas = widget.controller.schemas;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1480),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.isDesktop ? 28 : 14),
          child: Column(
            children: [
              // 统一画册页眉
              Container(
                padding: EdgeInsets.only(
                  top: widget.isDesktop ? 10 : 14,
                  bottom: 18,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.hairline)),
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '底模参数图谱 · Schema 模板',
                            style: StyleLoomTheme.serifStyle(
                              fontSize: widget.isDesktop ? 26 : 21,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '开箱内置 NovelAI V5/V4.5/V3、ComfyUI Anima/MOSS/Illustrious/NoobAI/Lumina/Chroma 与 WebUI，支持克隆或自由新增。',
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openSchemaEditor(),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('新建模型模板'),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: LayoutBuilder(
                  builder: (_, box) {
                    final colCount = box.maxWidth >= 1060
                        ? 3
                        : (box.maxWidth >= 660 ? 2 : 1);
                    return GridView.builder(
                      padding: EdgeInsets.only(
                        top: 20,
                        bottom: widget.isDesktop ? 40 : 96,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colCount,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: 222,
                      ),
                      itemCount: schemas.length,
                      itemBuilder: (_, idx) {
                        final s = schemas[idx];
                        return _SchemaEditorialCard(
                          schema: s,
                          onClone: () =>
                              _openSchemaEditor(base: s, cloneAsNew: true),
                          onEdit: s.isBuiltin
                              ? null
                              : () => _openSchemaEditor(base: s),
                          onDelete: s.isBuiltin
                              ? null
                              : () => runActionWithFeedback(
                                  context,
                                  () => widget.controller.deleteSchema(s.id),
                                ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SchemaEditorialCard extends StatelessWidget {
  const _SchemaEditorialCard({
    required this.schema,
    required this.onClone,
    this.onEdit,
    this.onDelete,
  });

  final PlatformSchema schema;
  final VoidCallback onClone;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: schema.isBuiltin ? c.celadonSoft : c.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  schema.isBuiltin ? '官方内置' : '自定义',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: schema.isBuiltin ? c.celadon : c.accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  schema.platform,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
              IconButton(
                tooltip: '克隆修改为新模板',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.copy_all_rounded, size: 17, color: c.muted),
                onPressed: onClone,
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: '编辑',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.edit_rounded, size: 17, color: c.muted),
                  onPressed: onEdit,
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: c.muted,
                  ),
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            schema.modelName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StyleLoomTheme.serifStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '默认语法：${schema.defaultSyntax.label} · ${schema.fields.length} 个动态控件',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: schema.fields
                    .take(6)
                    .map(
                      (f) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.trough,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          f.label,
                          style: TextStyle(fontSize: 11, color: c.ink),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
