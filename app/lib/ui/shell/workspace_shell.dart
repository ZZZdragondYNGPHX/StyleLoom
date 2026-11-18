import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../inspector/spell_inspector_page.dart';
import '../recipe/recipe_detail_panel.dart';
import '../schemas/schemas_page.dart';
import '../snippets/snippets_page.dart';
import '../sync/sync_page.dart';
import '../waterfall/waterfall_page.dart';

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  static const _platformChannel = MethodChannel('com.styleloom/platform');
  bool _draggingOver = false;
  bool _editorScheduled = false;
  RawDialogRoute<void>? _recipeRoute;
  final TextEditingController _dockSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setupShareListener();
    _dockSearchCtrl.text = widget.controller.searchQuery;
    widget.controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _dockSearchCtrl.dispose();
    _platformChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final ctrl = widget.controller;
    if (_dockSearchCtrl.text != ctrl.searchQuery) {
      _dockSearchCtrl.text = ctrl.searchQuery;
    }
    if (_editorScheduled) return;
    final shouldOpen = ctrl.activeNavIndex == 0 && ctrl.selectedRecipe != null;
    if (shouldOpen == (_recipeRoute != null)) return;
    _editorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _editorScheduled = false;
      if (!mounted) return;
      final current = _recipeRoute;
      if (ctrl.activeNavIndex != 0 || ctrl.selectedRecipe == null) {
        if (current != null && current.isActive) {
          current.navigator?.removeRoute(current);
        }
        return;
      }
      if (current != null) return;
      final route = RawDialogRoute<void>(
        barrierLabel: '关闭面板',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (context, _, _) {
          final size = MediaQuery.sizeOf(context);
          final desktop = size.width >= 900;
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (desktop)
                  GestureDetector(
                    onTap: ctrl.closeRecipeDrawer,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: const ColoredBox(color: Color(0x8A14120F)),
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(desktop ? 24 : 0),
                    child: Center(
                      child: SizedBox(
                        width: desktop
                            ? (size.width * 0.94).clamp(640, 1240).toDouble()
                            : double.infinity,
                        height: desktop
                            ? (size.height * 0.86).clamp(520, 800).toDouble()
                            : double.infinity,
                        child: ListenableBuilder(
                          listenable: ctrl,
                          builder: (context, _) {
                            final recipe = ctrl.selectedRecipe;
                            if (recipe == null) return const SizedBox.shrink();
                            return RecipeDetailPanel(
                              key: ValueKey(recipe.id),
                              controller: ctrl,
                              recipe: recipe,
                              isSpreadModal: desktop,
                              onClose: ctrl.closeRecipeDrawer,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
      _recipeRoute = route;
      await Navigator.of(context).push(route);
      _recipeRoute = null;
      if (mounted && ctrl.selectedRecipe != null) ctrl.closeRecipeDrawer();
    });
  }

  void _setupShareListener() {
    _platformChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedFile' && call.arguments is String) {
        if (mounted) {
          widget.controller.openInspectorWithFile(call.arguments as String);
        }
      }
    });
    _platformChannel
        .invokeMethod<String>('getInitialSharedFile')
        .then((path) {
          if (path != null && path.isNotEmpty && mounted) {
            widget.controller.openInspectorWithFile(path);
          }
        })
        .catchError((_) {});
  }

  Future<void> _handleDroppedFiles(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    final file = details.files.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    widget.controller.openInspectorWithBytes(bytes, file.name);
  }

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final size = MediaQuery.sizeOf(context);
        final isDesktop = size.width >= 900;

        if (ctrl.loading && !ctrl.initialized) {
          return Scaffold(
            backgroundColor: c.bg,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: c.accent),
                  const SizedBox(height: 16),
                  Text(
                    '正在展开 StyleLoom 画册与本地资产库…',
                    style: StyleLoomTheme.serifStyle(
                      fontSize: 15,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (ctrl.errorMessage != null && !ctrl.initialized) {
          return Scaffold(
            backgroundColor: c.bg,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 46,
                      color: c.accent,
                    ),
                    const SizedBox(height: 12),
                    Text('内核初始化失败：${ctrl.errorMessage}'),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: ctrl.initialize,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final mainBody = _buildMainTab(ctrl, isDesktop);
        return DropTarget(
          onDragEntered: (_) => setState(() => _draggingOver = true),
          onDragExited: (_) => setState(() => _draggingOver = false),
          onDragDone: (details) {
            setState(() => _draggingOver = false);
            _handleDroppedFiles(details);
          },
          child: Stack(
            children: [
              Scaffold(
                backgroundColor: c.bg,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 宣纸背景柔和径向微光渐变
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.7, -0.9),
                            radius: 1.15,
                            colors: [c.bgGlow, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0.85, 0.9),
                            radius: 1.0,
                            colors: [c.bgGlow, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: !isDesktop,
                      child: isDesktop
                          ? Column(
                              children: [
                                _EditorialPillDock(
                                  controller: ctrl,
                                  searchCtrl: _dockSearchCtrl,
                                ),
                                Expanded(child: mainBody),
                              ],
                            )
                          : mainBody,
                    ),
                    // 移动端悬浮毛玻璃胶囊导航栏
                    if (!isDesktop)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 12 + MediaQuery.paddingOf(context).bottom,
                        child: Center(
                          child: Material(
                            type: MaterialType.transparency,
                            child: _MobileFloatingNavPill(controller: ctrl),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 全局拖拽文件解析浮层
              if (_draggingOver)
                Positioned.fill(
                  child: IgnorePointer(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        color: c.accent.withValues(alpha: 0.14),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 22,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: c.accent, width: 1.8),
                            boxShadow: c.modalShadow,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.biotech_rounded,
                                size: 32,
                                color: c.accent,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '松开鼠标，在「透镜」中解析原图或 ComfyUI JSON',
                                style: StyleLoomTheme.serifStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainTab(AppController ctrl, bool isDesktop) {
    switch (ctrl.activeNavIndex) {
      case 0:
        return WaterfallPage(
          controller: ctrl,
          isDesktop: isDesktop,
          onOpenRecipe: ctrl.selectRecipe,
        );
      case 1:
        return SnippetsPage(controller: ctrl, isDesktop: isDesktop);
      case 2:
        return SpellInspectorPage(controller: ctrl, isDesktop: isDesktop);
      case 3:
        return SchemasPage(controller: ctrl, isDesktop: isDesktop);
      case 4:
        return SyncPage(controller: ctrl, isDesktop: isDesktop);
      default:
        return WaterfallPage(
          controller: ctrl,
          isDesktop: isDesktop,
          onOpenRecipe: ctrl.selectRecipe,
        );
    }
  }
}

/// 桌面端顶部居中悬浮毛玻璃胶囊坞
class _EditorialPillDock extends StatelessWidget {
  const _EditorialPillDock({
    required this.controller,
    required this.searchCtrl,
  });

  final AppController controller;
  final TextEditingController searchCtrl;

  static const _navItems = [
    (0, '画册'),
    (1, '积木'),
    (2, '透镜'),
    (3, '底模'),
    (4, '云匣'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.surfaceGlass,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.hairline),
                boxShadow: c.pillDockShadow,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 品牌徽记
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: c.accentSoft,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              size: 14,
                              color: c.accent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'StyleLoom',
                            style: StyleLoomTheme.serifStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: c.hairline,
                      margin: const EdgeInsets.only(right: 10),
                    ),

                    // 5 大模块胶囊导航
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: c.trough,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _navItems.map((item) {
                          final selected = controller.activeNavIndex == item.$1;
                          return InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => controller.setNavIndex(item.$1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? c.surface
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: c.shadowColor.withValues(
                                            alpha: 0.08,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (selected) ...[
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: c.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  Text(
                                    item.$2,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: selected ? c.ink : c.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // 聚光灯搜索胶囊框
                    Container(
                      width: 215,
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.trough,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, size: 15, color: c.muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: searchCtrl,
                              style: TextStyle(fontSize: 12.5, color: c.ink),
                              decoration: InputDecoration(
                                filled: false,
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: '全文搜索画师串、词条…',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: c.muted,
                                ),
                              ),
                              onChanged: (v) {
                                if (controller.activeNavIndex != 0 &&
                                    v.isNotEmpty) {
                                  controller.setNavIndex(0);
                                }
                                controller.updateFilters(query: v);
                              },
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
                                size: 14,
                                color: c.muted,
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 仅看收藏按钮
                    _DockToolPill(
                      icon: controller.favoriteOnly
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      label: '收藏',
                      active: controller.favoriteOnly,
                      tooltip: '仅看收藏画师串',
                      onTap: () {
                        if (controller.activeNavIndex != 0) {
                          controller.setNavIndex(0);
                        }
                        controller.updateFilters(
                          favorite: !controller.favoriteOnly,
                        );
                      },
                    ),

                    const SizedBox(width: 6),

                    // 列数点阵调节器 (2~6 列)
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: c.trough,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '列数',
                            style: TextStyle(fontSize: 11.5, color: c.muted),
                          ),
                          const SizedBox(width: 5),
                          for (var col = 2; col <= 6; col++)
                            Tooltip(
                              message: '$col 列瀑布流',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () =>
                                    controller.setColumns(desktop: col),
                                child: SizedBox(
                                  width: 17,
                                  height: 24,
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      width: controller.desktopColumns == col
                                          ? 8
                                          : 6,
                                      height: controller.desktopColumns == col
                                          ? 8
                                          : 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: controller.desktopColumns == col
                                            ? c.accent
                                            : c.muted.withValues(alpha: 0.45),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 6),

                    // 日间宣纸 / 暖炭夜读切换
                    _DockToolPill(
                      icon: controller.isNightMode
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      label: controller.isNightMode ? '宣纸' : '夜读',
                      tooltip: controller.isNightMode ? '切换日间宣纸调' : '切换暖炭夜读调',
                      onTap: controller.toggleNightMode,
                    ),

                    const SizedBox(width: 8),

                    // 主 CTA：新建画师串
                    FilledButton.icon(
                      onPressed: () => controller.openNewRecipeDraft(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 34),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text(
                        '新建画师串',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockToolPill extends StatelessWidget {
  const _DockToolPill({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: active ? c.accentSoft : c.trough,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? c.accent : c.muted),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? c.accent : c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 移动端底部悬浮毛玻璃胶囊导航栏
class _MobileFloatingNavPill extends StatelessWidget {
  const _MobileFloatingNavPill({required this.controller});
  final AppController controller;

  static const _items = [
    (
      0,
      Icons.auto_awesome_mosaic_outlined,
      Icons.auto_awesome_mosaic_rounded,
      '画册',
    ),
    (1, Icons.extension_outlined, Icons.extension_rounded, '积木'),
    (2, Icons.biotech_outlined, Icons.biotech_rounded, '透镜'),
    (3, Icons.tune_outlined, Icons.tune_rounded, '底模'),
    (4, Icons.cloud_sync_outlined, Icons.cloud_sync_rounded, '云匣'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: c.surfaceGlass,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.hairline),
              boxShadow: c.pillDockShadow,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _items.map((item) {
                final selected = controller.activeNavIndex == item.$1;
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => controller.setNavIndex(item.$1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? item.$3 : item.$2,
                          size: 19,
                          color: selected ? c.accent : c.muted,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.$4,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected ? c.accent : c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
