import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../bridge/core_client.dart';
import '../../models/core_models.dart';
import '../../theme/app_theme.dart';
import 'copy_helpers.dart';
import 'snippet_picker_dialog.dart';

typedef _CapsuleDrag = ({Object editor, String id});

class PromptCapsuleEditor extends StatefulWidget {
  const PromptCapsuleEditor({
    super.key,
    required this.label,
    required this.client,
    required this.nodes,
    required this.rawText,
    required this.modelSyntax,
    required this.availableSnippets,
    required this.onChanged,
    this.allowSnippetImport = true,
  });

  final String label;
  final StyleLoomClient client;
  final List<PromptNode> nodes;
  final String rawText;
  final PromptSyntax modelSyntax;
  final List<PromptSnippet> availableSnippets;
  final void Function(List<PromptNode> nodes, String rawText) onChanged;
  final bool allowSnippetImport;

  @override
  State<PromptCapsuleEditor> createState() => _PromptCapsuleEditorState();
}

class _PromptCapsuleEditorState extends State<PromptCapsuleEditor> {
  bool _rawMode = false;
  late TextEditingController _rawController;
  final TextEditingController _addTagController = TextEditingController();
  bool _busy = false;
  bool _adding = false;
  int _revision = 0;
  late List<PromptNode> _nodes;
  late final Future<void> _initialParse;

  /// 当前锁定显示浮窗的胶囊 ID（点击切换）；桌面悬停也可临时唤出
  String? _pinnedNodeId;
  String? _hoveredNodeId;

  @override
  void initState() {
    super.initState();
    _rawController = TextEditingController(text: widget.rawText);
    _nodes = List.of(widget.nodes);
    _initialParse = _parseInitialRaw();
  }

  @override
  void didUpdateWidget(covariant PromptCapsuleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes != widget.nodes) {
      _nodes = List.of(widget.nodes);
      final ids = _nodes.map((n) => n.id).toSet();
      if (_pinnedNodeId != null && !ids.contains(_pinnedNodeId)) {
        _pinnedNodeId = null;
      }
      if (_hoveredNodeId != null && !ids.contains(_hoveredNodeId)) {
        _hoveredNodeId = null;
      }
    }
    if (oldWidget.rawText != widget.rawText &&
        _rawController.text != widget.rawText &&
        !_rawMode) {
      _rawController.text = widget.rawText;
    }
  }

  Future<void> _parseInitialRaw() async {
    if (_nodes.isNotEmpty || widget.rawText.trim().isEmpty) return;
    final revision = _revision;
    try {
      final parsed = await widget.client.parseRawToNodes(widget.rawText);
      if (!mounted || revision != _revision) return;
      setState(() => _nodes = parsed);
      widget.onChanged(parsed, _rawController.text);
    } catch (e) {
      if (!mounted || revision != _revision) return;
      setState(() => _rawMode = true);
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('提示词操作失败：$e')));
  }

  @override
  void dispose() {
    _rawController.dispose();
    _addTagController.dispose();
    super.dispose();
  }

  Future<void> _syncRawFromNodes(List<PromptNode> nextNodes) async {
    if (!mounted) return;
    final revision = ++_revision;
    setState(() => _nodes = nextNodes);
    if (nextNodes.isEmpty) _rawController.clear();
    widget.onChanged(nextNodes, '');
    try {
      final nextRaw = await widget.client.nodesToRaw(
        nextNodes,
        widget.modelSyntax,
      );
      if (!mounted || revision != _revision) return;
      _rawController.text = nextRaw;
      widget.onChanged(nextNodes, nextRaw);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _toggleMode(bool toRaw) async {
    if (toRaw == _rawMode || _busy) return;
    setState(() {
      _busy = true;
      _pinnedNodeId = null;
      _hoveredNodeId = null;
    });
    final revision = ++_revision;
    try {
      if (toRaw) {
        final raw = _nodes.isEmpty
            ? _rawController.text
            : await widget.client.nodesToRaw(_nodes, widget.modelSyntax);
        if (!mounted || revision != _revision) return;
        _rawController.text = raw;
        widget.onChanged(_nodes, raw);
      } else {
        final raw = _rawController.text;
        final parsed = await widget.client.parseRawToNodes(raw);
        if (!mounted || revision != _revision) return;
        _nodes = parsed;
        widget.onChanged(parsed, raw);
      }
      if (mounted) setState(() => _rawMode = toRaw);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importSnippets() async {
    setState(() {
      _pinnedNodeId = null;
      _hoveredNodeId = null;
    });
    final chosen = await showDialog<List<PromptSnippet>>(
      context: context,
      builder: (_) => SnippetPickerDialog(snippets: widget.availableSnippets),
    );
    await _initialParse;
    if (!mounted || chosen == null || chosen.isEmpty) return;

    final revision = _revision;
    List<PromptNode> baseNodes = List.of(_nodes);
    if (_rawMode) {
      try {
        baseNodes = await widget.client.parseRawToNodes(_rawController.text);
      } catch (e) {
        _showError(e);
        return;
      }
      if (!mounted || revision != _revision) return;
    }
    final nowMs = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < chosen.length; i++) {
      final sn = chosen[i];
      baseNodes.add(
        SnippetRefNode(
          id: 'ref_${nowMs}_$i',
          snippetId: sn.id,
          fallbackName: sn.name,
          fallbackRaw: sn.rawText,
        ),
      );
    }
    await _syncRawFromNodes(baseNodes);
  }

  Future<void> _addInlineTokens() async {
    if (_adding || _busy) return;
    final input = _addTagController.text.trim();
    if (input.isEmpty) return;
    _adding = true;
    try {
      await _initialParse;
      if (!mounted || _rawMode) return;
      final parsed = await widget.client.parseRawToNodes(input);
      if (!mounted || _rawMode || parsed.isEmpty) return;
      if (_addTagController.text.trim() == input) _addTagController.clear();
      await _syncRawFromNodes([..._nodes, ...parsed]);
    } catch (e) {
      _showError(e);
    } finally {
      _adding = false;
    }
  }

  Future<void> _copyPrompt(TargetSyntax target) async {
    try {
      await _initialParse;
      if (!mounted) return;
      List<PromptNode> curNodes = _nodes;
      if (_rawMode) {
        curNodes = await widget.client.parseRawToNodes(_rawController.text);
      }
      final rendered = await widget.client.renderCopyNodes(
        nodes: curNodes,
        modelSyntax: widget.modelSyntax,
        targetSyntax: target,
      );
      if (!mounted) return;
      await copyTextWithFeedback(context, rendered, widget.label);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _reorder(String sourceId, String targetId) async {
    final fromIdx = _nodes.indexWhere((node) => node.id == sourceId);
    final toIdx = _nodes.indexWhere((node) => node.id == targetId);
    if (fromIdx < 0 || toIdx < 0 || fromIdx == toIdx) return;
    final next = List<PromptNode>.of(_nodes);
    final moved = next.removeAt(fromIdx);
    next.insert(toIdx, moved);
    await _syncRawFromNodes(next);
  }

  Future<void> _adjustWeight(int index, double delta) async {
    final next = List<PromptNode>.of(_nodes);
    final cur = next[index];
    final nextW = ((cur.weight + delta) * 100).round() / 100;
    final clamped = nextW.clamp(0.1, 3.0);
    next[index] = cur.copyWithState(weight: clamped);
    await _syncRawFromNodes(next);
  }

  Future<void> _resetWeight(int index) async {
    final next = List<PromptNode>.of(_nodes);
    next[index] = next[index].copyWithState(weight: 1.0);
    await _syncRawFromNodes(next);
  }

  Future<void> _toggleMute(int index) async {
    final next = List<PromptNode>.of(_nodes);
    final cur = next[index];
    next[index] = cur.copyWithState(enabled: !cur.enabled);
    await _syncRawFromNodes(next);
  }

  Future<void> _removeAt(int index) async {
    final removedId = _nodes[index].id;
    final next = List<PromptNode>.of(_nodes)..removeAt(index);
    if (_pinnedNodeId == removedId) _pinnedNodeId = null;
    if (_hoveredNodeId == removedId) _hoveredNodeId = null;
    await _syncRawFromNodes(next);
  }

  Future<void> _ungroupSnippet(SnippetRefNode node) async {
    final revision = _revision;
    if (_pinnedNodeId == node.id) _pinnedNodeId = null;
    if (_hoveredNodeId == node.id) _hoveredNodeId = null;
    try {
      final next = await widget.client.ungroupSnippetNode(
        nodes: _nodes,
        nodeId: node.id,
      );
      if (!mounted || revision != _revision) return;
      await _syncRawFromNodes(next);
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    final activeId = _pinnedNodeId ?? _hoveredNodeId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: StyleLoomTheme.serifStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: c.trough,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ModePillBtn(
                        label: '胶囊',
                        selected: !_rawMode,
                        onTap: _busy ? null : () => _toggleMode(false),
                      ),
                      _ModePillBtn(
                        label: '源码',
                        selected: _rawMode,
                        onTap: _busy ? null : () => _toggleMode(true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.allowSnippetImport)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _importSnippets,
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: c.celadonSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.extension_rounded,
                            size: 13,
                            color: c.celadon,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '织入积木',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: c.celadon,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SyntaxCopyButtons(
                  label: '',
                  compact: true,
                  onCopy: _copyPrompt,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.trough,
            borderRadius: BorderRadius.circular(16),
          ),
          child: _rawMode
              ? TextField(
                  controller: _rawController,
                  maxLines: 6,
                  minLines: 4,
                  style: StyleLoomTheme.monoStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: c.ink,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.surface,
                    hintText: '直接粘贴或手写英文逗号分隔的提示词，切回胶囊模式自动解析…',
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  onChanged: (v) {
                    ++_revision;
                    _nodes = [];
                    widget.onChanged([], v);
                  },
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_nodes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          '暂无词条 — 在下方输入添加，或点击右上角「织入积木」',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_nodes.length, (idx) {
                          final node = _nodes[idx];
                          final isOpen = activeId == node.id;
                          return DragTarget<_CapsuleDrag>(
                            key: ValueKey(node.id),
                            onWillAcceptWithDetails: (details) =>
                                details.data.editor == this &&
                                details.data.id != node.id,
                            onAcceptWithDetails: (details) =>
                                _reorder(details.data.id, node.id),
                            builder: (context, candidates, _) {
                              final isDropTarget = candidates.isNotEmpty;
                              return Draggable<_CapsuleDrag>(
                                data: (editor: this, id: node.id),
                                onDragStarted: () {
                                  setState(() {
                                    _pinnedNodeId = null;
                                    _hoveredNodeId = null;
                                  });
                                },
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: Opacity(
                                    opacity: 0.92,
                                    child: _StaticCapsuleLook(
                                      node: node,
                                      isOpen: true,
                                      isDropTarget: false,
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.32,
                                  child: _StaticCapsuleLook(
                                    node: node,
                                    isOpen: false,
                                    isDropTarget: false,
                                  ),
                                ),
                                child: _EditorialCapsuleHost(
                                  node: node,
                                  isOpen: isOpen,
                                  isDropTarget: isDropTarget,
                                  onTap: () {
                                    setState(() {
                                      _pinnedNodeId = _pinnedNodeId == node.id
                                          ? null
                                          : node.id;
                                    });
                                  },
                                  onHoverChanged: (hovering) {
                                    if (!mounted) return;
                                    if (hovering) {
                                      if (_hoveredNodeId != node.id) {
                                        setState(
                                          () => _hoveredNodeId = node.id,
                                        );
                                      }
                                    } else if (_hoveredNodeId == node.id) {
                                      setState(() => _hoveredNodeId = null);
                                    }
                                  },
                                  onDismissPinned: () {
                                    if (!mounted) return;
                                    if (_pinnedNodeId == node.id) {
                                      setState(() => _pinnedNodeId = null);
                                    }
                                  },
                                  onAdjustWeight: (d) => _adjustWeight(idx, d),
                                  onResetWeight: () => _resetWeight(idx),
                                  onToggleMute: () => _toggleMute(idx),
                                  onRemove: () => _removeAt(idx),
                                  onUngroup: node is SnippetRefNode
                                      ? () => _ungroupSnippet(node)
                                      : null,
                                ),
                              );
                            },
                          );
                        }),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _addTagController,
                            style: TextStyle(fontSize: 12.5, color: c.ink),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: c.surface,
                              hintText:
                                  '输入新词条（如 1girl, 1.15::artist:ask::）回车织入…',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                            ),
                            onSubmitted: (_) => _addInlineTokens(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: '添加词条',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _addInlineTokens,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.add_rounded,
                                size: 18,
                                color: c.accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ModePillBtn extends StatelessWidget {
  const _ModePillBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.shadowColor.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? c.ink : c.muted,
          ),
        ),
      ),
    );
  }
}

/// 纯静态零噪音字牌外观（仅显示词条文字 + 右上角上标权重，无任何常驻图标按钮）
class _StaticCapsuleLook extends StatelessWidget {
  const _StaticCapsuleLook({
    required this.node,
    required this.isOpen,
    required this.isDropTarget,
  });

  final PromptNode node;
  final bool isOpen;
  final bool isDropTarget;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    final isSnippet = node is SnippetRefNode;
    final muted = !node.enabled;
    final hasWeight = (node.weight - 1.0).abs() >= 0.005;

    final bgColor = isSnippet ? c.celadonSoft : c.surface;
    final textColor = isSnippet ? c.celadon : c.ink;
    final borderColor = isDropTarget
        ? c.warn
        : (isOpen
              ? (isSnippet ? c.celadon : c.accent)
              : (isSnippet
                    ? c.celadon.withValues(alpha: 0.22)
                    : Colors.transparent));

    final title = switch (node) {
      TokenNode t => t.text,
      SnippetRefNode s => '🧩 ${s.fallbackName}',
    };

    return Opacity(
      opacity: muted ? 0.44 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: isDropTarget || isOpen ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (!isSnippet)
              BoxShadow(
                color: c.shadowColor.withValues(alpha: c.isNight ? 0.2 : 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: isSnippet ? FontWeight.w600 : FontWeight.w400,
                    color: textColor,
                    decoration: muted ? TextDecoration.lineThrough : null,
                    decorationColor: textColor,
                  ),
                ),
              ),
            ),
            if (hasWeight) ...[
              const SizedBox(width: 4),
              Transform.translate(
                offset: const Offset(0, -2),
                child: Text(
                  node.weight.toStringAsFixed(2),
                  style: StyleLoomTheme.monoStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: isSnippet ? c.celadon : c.accent,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 带 OverlayPortal 悬停/点击微浮窗的胶囊宿主
class _EditorialCapsuleHost extends StatefulWidget {
  const _EditorialCapsuleHost({
    required this.node,
    required this.isOpen,
    required this.isDropTarget,
    required this.onTap,
    required this.onHoverChanged,
    required this.onDismissPinned,
    required this.onAdjustWeight,
    required this.onResetWeight,
    required this.onToggleMute,
    required this.onRemove,
    this.onUngroup,
  });

  final PromptNode node;
  final bool isOpen;
  final bool isDropTarget;
  final VoidCallback onTap;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onDismissPinned;
  final void Function(double delta) onAdjustWeight;
  final VoidCallback onResetWeight;
  final VoidCallback onToggleMute;
  final VoidCallback onRemove;
  final VoidCallback? onUngroup;

  @override
  State<_EditorialCapsuleHost> createState() => _EditorialCapsuleHostState();
}

class _EditorialCapsuleHostState extends State<_EditorialCapsuleHost> {
  final OverlayPortalController _portalCtrl = OverlayPortalController();
  bool _hoverPill = false;
  bool _hoverPopover = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _syncPortal();
  }

  @override
  void didUpdateWidget(covariant _EditorialCapsuleHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOpen != widget.isOpen) {
      _syncPortal();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _syncPortal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isOpen) {
        if (!_portalCtrl.isShowing) _portalCtrl.show();
      } else {
        if (_portalCtrl.isShowing) _portalCtrl.hide();
      }
    });
  }

  void _scheduleHoverSync() {
    _hideTimer?.cancel();
    if (_hoverPill || _hoverPopover) {
      widget.onHoverChanged(true);
    } else {
      _hideTimer = Timer(const Duration(milliseconds: 90), () {
        if (mounted && !_hoverPill && !_hoverPopover) {
          widget.onHoverChanged(false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portalCtrl,
      overlayChildBuilder: _buildPopover,
      child: TapRegion(
        groupId: widget.node.id,
        onTapOutside: (_) {
          if (widget.isOpen) widget.onDismissPinned();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            _hoverPill = true;
            _scheduleHoverSync();
          },
          onExit: (_) {
            _hoverPill = false;
            _scheduleHoverSync();
          },
          child: GestureDetector(
            onTap: widget.onTap,
            child: _StaticCapsuleLook(
              node: widget.node,
              isOpen: widget.isOpen,
              isDropTarget: widget.isDropTarget,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopover(BuildContext context, OverlayChildLayoutInfo info) {
    final c = EditorialColors.of(context);
    final muted = !widget.node.enabled;
    final hasUngroup = widget.onUngroup != null;

    final anchor = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    return CustomSingleChildLayout(
      delegate: _CapsuleMenuLayout(anchor),
      child: TapRegion(
        groupId: widget.node.id,
        child: MouseRegion(
          onEnter: (_) {
            _hoverPopover = true;
            _scheduleHoverSync();
          },
          onExit: (_) {
            _hoverPopover = false;
            _scheduleHoverSync();
          },
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceGlass,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.hairline),
                    boxShadow: c.modalShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PopoverIconBtn(
                        label: '−',
                        tooltip: '权重 -0.05',
                        onTap: () => widget.onAdjustWeight(-0.05),
                      ),
                      Tooltip(
                        message: '点击重置权重为 1.00',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: widget.onResetWeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3,
                            ),
                            child: Text(
                              widget.node.weight.toStringAsFixed(2),
                              style: StyleLoomTheme.monoStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: c.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _PopoverIconBtn(
                        label: '+',
                        tooltip: '权重 +0.05',
                        onTap: () => widget.onAdjustWeight(0.05),
                      ),
                      _PopDivider(color: c.hairline),
                      _PopoverIconBtn(
                        label: muted ? '恢复' : '静音',
                        tooltip: muted ? '取消屏蔽' : '临时屏蔽（复制时跳过）',
                        color: muted ? c.warn : c.ink,
                        onTap: widget.onToggleMute,
                      ),
                      if (hasUngroup) ...[
                        const SizedBox(width: 2),
                        _PopoverIconBtn(
                          label: '打散',
                          tooltip: '将预设积木打散为独立词条',
                          color: c.celadon,
                          onTap: widget.onUngroup!,
                        ),
                      ],
                      _PopDivider(color: c.hairline),
                      _PopoverIconBtn(
                        label: '移除',
                        tooltip: '移除',
                        color: c.accent,
                        onTap: widget.onRemove,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsuleMenuLayout extends SingleChildLayoutDelegate {
  const _CapsuleMenuLayout(this.anchor);
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: anchor.center,
    verticalOffset: anchor.height / 2 + 6,
    preferBelow: false,
  );

  @override
  bool shouldRelayout(_CapsuleMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

class _PopDivider extends StatelessWidget {
  const _PopDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: color,
    );
  }
}

class _PopoverIconBtn extends StatelessWidget {
  const _PopoverIconBtn({
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color ?? c.ink,
            ),
          ),
        ),
      ),
    );
  }
}
