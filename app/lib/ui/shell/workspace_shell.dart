import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

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
  bool _mobileEditorOpen = false;
  MaterialPageRoute<void>? _mobileRecipeRoute;

  @override
  void initState() {
    super.initState();
    _setupShareListener();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _platformChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final ctrl = widget.controller;
    if (_mobileEditorOpen) {
      if (ctrl.selectedRecipe == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final route = _mobileRecipeRoute;
          if (mounted && route != null && route.isCurrent) {
            route.navigator?.pop();
          }
        });
      }
      return;
    }
    if (ctrl.activeNavIndex != 0 ||
        ctrl.selectedRecipe == null ||
        MediaQuery.sizeOf(context).width >= 960) {
      return;
    }
    _mobileEditorOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (ctrl.selectedRecipe == null) {
        _mobileEditorOpen = false;
        return;
      }
      final route = MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: SafeArea(
            child: ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) {
                final recipe = ctrl.selectedRecipe;
                if (recipe == null) return const SizedBox.shrink();
                return RecipeDetailPanel(
                  key: ValueKey(recipe.id),
                  controller: ctrl,
                  recipe: recipe,
                  onClose: ctrl.closeRecipeDrawer,
                );
              },
            ),
          ),
        ),
      );
      _mobileRecipeRoute = route;
      await Navigator.of(context).push(route);
      _mobileRecipeRoute = null;
      ctrl.closeRecipeDrawer();
      _mobileEditorOpen = false;
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final width = MediaQuery.of(context).size.width;
        final isDesktop = width >= 960;

        if (ctrl.loading && !ctrl.initialized) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('正在加载 StyleLoom 本地内核与资产库…'),
                ],
              ),
            ),
          );
        }

        if (ctrl.errorMessage != null && !ctrl.initialized) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 46,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 10),
                    Text('内核初始化失败：${ctrl.errorMessage}'),
                    const SizedBox(height: 12),
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
                body: SafeArea(
                  child: isDesktop
                      ? Row(
                          children: [
                            _DesktopLeftSidebar(controller: ctrl),
                            const VerticalDivider(width: 1),
                            Expanded(child: mainBody),
                            if (ctrl.activeNavIndex == 0 &&
                                ctrl.selectedRecipe != null) ...[
                              const VerticalDivider(width: 1),
                              SizedBox(
                                width: width > 1360 ? 480 : 410,
                                child: RecipeDetailPanel(
                                  key: ValueKey(ctrl.selectedRecipe!.id),
                                  controller: ctrl,
                                  recipe: ctrl.selectedRecipe!,
                                  onClose: ctrl.closeRecipeDrawer,
                                ),
                              ),
                            ],
                          ],
                        )
                      : mainBody,
                ),
                bottomNavigationBar: isDesktop
                    ? null
                    : NavigationBar(
                        selectedIndex: ctrl.activeNavIndex,
                        onDestinationSelected: ctrl.setNavIndex,
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.auto_awesome_mosaic_outlined),
                            selectedIcon: Icon(
                              Icons.auto_awesome_mosaic_rounded,
                            ),
                            label: '画师串',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.extension_outlined),
                            selectedIcon: Icon(Icons.extension_rounded),
                            label: '词条预设',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.biotech_outlined),
                            selectedIcon: Icon(Icons.biotech_rounded),
                            label: '原图解析',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.tune_outlined),
                            selectedIcon: Icon(Icons.tune_rounded),
                            label: '模型模板',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.cloud_sync_outlined),
                            selectedIcon: Icon(Icons.cloud_sync_rounded),
                            label: '同步',
                          ),
                        ],
                      ),
              ),
              if (_draggingOver)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: StyleLoomTheme.accent.withValues(alpha: 0.2),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: StyleLoomTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: StyleLoomTheme.accent,
                            width: 2,
                          ),
                        ),
                        child: const Text(
                          '松开鼠标即可在 Spell Inspector 中解析原图 / ComfyUI JSON',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
        return SnippetsPage(controller: ctrl);
      case 2:
        return SpellInspectorPage(controller: ctrl);
      case 3:
        return SchemasPage(controller: ctrl);
      case 4:
        return SyncPage(controller: ctrl);
      default:
        return WaterfallPage(
          controller: ctrl,
          isDesktop: isDesktop,
          onOpenRecipe: ctrl.selectRecipe,
        );
    }
  }
}

class _DesktopLeftSidebar extends StatelessWidget {
  const _DesktopLeftSidebar({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final platforms = controller.allPlatforms;
    return Material(
      color: StyleLoomTheme.surface,
      child: SizedBox(
        width: 230,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: StyleLoomTheme.border),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: StyleLoomTheme.accent,
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'StyleLoom',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '画风织机 · 配方图库',
                        style: TextStyle(
                          fontSize: 11,
                          color: StyleLoomTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  _NavTile(
                    icon: Icons.auto_awesome_mosaic_rounded,
                    label: '画师串瀑布流',
                    selected: controller.activeNavIndex == 0,
                    onTap: () => controller.setNavIndex(0),
                  ),
                  _NavTile(
                    icon: Icons.extension_rounded,
                    label: '提示词预设片段',
                    selected: controller.activeNavIndex == 1,
                    onTap: () => controller.setNavIndex(1),
                  ),
                  _NavTile(
                    icon: Icons.biotech_rounded,
                    label: '原图 / JSON 解析器',
                    selected: controller.activeNavIndex == 2,
                    onTap: () => controller.setNavIndex(2),
                  ),
                  _NavTile(
                    icon: Icons.tune_rounded,
                    label: '平台与模型模板',
                    selected: controller.activeNavIndex == 3,
                    onTap: () => controller.setNavIndex(3),
                  ),
                  _NavTile(
                    icon: Icons.cloud_sync_rounded,
                    label: '同步与 .slpack',
                    selected: controller.activeNavIndex == 4,
                    onTap: () => controller.setNavIndex(4),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (controller.activeNavIndex == 0)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(10),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        '按生图平台 / 模型筛选',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: StyleLoomTheme.textSecondary,
                        ),
                      ),
                    ),
                    _FilterTile(
                      label: '全部平台与模型',
                      selected:
                          controller.filterPlatform == null &&
                          controller.filterSchemaId == null,
                      onTap: () => controller.updateFilters(
                        clearPlatform: true,
                        clearSchema: true,
                      ),
                    ),
                    for (final plat in platforms) ...[
                      _FilterTile(
                        label: plat,
                        selected:
                            controller.filterPlatform == plat &&
                            controller.filterSchemaId == null,
                        bold: true,
                        onTap: () => controller.updateFilters(
                          platform: plat,
                          clearSchema: true,
                        ),
                      ),
                      ...controller.schemas
                          .where((s) => s.platform == plat)
                          .map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: _FilterTile(
                                label: s.modelName,
                                selected: controller.filterSchemaId == s.id,
                                onTap: () => controller.updateFilters(
                                  platform: plat,
                                  schemaId: s.id,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: StyleLoomTheme.accentSoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(
        icon,
        size: 18,
        color: selected ? StyleLoomTheme.accent : StyleLoomTheme.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: StyleLoomTheme.textPrimary,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.bold = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? StyleLoomTheme.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected || bold ? FontWeight.w700 : FontWeight.normal,
            color: selected
                ? StyleLoomTheme.textPrimary
                : StyleLoomTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
