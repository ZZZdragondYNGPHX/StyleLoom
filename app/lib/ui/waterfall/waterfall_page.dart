import 'dart:io';
import 'dart:ui';

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:material_ui/material_ui.dart';

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
  void didUpdateWidget(covariant WaterfallPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchCtrl.text != widget.controller.searchQuery) {
      _searchCtrl.text = widget.controller.searchQuery;
    }
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
    final c = EditorialColors.of(context);
    final schemas = widget.controller.schemas;
    final chosen = await showDialog<PlatformSchema>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.hairline),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 450),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '克隆到其他模型（生成独立对比卡）',
                  style: StyleLoomTheme.serifStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: schemas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, idx) {
                      final s = schemas[idx];
                      final isCur = s.id == recipe.schemaId;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop(s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isCur ? c.accentSoft : c.trough,
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
                              if (isCur)
                                Text(
                                  '当前',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: c.accent,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: c.muted,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final c = EditorialColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: c.hairline,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                recipe.title.isEmpty ? '未命名画师串' : recipe.title,
                style: StyleLoomTheme.serifStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.controller.schemaById(recipe.schemaId)?.displayLabel ??
                    recipe.schemaId,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
              const SizedBox(height: 14),
              _SheetActionRow(
                icon: Icons.copy_rounded,
                label: '复制正面提示词',
                accent: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _copySide(recipe, 'positive', TargetSyntax.asIs);
                },
              ),
              _SheetActionRow(
                icon: Icons.remove_circle_outline_rounded,
                label: '复制负面提示词',
                onTap: () {
                  Navigator.pop(ctx);
                  _copySide(recipe, 'negative', TargetSyntax.asIs);
                },
              ),
              _SheetActionRow(
                icon: Icons.swap_horiz_rounded,
                label: '转换权重语法后复制正面词',
                onTap: () {
                  Navigator.pop(ctx);
                  _pickSyntaxAndCopy(recipe, 'positive');
                },
              ),
              _SheetActionRow(
                icon: Icons.copy_all_rounded,
                label: '克隆到其他模型',
                onTap: () {
                  Navigator.pop(ctx);
                  _showCloneDialog(recipe);
                },
              ),
              _SheetActionRow(
                icon: recipe.favorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                label: recipe.favorite ? '取消收藏' : '加入收藏',
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
    final c = EditorialColors.of(context);
    final target = await showDialog<TargetSyntax>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: c.surface,
        title: Text(
          '选择目标语法（${side == 'negative' ? '负面' : '正面'}）',
          style: StyleLoomTheme.serifStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
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
    final c = EditorialColors.of(context);
    final ctrl = widget.controller;
    final cols = widget.isDesktop ? ctrl.desktopColumns : ctrl.mobileColumns;
    final tags = {
      ...ctrl.allRecipeTags,
      if (ctrl.filterTag != null) ctrl.filterTag!,
    }.toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1680),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.isDesktop ? 28 : 12),
          child: Column(
            children: [
              if (ctrl.errorMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ctrl.errorMessage!,
                    style: TextStyle(fontSize: 12.5, color: c.accent),
                  ),
                ),

              // 移动端专属精简顶栏
              if (!widget.isDesktop)
                _MobileTopBar(
                  controller: ctrl,
                  searchCtrl: _searchCtrl,
                  columns: cols,
                ),

              // 杂志风无框筛选丝带 Editorial Ribbon
              _EditorialFilterRibbon(
                controller: ctrl,
                tags: tags,
                isDesktop: widget.isDesktop,
              ),

              Expanded(
                child: ctrl.recipes.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: _EmptyWaterfallView(
                            onCreate: () => ctrl.openNewRecipeDraft(),
                            onOpenInspector: () => ctrl.setNavIndex(2),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onScaleStart: (_) {
                          _baseScaleCols = cols.toDouble();
                        },
                        onScaleUpdate: (details) {
                          if (widget.isDesktop || details.pointerCount < 2) {
                            return;
                          }
                          final nextCols = (_baseScaleCols / details.scale)
                              .round()
                              .clamp(1, 4);
                          if (nextCols != ctrl.mobileColumns) {
                            ctrl.setColumns(mobile: nextCols);
                          }
                        },
                        child: MasonryGridView.count(
                          padding: EdgeInsets.only(
                            top: 18,
                            bottom: widget.isDesktop ? 42 : 96,
                          ),
                          crossAxisCount: cols,
                          mainAxisSpacing: widget.isDesktop ? 20 : 12,
                          crossAxisSpacing: widget.isDesktop ? 20 : 12,
                          itemCount: ctrl.recipes.length,
                          itemBuilder: (context, idx) {
                            final recipe = ctrl.recipes[idx];
                            final schema = ctrl.schemaById(recipe.schemaId);
                            final isSelected =
                                ctrl.selectedRecipe?.id == recipe.id;
                            return _EditorialRecipeCard(
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
                              onToggleFav: () => ctrl.toggleFavorite(recipe),
                              onCopyPositive: (t) =>
                                  _copySide(recipe, 'positive', t),
                              onCopyNegative: (t) =>
                                  _copySide(recipe, 'negative', t),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.controller,
    required this.searchCtrl,
    required this.columns,
  });

  final AppController controller;
  final TextEditingController searchCtrl;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(999),
                boxShadow: c.cardShadow,
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 17, color: c.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      style: TextStyle(fontSize: 13, color: c.ink),
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: '搜索画师串、词条、标签…',
                        hintStyle: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                      onChanged: (v) => controller.updateFilters(query: v),
                    ),
                  ),
                  if (searchCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        searchCtrl.clear();
                        controller.updateFilters(query: '');
                      },
                      child: Icon(
                        Icons.clear_rounded,
                        size: 16,
                        color: c.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _MobileCircleBtn(
            tooltip: '仅看收藏',
            active: controller.favoriteOnly,
            icon: controller.favoriteOnly
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            onTap: () =>
                controller.updateFilters(favorite: !controller.favoriteOnly),
          ),
          const SizedBox(width: 6),
          _MobileCircleBtn(
            tooltip: '切换列数 ($columns 列)',
            icon: Icons.grid_view_rounded,
            badgeText: '$columns',
            onTap: () {
              final next = columns >= 4 ? 1 : columns + 1;
              controller.setColumns(mobile: next);
            },
          ),
          const SizedBox(width: 6),
          _MobileCircleBtn(
            tooltip: controller.isNightMode ? '切换日间宣纸' : '切换暖炭夜读',
            icon: controller.isNightMode
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            onTap: controller.toggleNightMode,
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: () => controller.openNewRecipeDraft(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('新建', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _MobileCircleBtn extends StatelessWidget {
  const _MobileCircleBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.badgeText,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? c.accentSoft : c.surface,
            shape: BoxShape.circle,
            boxShadow: c.cardShadow,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 17, color: active ? c.accent : c.ink),
              if (badgeText != null)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3.5),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeText!,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFFEFA),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 极简无框杂志筛选丝带（左侧衬线平台字标 + 右侧斜体风格标签）
class _EditorialFilterRibbon extends StatelessWidget {
  const _EditorialFilterRibbon({
    required this.controller,
    required this.tags,
    required this.isDesktop,
  });

  final AppController controller;
  final List<String> tags;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    final platforms = controller.allPlatforms;
    final activePlat = controller.filterPlatform;
    final subSchemas = activePlat == null
        ? const <PlatformSchema>[]
        : controller.schemas.where((s) => s.platform == activePlat).toList();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: isDesktop ? 4 : 2, bottom: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _RibbonPlatformTab(
                      label: '全部画册',
                      supCount: controller.recipes.length,
                      selected:
                          controller.filterPlatform == null &&
                          controller.filterSchemaId == null,
                      onTap: () => controller.updateFilters(
                        clearPlatform: true,
                        clearSchema: true,
                      ),
                    ),
                    ...platforms.map(
                      (p) => _RibbonPlatformTab(
                        label: p,
                        selected: controller.filterPlatform == p,
                        onTap: () => controller.updateFilters(
                          platform: p,
                          clearSchema: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (tags.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (controller.filterTag != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: InkWell(
                            onTap: () =>
                                controller.updateFilters(clearTag: true),
                            child: Text(
                              '重置标签',
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                          ),
                        ),
                      ...tags.map((t) {
                        final active = controller.filterTag == t;
                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: InkWell(
                            onTap: () => controller.updateFilters(
                              tag: t,
                              clearTag: active,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: active
                                        ? c.accent
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              child: Text(
                                '#$t',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontStyle: active
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: active ? c.accent : c.muted,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ),
          if (subSchemas.length > 1) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SubSchemaPill(
                    label: '$activePlat · 全部底模',
                    selected: controller.filterSchemaId == null,
                    onTap: () => controller.updateFilters(clearSchema: true),
                  ),
                  ...subSchemas.map(
                    (s) => _SubSchemaPill(
                      label: s.modelName,
                      selected: controller.filterSchemaId == s.id,
                      onTap: () => controller.updateFilters(
                        platform: activePlat,
                        schemaId: s.id,
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

class _RibbonPlatformTab extends StatelessWidget {
  const _RibbonPlatformTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.supCount,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? supCount;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 22),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? c.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: StyleLoomTheme.serifStyle(
                  fontSize: 16.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? c.ink : c.muted,
                ),
              ),
              if (supCount != null) ...[
                const SizedBox(width: 2),
                Text(
                  '$supCount',
                  style: StyleLoomTheme.monoStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: c.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubSchemaPill extends StatelessWidget {
  const _SubSchemaPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.trough,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? c.accent : c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 纯享博物馆画册卡片
class _EditorialRecipeCard extends StatefulWidget {
  const _EditorialRecipeCard({
    required this.recipe,
    required this.schemaLabel,
    required this.thumbAbsPath,
    required this.selected,
    required this.isDesktop,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFav,
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
  final VoidCallback onToggleFav;
  final Future<void> Function(TargetSyntax target) onCopyPositive;
  final Future<void> Function(TargetSyntax target) onCopyNegative;

  @override
  State<_EditorialRecipeCard> createState() => _EditorialRecipeCardState();
}

class _EditorialRecipeCardState extends State<_EditorialRecipeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    final cover = widget.recipe.images.isNotEmpty
        ? widget.recipe.images.first
        : null;
    final aspect = cover?.aspectRatio ?? 0.74;
    final file = widget.thumbAbsPath.isNotEmpty
        ? File(widget.thumbAbsPath)
        : null;
    final hasFile = file != null && file.existsSync();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0,
            widget.isDesktop && _hovered ? -4 : 0,
            0,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: c.surface,
            border: widget.selected
                ? Border.all(color: c.accent, width: 2)
                : null,
            boxShadow: _hovered ? c.cardHoverShadow : c.cardShadow,
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
                  _EditorialTypographicCover(
                    title: widget.recipe.title,
                    schemaLabel: widget.schemaLabel,
                    tokenCount: widget.recipe.positiveNodes.length,
                  ),

                // 极克制右上角毛玻璃底模角标与收藏星标
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              color: c.surfaceGlass,
                              child: Text(
                                _shortModelBadge(widget.schemaLabel),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: widget.onToggleFav,
                        child: ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              width: 28,
                              height: 28,
                              color: widget.recipe.favorite
                                  ? c.surface
                                  : c.surfaceGlass,
                              alignment: Alignment.center,
                              child: Icon(
                                widget.recipe.favorite
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 15,
                                color: widget.recipe.favorite
                                    ? c.accent
                                    : c.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 有图片时的极简底部标题（悬停时让位给快捷操作栏）
                if (hasFile &&
                    widget.recipe.title.isNotEmpty &&
                    (!widget.isDesktop || !_hovered))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(11, 22, 42, 9),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.62),
                          ],
                        ),
                      ),
                      child: Text(
                        widget.recipe.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StyleLoomTheme.serifStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFFFEFA),
                        ),
                      ),
                    ),
                  ),

                // 移动端右下角轻量快捷菜单按钮
                if (!widget.isDesktop)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: GestureDetector(
                      onTap: widget.onLongPress,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c.surfaceGlass,
                          shape: BoxShape.circle,
                          boxShadow: c.cardShadow,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: 16,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),

                // 桌面端悬停升起的宣纸/炭黑微胶囊操作坞
                if (widget.isDesktop && _hovered)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.recipe.title.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 7),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x991C1A17),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.recipe.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: StyleLoomTheme.serifStyle(
                                      fontSize: 12,
                                      color: const Color(0xFFFAF7F0),
                                    ),
                                  ),
                                ),
                                if (cover != null)
                                  Text(
                                    '${cover.width}×${cover.height}',
                                    style: StyleLoomTheme.monoStyle(
                                      fontSize: 10,
                                      color: const Color(0xCCFAF7F0),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: c.surfaceGlass,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: c.modalShadow,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _HoverPillBtn(
                                      label: '复制正面',
                                      primary: true,
                                      onTap: () => widget.onCopyPositive(
                                        TargetSyntax.asIs,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: _HoverPillBtn(
                                      label: '复制负面',
                                      onTap: () => widget.onCopyNegative(
                                        TargetSyntax.asIs,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<(String, TargetSyntax)>(
                                    tooltip: '转语法后复制',
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      Icons.swap_horiz_rounded,
                                      size: 16,
                                      color: c.ink,
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
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
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
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _EditorialTypographicCover extends StatelessWidget {
  const _EditorialTypographicCover({
    required this.title,
    required this.schemaLabel,
    required this.tokenCount,
  });

  final String title;
  final String schemaLabel;
  final int tokenCount;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxHeight < 190 || bounds.maxWidth < 126) {
          return Container(
            color: c.trough,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              title.isEmpty ? '无预览图画师串' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StyleLoomTheme.serifStyle(fontSize: 13, color: c.ink),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.trough, c.surface],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 48, 18, 18),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                bottom: -18,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [c.accentSoft, Colors.transparent],
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title.isEmpty ? '无预览图画师串' : title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: StyleLoomTheme.serifStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tokenCount > 0
                        ? '$tokenCount 枚词条 · $schemaLabel'
                        : schemaLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: c.muted),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HoverPillBtn extends StatelessWidget {
  const _HoverPillBtn({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 28,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: primary ? c.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: primary ? const Color(0xFFFFFEFA) : c.ink,
          ),
        ),
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  const _SheetActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accent ? c.accentSoft : c.trough,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent ? c.accent : c.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: accent ? c.accent : c.ink,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.muted),
            ],
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
    final c = EditorialColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.auto_awesome_mosaic_rounded,
                  size: 26,
                  color: c.accent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '画师串画册还是空的',
                style: StyleLoomTheme.serifStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '可以新建画师串预设并织入词条积木，或拖入/打开一张原图从「透镜」提取封面与参数。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('新建画师串'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenInspector,
                    icon: const Icon(Icons.biotech_rounded, size: 17),
                    label: const Text('前往透镜解析'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
