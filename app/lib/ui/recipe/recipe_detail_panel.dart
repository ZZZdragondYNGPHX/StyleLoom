import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/copy_helpers.dart';
import '../widgets/prompt_capsule_editor.dart';
import 'dynamic_schema_form.dart';

class RecipeDetailPanel extends StatefulWidget {
  const RecipeDetailPanel({
    super.key,
    required this.controller,
    required this.recipe,
    required this.onClose,
    this.isSpreadModal = false,
  });

  final AppController controller;
  final StyleRecipe recipe;
  final VoidCallback onClose;
  final bool isSpreadModal;

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
  int _activeTab = 0; // 0: 咒语编织, 1: 底模参数, 2: 溯源手记
  bool _abCompareMode = false;
  int _abLeftIdx = 0;
  int _abRightIdx = 1;
  double _curtainFraction = 0.5;
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
    _abCompareMode = false;
    _abLeftIdx = 0;
    _abRightIdx = _images.length > 1 ? 1 : 0;
    _curtainFraction = 0.5;
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
          if (_images.length >= 2 && _abRightIdx == 0) {
            _abRightIdx = 1;
          }
        }
      });
    }
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
    final c = EditorialColors.of(context);
    final schemas = widget.controller.schemas;
    final target = await showDialog<PlatformSchema>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.hairline),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 460),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '克隆为另一模型的独立卡片',
                  style: StyleLoomTheme.serifStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '选择目标底模并自动转写词条权重语法',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: schemas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, idx) {
                      final s = schemas[idx];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(ctx, s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
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
                                      s.modelName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: c.ink,
                                      ),
                                    ),
                                    Text(
                                      '${s.platform} · ${s.defaultSyntax.label}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: c.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: c.accent,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (target == null) return;
    final curId = widget.controller.selectedRecipe?.id ?? widget.recipe.id;
    if (curId.isEmpty) return;
    await widget.controller.cloneRecipeToSchema(curId, target.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已克隆为 ${target.modelName} 对比卡')),
      );
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
    final c = EditorialColors.of(context);
    final schema = widget.controller.schemaById(_schemaId);
    final syntax = schema?.defaultSyntax ?? PromptSyntax.sdParens;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide =
            widget.isSpreadModal && constraints.maxWidth >= 780;
        if (useSideBySide) {
          return Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: c.modalShadow,
                border: Border.all(color: c.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 104,
                    child: _buildMuseumStage(context, schema, isCompact: false),
                  ),
                  Expanded(
                    flex: 100,
                    child: _buildRightWorkbench(context, schema, syntax),
                  ),
                ],
              ),
            ),
          );
        }

        // 移动端或窄窗体：纵向流式画册抽屉
        return Material(
          color: c.surface,
          child: Column(
            children: [
              _buildWorkbenchHeader(context, schema),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    SizedBox(
                      height: 310,
                      child: _buildMuseumStage(
                        context,
                        schema,
                        isCompact: true,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _buildTabStrip(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: _buildActiveTabContent(context, schema, syntax),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMuseumStage(
    BuildContext context,
    PlatformSchema? schema, {
    required bool isCompact,
  }) {
    final c = EditorialColors.of(context);
    final activeIdx = _images.isEmpty
        ? 0
        : _activeImageIdx.clamp(0, _images.length - 1);
    final activeImg = _images.isNotEmpty ? _images[activeIdx] : null;
    final leftIdx = _images.isEmpty ? 0 : _abLeftIdx.clamp(0, _images.length - 1);
    final rightIdx = _images.isEmpty
        ? 0
        : _abRightIdx.clamp(0, _images.length - 1);

    return Container(
      color: c.museumBg,
      padding: EdgeInsets.fromLTRB(
        isCompact ? 14 : 20,
        isCompact ? 12 : 18,
        isCompact ? 14 : 20,
        isCompact ? 12 : 16,
      ),
      child: Column(
        children: [
          // 舞台顶栏
          Row(
            children: [
              Expanded(
                child: Text(
                  activeImg == null
                      ? (schema?.modelName ?? '视觉画框舞台')
                      : '${activeImg.width}×${activeImg.height} · ${activeIdx + 1}/${_images.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StyleLoomTheme.monoStyle(
                    fontSize: 12,
                    color: const Color(0xFFF3EFE7).withValues(alpha: 0.78),
                  ),
                ),
              ),
              if (_images.length >= 2)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () =>
                        setState(() => _abCompareMode = !_abCompareMode),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: _abCompareMode
                            ? c.accent
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.compare_rounded,
                            size: 14,
                            color: Color(0xFFFFFEFA),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _abCompareMode ? '退出拉帘' : 'A/B 拉帘对比',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFFFEFA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => runActionWithFeedback(context, _pickAndAddImages),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_rounded,
                        size: 14,
                        color: Color(0xFFFFFEFA),
                      ),
                      SizedBox(width: 5),
                      Text(
                        '添图',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFFFFEFA),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (activeImg != null) ...[
                if (activeIdx != 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        setState(() {
                          final item = _images.removeAt(activeIdx);
                          _images.insert(0, item);
                          _activeImageIdx = 0;
                        });
                      },
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '设为封面',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFFFFEFA),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '移除当前图片',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _images.removeAt(activeIdx);
                      _activeImageIdx = 0;
                      _abCompareMode = false;
                    });
                  },
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: const Color(0xFFF3EFE7).withValues(alpha: 0.72),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // 中央高清展台 / A-B 拉帘对比器
          Expanded(
            child: activeImg == null
                ? Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () =>
                          runActionWithFeedback(context, _pickAndAddImages),
                      child: Container(
                        width: 260,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 36,
                              color: c.accent,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '点击添加出图样张',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFF3EFE7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '添加 2 张以上即可体验左右拖动 A/B 拉帘对比',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: const Color(
                                  0xFFF3EFE7,
                                ).withValues(alpha: 0.58),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : (_abCompareMode && _images.length >= 2)
                ? _CurtainCompareStage(
                    leftFile: File(
                      widget.controller.client.resolveVaultPath(
                        _images[leftIdx].blobRelPath,
                      ),
                    ),
                    rightFile: File(
                      widget.controller.client.resolveVaultPath(
                        _images[rightIdx].blobRelPath,
                      ),
                    ),
                    leftLabel: 'A · 图 ${leftIdx + 1}',
                    rightLabel: 'B · 图 ${rightIdx + 1}',
                    fraction: _curtainFraction,
                    onFractionChanged: (v) =>
                        setState(() => _curtainFraction = v),
                  )
                : Center(
                    child: GestureDetector(
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: c.museumBg,
                            child: InteractiveViewer(
                              child: Image.file(
                                File(
                                  widget.controller.client.resolveVaultPath(
                                    activeImg.blobRelPath,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
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
          ),

          // A/B 拉帘变体选择器
          if (_abCompareMode && _images.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StageVariantDropdown(
                    prefix: '左图 A',
                    value: leftIdx,
                    count: _images.length,
                    onChanged: (v) => setState(() => _abLeftIdx = v),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.compare_arrows_rounded,
                    size: 16,
                    color: Color(0x99F3EFE7),
                  ),
                  const SizedBox(width: 10),
                  _StageVariantDropdown(
                    prefix: '右图 B',
                    value: rightIdx,
                    count: _images.length,
                    onChanged: (v) => setState(() => _abRightIdx = v),
                  ),
                ],
              ),
            ),

          // 底部胶片缩略切换条
          if (_images.length > 1)
            Container(
              height: 52,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                ),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final img = _images[idx];
                  final active = idx == activeIdx;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() {
                      _activeImageIdx = idx;
                      _abCompareMode = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: active
                            ? Border.all(color: c.accent, width: 1.5)
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: Image.file(
                                File(
                                  widget.controller.client.resolveVaultPath(
                                    img.thumbRelPath,
                                  ),
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            idx == 0 ? '封面' : '图 ${idx + 1}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: active
                                  ? const Color(0xFFFFFEFA)
                                  : const Color(0xBFF3EFE7),
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRightWorkbench(
    BuildContext context,
    PlatformSchema? schema,
    PromptSyntax syntax,
  ) {
    return Column(
      children: [
        _buildWorkbenchHeader(context, schema),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
          child: _buildTabStrip(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            children: [_buildActiveTabContent(context, schema, syntax)],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkbenchHeader(BuildContext context, PlatformSchema? schema) {
    final c = EditorialColors.of(context);
    final isNew = widget.recipe.id.isEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        widget.isSpreadModal ? 22 : 16,
        16,
        14,
        12,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNew ? '新建画师串预设' : '画师串预设详情',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StyleLoomTheme.serifStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${schema?.displayLabel ?? _schemaId}${_titleCtrl.text.trim().isEmpty ? "" : " · ${_titleCtrl.text.trim()}"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _favorite ? '取消收藏' : '收藏',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _favorite ? c.accent : c.muted,
            ),
            onPressed: () => setState(() => _favorite = !_favorite),
          ),
          if (!isNew)
            IconButton(
              tooltip: '克隆到其他模型',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_all_rounded, size: 19, color: c.muted),
              onPressed: () =>
                  runActionWithFeedback(context, _cloneToOtherModel),
            ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded, size: 19, color: c.muted),
            onPressed: () => runActionWithFeedback(context, _confirmDelete),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text(_saving ? '保存中…' : '保存'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '关闭面板',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: c.muted),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildTabStrip(BuildContext context) {
    final c = EditorialColors.of(context);
    const tabs = [
      (0, '01', '咒语编织'),
      (1, '02', '底模参数'),
      (2, '03', '溯源手记'),
    ];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((t) {
            final active = _activeTab == t.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 22),
              child: InkWell(
                onTap: () => setState(() => _activeTab = t.$1),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 10, top: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: active ? c.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.$2,
                        style: StyleLoomTheme.serifStyle(
                          fontSize: 11,
                          color: active ? c.accent : c.muted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t.$3,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? c.ink : c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(
    BuildContext context,
    PlatformSchema? schema,
    PromptSyntax syntax,
  ) {
    final c = EditorialColors.of(context);
    switch (_activeTab) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '画师串预设名称',
                hintText: '例如：厚涂冷光赛博串 / Ask 混搭风',
              ),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 18),
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
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.trough,
                borderRadius: BorderRadius.circular(14),
              ),
              child: DropdownButtonFormField<String>(
                key: ValueKey(_schemaId),
                initialValue: _schemaId,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surface,
                  labelText: '生图平台与底模（决定参数控件）',
                ),
                items: [
                  if (!widget.controller.schemas.any((s) => s.id == _schemaId))
                    DropdownMenuItem(
                      value: _schemaId,
                      child: Text('模板不可用：$_schemaId'),
                    ),
                  ...widget.controller.schemas.map(
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
            ),
            const SizedBox(height: 14),
            if (schema != null)
              DynamicSchemaForm(
                schema: schema,
                values: _params,
                onChanged: (next) => setState(() => _params = next),
              ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.trough,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '画风标签',
                    style: StyleLoomTheme.serifStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_tags.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _tags
                          .map(
                            (t) => InputChip(
                              backgroundColor: c.surface,
                              label: Text('#$t'),
                              onDeleted: () => setState(() => _tags.remove(t)),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagCtrl,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: c.surface,
                            hintText: '添加画风标签（如 厚涂、赛璐璐、平涂）…',
                          ),
                          onSubmitted: (v) {
                            final clean = v.trim();
                            if (clean.isNotEmpty && !_tags.contains(clean)) {
                              setState(() => _tags.add(clean));
                            }
                            _tagCtrl.clear();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          final clean = _tagCtrl.text.trim();
                          if (clean.isNotEmpty && !_tags.contains(clean)) {
                            setState(() => _tags.add(clean));
                          }
                          _tagCtrl.clear();
                        },
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _sourceCtrl,
              decoration: const InputDecoration(labelText: '来源链接 / 贴主'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 4,
              minLines: 3,
              decoration: const InputDecoration(labelText: '调参手记'),
            ),
            if (widget.recipe.id.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '跨底模并排实验',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: c.accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '克隆当前画师串到其他底模并自动转写权重语法',
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () =>
                          runActionWithFeedback(context, _cloneToOtherModel),
                      icon: const Icon(Icons.copy_all_rounded, size: 15),
                      label: const Text('克隆转写'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
    }
  }
}

class _StageVariantDropdown extends StatelessWidget {
  const _StageVariantDropdown({
    required this.prefix,
    required this.value,
    required this.count,
    required this.onChanged,
  });

  final String prefix;
  final int value;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          dropdownColor: const Color(0xFF1F1C19),
          style: const TextStyle(fontSize: 12, color: Color(0xFFFFFEFA)),
          items: List.generate(
            count,
            (i) => DropdownMenuItem(
              value: i,
              child: Text('$prefix · ${i == 0 ? "封面" : "图 ${i + 1}"}'),
            ),
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// 可左右拖动分割线的 A/B 双图拉帘对比器
class _CurtainCompareStage extends StatelessWidget {
  const _CurtainCompareStage({
    required this.leftFile,
    required this.rightFile,
    required this.leftLabel,
    required this.rightLabel,
    required this.fraction,
    required this.onFractionChanged,
  });

  final File leftFile;
  final File rightFile;
  final String leftLabel;
  final String rightLabel;
  final double fraction;
  final ValueChanged<double> onFractionChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) {
        final width = box.maxWidth <= 0 ? 1.0 : box.maxWidth;
        final dividerX = width * fraction.clamp(0.05, 0.95);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            final next = (details.localPosition.dx / width).clamp(0.05, 0.95);
            onFractionChanged(next);
          },
          onTapDown: (details) {
            final next = (details.localPosition.dx / width).clamp(0.05, 0.95);
            onFractionChanged(next);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(rightFile, fit: BoxFit.contain),
                ClipRect(
                  clipper: _LeftCurtainClipper(fraction),
                  child: Image.file(leftFile, fit: BoxFit.contain),
                ),
                Positioned(
                  left: dividerX - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: const Color(0xEBFFFEFA),
                  ),
                ),
                Positioned(
                  left: dividerX - 17,
                  top: (box.maxHeight / 2) - 17,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFEFA),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.compare_arrows_rounded,
                      size: 18,
                      color: Color(0xFF1C1A17),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _CurtainBadge(label: leftLabel),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: _CurtainBadge(label: rightLabel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CurtainBadge extends StatelessWidget {
  const _CurtainBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xBF14120F),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFFF3EFE7),
        ),
      ),
    );
  }
}

class _LeftCurtainClipper extends CustomClipper<Rect> {
  const _LeftCurtainClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * fraction.clamp(0.05, 0.95), size.height);
  }

  @override
  bool shouldReclip(covariant _LeftCurtainClipper oldClipper) {
    return oldClipper.fraction != fraction;
  }
}
