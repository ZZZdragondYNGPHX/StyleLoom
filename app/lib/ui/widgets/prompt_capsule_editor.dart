import 'package:material_ui/material_ui.dart';

import '../../bridge/core_client.dart';
import '../../models/core_models.dart';
import '../../theme/app_theme.dart';
import 'copy_helpers.dart';
import 'snippet_picker_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _rawController = TextEditingController(text: widget.rawText);
    _nodes = List.of(widget.nodes);
    _parseInitialRaw();
  }

  @override
  void didUpdateWidget(covariant PromptCapsuleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes != widget.nodes) _nodes = List.of(widget.nodes);
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
    setState(() => _busy = true);
    final revision = ++_revision;
    try {
      if (toRaw) {
        final raw = await widget.client.nodesToRaw(_nodes, widget.modelSyntax);
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
    final chosen = await showDialog<List<PromptSnippet>>(
      context: context,
      builder: (_) => SnippetPickerDialog(snippets: widget.availableSnippets),
    );
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
      final parsed = await widget.client.parseRawToNodes(input);
      if (!mounted || parsed.isEmpty) return;
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

  Future<void> _reorder(int fromIdx, int toIdx) async {
    if (fromIdx == toIdx) return;
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

  Future<void> _toggleMute(int index) async {
    final next = List<PromptNode>.of(_nodes);
    final cur = next[index];
    next[index] = cur.copyWithState(enabled: !cur.enabled);
    await _syncRawFromNodes(next);
  }

  Future<void> _removeAt(int index) async {
    final next = List<PromptNode>.of(_nodes);
    next.removeAt(index);
    await _syncRawFromNodes(next);
  }

  Future<void> _ungroupSnippet(SnippetRefNode node) async {
    final revision = _revision;
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StyleLoomTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StyleLoomTheme.border),
      ),
      child: Column(
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('胶囊', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('源码', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {_rawMode},
                    onSelectionChanged: _busy
                        ? null
                        : (s) => _toggleMode(s.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                    OutlinedButton.icon(
                      onPressed: _importSnippets,
                      icon: const Icon(Icons.extension_rounded, size: 15),
                      label: const Text(
                        '导入预设片段',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  SyntaxCopyButtons(label: widget.label, onCopy: _copyPrompt),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_rawMode)
            TextField(
              controller: _rawController,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontSize: 13, height: 1.45),
              decoration: const InputDecoration(
                hintText: '直接粘贴或手写英文逗号分隔的提示词，切回胶囊模式自动解析…',
              ),
              onChanged: (v) {
                ++_revision;
                _nodes = [];
                widget.onChanged([], v);
              },
            )
          else ...[
            if (_nodes.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: StyleLoomTheme.bg.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: StyleLoomTheme.border),
                ),
                child: const Text(
                  '暂无词条，在下方输入添加或点击右上角「导入预设片段」',
                  style: TextStyle(
                    fontSize: 12,
                    color: StyleLoomTheme.textSecondary,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(_nodes.length, (idx) {
                  final node = _nodes[idx];
                  return DragTarget<int>(
                    onWillAcceptWithDetails: (details) => details.data != idx,
                    onAcceptWithDetails: (details) =>
                        _reorder(details.data, idx),
                    builder: (context, candidates, _) {
                      final isDropTarget = candidates.isNotEmpty;
                      final pill = _CapsulePill(
                        node: node,
                        isDropTarget: isDropTarget,
                        onAdjustWeight: (d) => _adjustWeight(idx, d),
                        onToggleMute: () => _toggleMute(idx),
                        onRemove: () => _removeAt(idx),
                        onUngroup: node is SnippetRefNode
                            ? () => _ungroupSnippet(node)
                            : null,
                      );
                      return Draggable<int>(
                        data: idx,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Opacity(opacity: 0.9, child: pill),
                        ),
                        childWhenDragging: Opacity(opacity: 0.35, child: pill),
                        child: pill,
                      );
                    },
                  );
                }),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addTagController,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: '快速添加词条（如 1girl, 1.2::artist:ask::）回车确认…',
                    ),
                    onSubmitted: (_) => _addInlineTokens(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: '添加词条',
                  onPressed: _addInlineTokens,
                  icon: const Icon(Icons.add_rounded, size: 18),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CapsulePill extends StatelessWidget {
  const _CapsulePill({
    required this.node,
    required this.isDropTarget,
    required this.onAdjustWeight,
    required this.onToggleMute,
    required this.onRemove,
    this.onUngroup,
  });

  final PromptNode node;
  final bool isDropTarget;
  final void Function(double delta) onAdjustWeight;
  final VoidCallback onToggleMute;
  final VoidCallback onRemove;
  final VoidCallback? onUngroup;

  @override
  Widget build(BuildContext context) {
    final isSnippet = node is SnippetRefNode;
    final muted = !node.enabled;
    final hasWeight = (node.weight - 1.0).abs() >= 0.005;

    final baseBg = isSnippet
        ? StyleLoomTheme.teal.withValues(alpha: muted ? 0.06 : 0.16)
        : (muted ? StyleLoomTheme.bg : StyleLoomTheme.surfaceHigh);
    final borderColor = isDropTarget
        ? StyleLoomTheme.amber
        : (isSnippet
              ? StyleLoomTheme.teal.withValues(alpha: muted ? 0.3 : 0.7)
              : (hasWeight ? StyleLoomTheme.accent : StyleLoomTheme.border));

    final title = switch (node) {
      TokenNode t => t.text,
      SnippetRefNode s => '🧩 ${s.fallbackName}',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: isDropTarget ? 1.8 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.drag_indicator_rounded,
            size: 13,
            color: StyleLoomTheme.textSecondary,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSnippet ? FontWeight.w600 : FontWeight.normal,
                  color: muted
                      ? StyleLoomTheme.textSecondary
                      : StyleLoomTheme.textPrimary,
                  decoration: muted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          if (hasWeight) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: StyleLoomTheme.accentSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                node.weight.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 10,
                  color: StyleLoomTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(width: 3),
          _MiniIconBtn(
            icon: Icons.remove_rounded,
            tooltip: '权重 -0.05',
            onTap: () => onAdjustWeight(-0.05),
          ),
          _MiniIconBtn(
            icon: Icons.add_rounded,
            tooltip: '权重 +0.05',
            onTap: () => onAdjustWeight(0.05),
          ),
          _MiniIconBtn(
            icon: muted
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            tooltip: muted ? '取消屏蔽' : '临时屏蔽（复制时跳过）',
            color: muted ? StyleLoomTheme.amber : null,
            onTap: onToggleMute,
          ),
          if (onUngroup != null)
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onUngroup,
              child: Container(
                margin: const EdgeInsets.only(left: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: StyleLoomTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: StyleLoomTheme.teal.withValues(alpha: 0.6),
                  ),
                ),
                child: const Text(
                  '打散',
                  style: TextStyle(
                    fontSize: 10,
                    color: StyleLoomTheme.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          _MiniIconBtn(
            icon: Icons.close_rounded,
            tooltip: '移除',
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

class _MiniIconBtn extends StatelessWidget {
  const _MiniIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 13,
            color: color ?? StyleLoomTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
