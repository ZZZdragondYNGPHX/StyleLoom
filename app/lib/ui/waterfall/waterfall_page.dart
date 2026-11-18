import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/copy_helpers.dart';

class WaterfallPage extends StatefulWidget {
  const WaterfallPage({
    super.key,
    required this.controller,
    required this.isDesktop,
    required this.onOpenRecipe,
  });

  final AppController controller;
  final bool isDesktop;
  final ValueChanged<StyleRecipe> onOpenRecipe;

  @override
  State<WaterfallPage> createState() => _WaterfallPageState();
}

class _WaterfallPageState extends State<WaterfallPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  double _baseScaleCols = 2.0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.controller.searchQuery;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _copySide(
    StyleRecipe recipe,
    String side,
    TargetSyntax target,
  ) async {
    final text = await widget.controller.client.renderRecipePrompt(
      recipeId: recipe.id,
      side: side,
      targetSyntax: target,
    );
    if (!mounted) return;
    await copyTextWithFeedback(
      context,
      text,
      side == 'negative' ? '负面提示词' : '正面提示词',
    );
  }

  Future<void> _showCloneDialog(StyleRecipe recipe) async {
    final schemas = widget.controller.schemas;
    final chosen = await showDialog<PlatformSchema>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('克隆到其他模型（生成独立对比卡）'),
        content: SizedBox(
          width: 380,
          height: 360,
          child: ListView.builder(
            itemCount: schemas.length,
            itemBuilder: (_, idx) {
              final s = schemas[idx];
              return ListTile(
                title: Text(s.modelName),
                subtitle: Text('${s.platform} · ${s.defaultSyntax.label}'),
                trailing: s.id == recipe.schemaId
                    ? const Chip(label: Text('当前'))
                    : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () => Navigator.of(ctx).pop(s),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    final cloned = await widget.controller.cloneRecipeToSchema(
      recipe.id,
      chosen.id,
    );
    if (!mounted) return;
    widget.onOpenRecipe(cloned);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已克隆为「${cloned.title}」')));
  }

  void _showMobileQuickMenu(StyleRecipe recipe) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: StyleLoomTheme.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  recipe.title.isEmpty ? '未命名画师串' : recipe.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  widget.controller.schemaById(recipe.schemaId)?.displayLabel ??
                      recipe.schemaId,
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('复制正面提示词'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copySide(recipe, 'positive', TargetSyntax.asIs);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: const Text('复制负面提示词'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copySide(recipe, 'negative', TargetSyntax.asIs);
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('转换权重语法后复制正面词'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickSyntaxAndCopy(recipe, 'positive');
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_all_rounded),
                title: const Text('克隆到其他模型'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCloneDialog(recipe);
                },
              ),
              ListTile(
                leading: Icon(
                  recipe.favorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: recipe.favorite ? StyleLoomTheme.amber : null,
                ),
                title: Text(recipe.favorite ? '取消收藏' : '加入收藏'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.toggleFavorite(recipe);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSyntaxAndCopy(StyleRecipe recipe, String side) async {
    final target = await showDialog<TargetSyntax>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('选择目标语法（${side == 'negative' ? '负面' : '正面'}）'),
        children: TargetSyntax.values
            .map(
              (t) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(t.label),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (target != null) {
      await _copySide(recipe, side, target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final cols = widget.isDesktop ? ctrl.desktopColumns : ctrl.mobileColumns;
    final tags = {
      ...ctrl.allRecipeTags,
      if (ctrl.filterTag != null) ctrl.filterTag!,
    }.toList();

    return Column(
      children: [
        if (ctrl.errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(ctrl.errorMessage!),
          ),
        _ToolbarHeader(
          controller: ctrl,
          searchCtrl: _searchCtrl,
          isDesktop: widget.isDesktop,
          columns: cols,
          tags: tags,
        ),
        Expanded(
          child: ctrl.recipes.isEmpty
              ? _EmptyWaterfallView(
                  onCreate: () => ctrl.openNewRecipeDraft(),
                  onOpenInspector: () => ctrl.setNavIndex(2),
                )
              : GestureDetector(
                  onScaleStart: (_) {
                    _baseScaleCols = cols.toDouble();
                  },
                  onScaleUpdate: (details) {
                    if (widget.isDesktop || details.pointerCount < 2) return;
                    final nextCols = (_baseScaleCols / details.scale)
                        .round()
                        .clamp(1, 4);
                    if (nextCols != ctrl.mobileColumns) {
                      ctrl.setColumns(mobile: nextCols);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    child: MasonryGridView.count(
                      crossAxisCount: cols,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      itemCount: ctrl.recipes.length,
                      itemBuilder: (context, idx) {
                        final recipe = ctrl.recipes[idx];
                        final schema = ctrl.schemaById(recipe.schemaId);
                        final isSelected = ctrl.selectedRecipe?.id == recipe.id;
                        return _MinimalistRecipeCard(
                          recipe: recipe,
                          schemaLabel: schema?.modelName ?? recipe.schemaId,
                          thumbAbsPath: recipe.images.isNotEmpty
                              ? ctrl.client.resolveVaultPath(
                                  recipe.images.first.thumbRelPath,
                                )
                              : '',
                          selected: isSelected,
                          isDesktop: widget.isDesktop,
                          onTap: () => widget.onOpenRecipe(recipe),
                          onLongPress: () => _showMobileQuickMenu(recipe),
                          onCopyPositive: (t) =>
                              _copySide(recipe, 'positive', t),
                          onCopyNegative: (t) =>
                              _copySide(recipe, 'negative', t),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ToolbarHeader extends StatelessWidget {
  const _ToolbarHeader({
    required this.controller,
    required this.searchCtrl,
    required this.isDesktop,
    required this.columns,
    required this.tags,
  });

  final AppController controller;
  final TextEditingController searchCtrl;
  final bool isDesktop;
  final int columns;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: StyleLoomTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: '全文搜索画师串、词条、标签或笔记…',
                    suffixIcon: searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              searchCtrl.clear();
                              controller.updateFilters(query: '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => controller.updateFilters(query: v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '仅看收藏',
                icon: Icon(
                  controller.favoriteOnly
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: controller.favoriteOnly ? StyleLoomTheme.amber : null,
                ),
                onPressed: () => controller.updateFilters(
                  favorite: !controller.favoriteOnly,
                ),
              ),
              if (isDesktop) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.grid_view_rounded,
                  size: 16,
                  color: StyleLoomTheme.textSecondary,
                ),
                SizedBox(
                  width: 110,
                  child: Slider(
                    value: columns.toDouble(),
                    min: 2,
                    max: 8,
                    divisions: 6,
                    label: '$columns 列',
                    onChanged: (v) => controller.setColumns(desktop: v.round()),
                  ),
                ),
              ] else ...[
                IconButton(
                  tooltip: '切换瀑布流列数 ($columns 列)',
                  icon: Badge(
                    label: Text('$columns'),
                    child: const Icon(Icons.grid_view_rounded, size: 20),
                  ),
                  onPressed: () {
                    final next = columns >= 4 ? 1 : columns + 1;
                    controller.setColumns(mobile: next);
                  },
                ),
              ],
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: () => controller.openNewRecipeDraft(),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text(isDesktop ? '新建画师串' : '新建'),
              ),
            ],
          ),
          if (!isDesktop || tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (!isDesktop) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('全部平台'),
                        selected:
                            controller.filterPlatform == null &&
                            controller.filterSchemaId == null,
                        onSelected: (_) => controller.updateFilters(
                          clearPlatform: true,
                          clearSchema: true,
                        ),
                      ),
                    ),
                    ...controller.allPlatforms.map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(p),
                          selected: controller.filterPlatform == p,
                          onSelected: (_) => controller.updateFilters(
                            platform: controller.filterPlatform == p ? null : p,
                            clearPlatform: controller.filterPlatform == p,
                          ),
                        ),
                      ),
                    ),
                  ],
                  ...tags.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('#$t'),
                        selected: controller.filterTag == t,
                        onSelected: (_) => controller.updateFilters(
                          tag: t,
                          clearTag: controller.filterTag == t,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MinimalistRecipeCard extends StatefulWidget {
  const _MinimalistRecipeCard({
    required this.recipe,
    required this.schemaLabel,
    required this.thumbAbsPath,
    required this.selected,
    required this.isDesktop,
    required this.onTap,
    required this.onLongPress,
    required this.onCopyPositive,
    required this.onCopyNegative,
  });

  final StyleRecipe recipe;
  final String schemaLabel;
  final String thumbAbsPath;
  final bool selected;
  final bool isDesktop;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<void> Function(TargetSyntax target) onCopyPositive;
  final Future<void> Function(TargetSyntax target) onCopyNegative;

  @override
  State<_MinimalistRecipeCard> createState() => _MinimalistRecipeCardState();
}

class _MinimalistRecipeCardState extends State<_MinimalistRecipeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cover = widget.recipe.images.isNotEmpty
        ? widget.recipe.images.first
        : null;
    final aspect = cover?.aspectRatio ?? 0.72;
    final file = widget.thumbAbsPath.isNotEmpty
        ? File(widget.thumbAbsPath)
        : null;
    final hasFile = file != null && file.existsSync();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected
                  ? StyleLoomTheme.accent
                  : (_hovered
                        ? StyleLoomTheme.accent.withValues(alpha: 0.6)
                        : StyleLoomTheme.border),
              width: widget.selected ? 2 : 1,
            ),
            color: StyleLoomTheme.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasFile)
                  Image.file(
                    file,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  )
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1F2437), Color(0xFF151824)],
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 28,
                            color: StyleLoomTheme.accent,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.recipe.title.isEmpty
                                ? '无预览图'
                                : widget.recipe.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Subtle top-left model badge (pure minimalist)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.56),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _shortModelBadge(widget.schemaLabel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      if (widget.recipe.favorite)
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: StyleLoomTheme.amber,
                          ),
                        ),
                    ],
                  ),
                ),

                // Minimalist bottom title overlay only when image exists and not hovering
                if (hasFile &&
                    widget.recipe.title.isNotEmpty &&
                    (!widget.isDesktop || !_hovered))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(9, 18, 9, 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                          ],
                        ),
                      ),
                      child: Text(
                        widget.recipe.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                // Desktop Hover Frosted Quick-Copy Bar
                if (widget.isDesktop && _hovered)
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _HoverActionChip(
                              label: '复制正面',
                              onTap: () =>
                                  widget.onCopyPositive(TargetSyntax.asIs),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _HoverActionChip(
                              label: '复制负面',
                              onTap: () =>
                                  widget.onCopyNegative(TargetSyntax.asIs),
                            ),
                          ),
                          const SizedBox(width: 2),
                          PopupMenuButton<(String, TargetSyntax)>(
                            tooltip: '转语法后复制',
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.swap_horiz_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            onSelected: (pair) {
                              if (pair.$1 == 'pos') {
                                widget.onCopyPositive(pair.$2);
                              } else {
                                widget.onCopyNegative(pair.$2);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                enabled: false,
                                child: Text(
                                  '转换语法复制正面词',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              ...TargetSyntax.values
                                  .where((t) => t != TargetSyntax.asIs)
                                  .map(
                                    (t) => PopupMenuItem(
                                      value: ('pos', t),
                                      child: Text(
                                        '正面 → ${t.label}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                enabled: false,
                                child: Text(
                                  '转换语法复制负面词',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              ...TargetSyntax.values
                                  .where((t) => t != TargetSyntax.asIs)
                                  .map(
                                    (t) => PopupMenuItem(
                                      value: ('neg', t),
                                      child: Text(
                                        '负面 → ${t.label}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverActionChip extends StatelessWidget {
  const _HoverActionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: StyleLoomTheme.accent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _shortModelBadge(String full) {
  return full
      .replaceAll('NovelAI Diffusion ', 'NAI ')
      .replaceAll(' (V-Pred / Eps)', '')
      .replaceAll(' (Base / Aesthetic)', ' Base')
      .replaceAll(' (Turbo)', ' Turbo');
}

class _EmptyWaterfallView extends StatelessWidget {
  const _EmptyWaterfallView({
    required this.onCreate,
    required this.onOpenInspector,
  });

  final VoidCallback onCreate;
  final VoidCallback onOpenInspector;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome_mosaic_rounded,
                  size: 46,
                  color: StyleLoomTheme.accent,
                ),
                const SizedBox(height: 12),
                const Text(
                  '画师串瀑布流还是空的',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '你可以新建一张画师串预设卡片，或者直接把 NovelAI / ComfyUI 原图与工作流 JSON 拖进窗口，在解析器中查看并分项复制咒语。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: StyleLoomTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('新建画师串预设'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenInspector,
                      icon: const Icon(Icons.biotech_rounded, size: 18),
                      label: const Text('打开原图解析器'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
