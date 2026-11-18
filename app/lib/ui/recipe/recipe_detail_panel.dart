import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/prompt_capsule_editor.dart';
import '../widgets/copy_helpers.dart';
import 'dynamic_schema_form.dart';

class RecipeDetailPanel extends StatefulWidget {
  const RecipeDetailPanel({
    super.key,
    required this.controller,
    required this.recipe,
    required this.onClose,
  });

  final AppController controller;
  final StyleRecipe recipe;
  final VoidCallback onClose;

  @override
  State<RecipeDetailPanel> createState() => _RecipeDetailPanelState();
}

class _RecipeDetailPanelState extends State<RecipeDetailPanel> {
  late TextEditingController _titleCtrl;
  late TextEditingController _sourceCtrl;
  late TextEditingController _notesCtrl;
  final TextEditingController _tagCtrl = TextEditingController();

  late String _schemaId;
  late List<PromptNode> _posNodes;
  late String _posRaw;
  late List<PromptNode> _negNodes;
  late String _negRaw;
  late Map<String, dynamic> _params;
  late List<String> _tags;
  late List<RecipeImageRef> _images;
  late bool _favorite;
  late int _rating;

  int _activeImageIdx = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _sourceCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _loadFromRecipe(widget.recipe);
  }

  @override
  void didUpdateWidget(covariant RecipeDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.recipe, widget.recipe)) {
      _loadFromRecipe(widget.recipe);
    }
  }

  void _loadFromRecipe(StyleRecipe r) {
    _titleCtrl.text = r.title;
    _sourceCtrl.text = r.sourceUrl;
    _notesCtrl.text = r.notes;
    _schemaId = r.schemaId;
    _posNodes = List.of(r.positiveNodes);
    _posRaw = r.positiveRaw;
    _negNodes = List.of(r.negativeNodes);
    _negRaw = r.negativeRaw;
    _params = Map<String, dynamic>.from(r.params);
    _tags = List.of(r.tags);
    _images = List.of(r.images);
    _favorite = r.favorite;
    _rating = r.rating;
    _activeImageIdx = 0;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _sourceCtrl.dispose();
    _notesCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _switchSchema(String newSchemaId) {
    final schema = widget.controller.schemaById(newSchemaId);
    if (schema == null) return;
    final nextParams = schema.defaultParams();
    for (final entry in _params.entries) {
      if (nextParams.containsKey(entry.key)) {
        nextParams[entry.key] = entry.value;
      }
    }
    setState(() {
      _schemaId = newSchemaId;
      _params = nextParams;
    });
  }

  Future<void> _pickAndAddImages() async {
    const group = XTypeGroup(
      label: '预览图',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (files.isEmpty) return;
    final added = <RecipeImageRef>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final asset = await widget.controller.client.importImageBytes(bytes);
      added.add(asset.toRecipeRef());
    }
    if (mounted) {
      setState(() {
        _images.addAll(added);
        if (_images.isNotEmpty) {
          _activeImageIdx = _images.length - 1;
        }
      });
    }
  }

  void _showCompareDialog() {
    if (_images.length < 2) return;
    var leftIdx = 0;
    var rightIdx = 1;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('多图效果对比'),
          content: SizedBox(
            width: 820,
            height: 520,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      DropdownButton<int>(
                        value: leftIdx,
                        items: List.generate(
                          _images.length,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('图 ${i + 1}${i == 0 ? " (封面)" : ""}'),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) setDlg(() => leftIdx = v);
                        },
                      ),
                      Expanded(
                        child: InteractiveViewer(
                          child: Image.file(
                            File(
                              widget.controller.client.resolveVaultPath(
                                _images[leftIdx].blobRelPath,
                              ),
                            ),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(),
                Expanded(
                  child: Column(
                    children: [
                      DropdownButton<int>(
                        value: rightIdx,
                        items: List.generate(
                          _images.length,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('图 ${i + 1}${i == 0 ? " (封面)" : ""}'),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) setDlg(() => rightIdx = v);
                        },
                      ),
                      Expanded(
                        child: InteractiveViewer(
                          child: Image.file(
                            File(
                              widget.controller.client.resolveVaultPath(
                                _images[rightIdx].blobRelPath,
                              ),
                            ),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final recipe = StyleRecipe(
        id: widget.recipe.id,
        title: _titleCtrl.text.trim().isEmpty
            ? '未命名画师串'
            : _titleCtrl.text.trim(),
        schemaId: _schemaId,
        positiveNodes: _posNodes,
        positiveRaw: _posRaw,
        negativeNodes: _negNodes,
        negativeRaw: _negRaw,
        params: _params,
        tags: _tags,
        sourceUrl: _sourceCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        rating: _rating,
        favorite: _favorite,
        images: _images,
        createdAt: widget.recipe.createdAt,
      );
      await widget.controller.saveRecipe(recipe);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存画师串预设')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cloneToOtherModel() async {
    if (widget.recipe.id.isEmpty) {
      await _save();
    }
    if (!mounted) return;
    final schemas = widget.controller.schemas;
    final target = await showDialog<PlatformSchema>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('克隆为另一模型的独立卡片'),
        content: SizedBox(
          width: 360,
          height: 360,
          child: ListView.builder(
            itemCount: schemas.length,
            itemBuilder: (_, idx) {
              final s = schemas[idx];
              return ListTile(
                title: Text(s.modelName),
                subtitle: Text('${s.platform} · ${s.defaultSyntax.label}'),
                onTap: () => Navigator.pop(ctx, s),
              );
            },
          ),
        ),
      ),
    );
    if (target == null) return;
    final curId = widget.controller.selectedRecipe?.id ?? widget.recipe.id;
    if (curId.isEmpty) return;
    await widget.controller.cloneRecipeToSchema(curId, target.id);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已克隆为 ${target.modelName} 对比卡')));
    }
  }

  Future<void> _confirmDelete() async {
    if (widget.recipe.id.isEmpty) {
      widget.onClose();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除画师串卡片？'),
        content: Text('确定删除「${_titleCtrl.text}」？此操作可从最近备份恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.controller.deleteRecipe(widget.recipe.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schema = widget.controller.schemaById(_schemaId);
    final syntax = schema?.defaultSyntax ?? PromptSyntax.sdParens;
    final activeImg = _images.isNotEmpty
        ? _images[_activeImageIdx.clamp(0, _images.length - 1)]
        : null;

    return Container(
      color: StyleLoomTheme.bg,
      child: Column(
        children: [
          // Header action bar
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: const BoxDecoration(
              color: StyleLoomTheme.surface,
              border: Border(bottom: BorderSide(color: StyleLoomTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.recipe.id.isEmpty ? '新建画师串预设' : '画师串预设详情',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _favorite ? '取消收藏' : '收藏',
                  icon: Icon(
                    _favorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: _favorite ? StyleLoomTheme.amber : null,
                  ),
                  onPressed: () => setState(() => _favorite = !_favorite),
                ),
                if (widget.recipe.id.isNotEmpty)
                  IconButton(
                    tooltip: '克隆到其他模型',
                    icon: const Icon(Icons.copy_all_rounded, size: 20),
                    onPressed: () =>
                        runActionWithFeedback(context, _cloneToOtherModel),
                  ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: () =>
                      runActionWithFeedback(context, _confirmDelete),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: Text(_saving ? '保存中…' : '保存'),
                ),
                IconButton(
                  tooltip: '关闭面板',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // Preview image carousel
                Container(
                  decoration: BoxDecoration(
                    color: StyleLoomTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StyleLoomTheme.border),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (activeImg != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 280),
                            child: GestureDetector(
                              onTap: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (ctx) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.file(
                                        File(
                                          widget.controller.client
                                              .resolveVaultPath(
                                                activeImg.blobRelPath,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Image.file(
                                File(
                                  widget.controller.client.resolveVaultPath(
                                    activeImg.blobRelPath,
                                  ),
                                ),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => runActionWithFeedback(
                              context,
                              _pickAndAddImages,
                            ),
                            icon: const Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              '添加预览图',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_images.length >= 2)
                            OutlinedButton.icon(
                              onPressed: _showCompareDialog,
                              icon: const Icon(Icons.compare_rounded, size: 16),
                              label: const Text(
                                '双图对比',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          const Spacer(),
                          if (activeImg != null) ...[
                            if (_activeImageIdx != 0)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    final item = _images.removeAt(
                                      _activeImageIdx,
                                    );
                                    _images.insert(0, item);
                                    _activeImageIdx = 0;
                                  });
                                },
                                child: const Text(
                                  '设为封面',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            IconButton(
                              tooltip: '移除当前图片',
                              icon: const Icon(
                                Icons.delete_sweep_rounded,
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _images.removeAt(_activeImageIdx);
                                  _activeImageIdx = 0;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                      if (_images.length > 1) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 54,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _images.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (_, idx) {
                              final img = _images[idx];
                              final active = idx == _activeImageIdx;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _activeImageIdx = idx),
                                child: Container(
                                  width: 54,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: active
                                          ? StyleLoomTheme.accent
                                          : StyleLoomTheme.border,
                                      width: active ? 2 : 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.file(
                                    File(
                                      widget.controller.client.resolveVaultPath(
                                        img.thumbRelPath,
                                      ),
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Title & Platform/Model selector
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '画师串预设名称',
                    hintText: '例如：厚涂冷光赛博串 / Ask 混搭风',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(_schemaId),
                  initialValue: _schemaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '生图平台与底模（决定参数面板）',
                  ),
                  items: [
                    if (!widget.controller.schemas.any(
                      (s) => s.id == _schemaId,
                    ))
                      DropdownMenuItem(
                        value: _schemaId,
                        child: Text('模板不可用：$_schemaId'),
                      ),
                    ...widget.controller.schemas
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              '${s.platform} · ${s.modelName}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                  ],
                  onChanged: (v) {
                    if (v != null) _switchSchema(v);
                  },
                ),

                const SizedBox(height: 12),

                // Positive & Negative Prompt Capsule Editors
                PromptCapsuleEditor(
                  key: ValueKey(
                    '${widget.recipe.id}_${widget.recipe.updatedAt}_positive',
                  ),
                  label: '正面提示词',
                  client: widget.controller.client,
                  nodes: _posNodes,
                  rawText: _posRaw,
                  modelSyntax: syntax,
                  availableSnippets: widget.controller.snippets,
                  onChanged: (nodes, raw) {
                    setState(() {
                      _posNodes = nodes;
                      _posRaw = raw;
                    });
                  },
                ),
                const SizedBox(height: 12),
                PromptCapsuleEditor(
                  key: ValueKey(
                    '${widget.recipe.id}_${widget.recipe.updatedAt}_negative',
                  ),
                  label: '负面提示词',
                  client: widget.controller.client,
                  nodes: _negNodes,
                  rawText: _negRaw,
                  modelSyntax: syntax,
                  availableSnippets: widget.controller.snippets,
                  onChanged: (nodes, raw) {
                    setState(() {
                      _negNodes = nodes;
                      _negRaw = raw;
                    });
                  },
                ),

                const SizedBox(height: 12),

                // Dynamic Schema Interactive Parameters
                if (schema != null) ...[
                  Material(
                    color: StyleLoomTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: StyleLoomTheme.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.tune_rounded,
                                size: 16,
                                color: StyleLoomTheme.accent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${schema.modelName} 可交互参数',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          DynamicSchemaForm(
                            schema: schema,
                            values: _params,
                            onChanged: (next) => setState(() => _params = next),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Tags & Notes
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StyleLoomTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StyleLoomTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '画风标签与来源备注',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _tags
                            .map(
                              (t) => InputChip(
                                label: Text('#$t'),
                                onDeleted: () =>
                                    setState(() => _tags.remove(t)),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tagCtrl,
                              decoration: const InputDecoration(
                                hintText: '添加画风标签（如 厚涂、赛璐璐、平涂）…',
                              ),
                              onSubmitted: (v) {
                                final clean = v.trim();
                                if (clean.isNotEmpty &&
                                    !_tags.contains(clean)) {
                                  setState(() => _tags.add(clean));
                                }
                                _tagCtrl.clear();
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.add_rounded, size: 18),
                            onPressed: () {
                              final clean = _tagCtrl.text.trim();
                              if (clean.isNotEmpty && !_tags.contains(clean)) {
                                setState(() => _tags.add(clean));
                              }
                              _tagCtrl.clear();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _sourceCtrl,
                        decoration: const InputDecoration(
                          labelText: '来源链接 / 贴主',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(labelText: '调参备注'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
