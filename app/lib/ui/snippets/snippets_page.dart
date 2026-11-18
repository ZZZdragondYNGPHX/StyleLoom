import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/copy_helpers.dart';
import '../widgets/prompt_capsule_editor.dart';

class SnippetsPage extends StatefulWidget {
  const SnippetsPage({
    super.key,
    required this.controller,
    this.isDesktop = true,
  });

  final AppController controller;
  final bool isDesktop;

  @override
  State<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends State<SnippetsPage> {
  String _query = '';
  String? _category;

  Future<void> _openEditor([PromptSnippet? existing]) async {
    final c = EditorialColors.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final catCtrl = TextEditingController(
      text: (existing?.categories ?? []).join(', '),
    );
    final modelCtrl = TextEditingController(text: existing?.modelHint ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    var nodes = List<PromptNode>.of(existing?.nodes ?? []);
    var raw = existing?.rawText ?? '';
    if (nodes.isEmpty && raw.trim().isNotEmpty) {
      nodes = await widget.controller.client.parseRawToNodes(raw);
    }

    if (!mounted) return;
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: c.hairline),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          existing == null ? '新建提示词预设（片段）' : '编辑提示词预设',
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
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: '预设片段名称',
                              hintText: '例如：预设A-通用美少女 / 高画质起手 / 通用负面防崩',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: catCtrl,
                                  decoration: const InputDecoration(
                                    labelText: '分类标签（英文逗号分隔）',
                                    hintText: '人物, 身材, 光影, 负面',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: modelCtrl,
                                  decoration: const InputDecoration(
                                    labelText: '适用模型备注（可选）',
                                    hintText: '例如：全平台 / NAI V5 / Illustrious',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          PromptCapsuleEditor(
                            label: '片段内容',
                            client: widget.controller.client,
                            nodes: nodes,
                            rawText: raw,
                            modelSyntax: PromptSyntax.sdParens,
                            availableSnippets: widget.controller.snippets
                                .where((s) => s.id != existing?.id)
                                .toList(),
                            allowSnippetImport: false,
                            onChanged: (nextNodes, nextRaw) {
                              setDlg(() {
                                nodes = nextNodes;
                                raw = nextRaw;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: noteCtrl,
                            decoration: const InputDecoration(labelText: '备注'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                                  final cats = catCtrl.text
                                      .split(RegExp(r'[,，]'))
                                      .map((s) => s.trim())
                                      .where((s) => s.isNotEmpty)
                                      .toList();
                                  await widget.controller.saveSnippet(
                                    PromptSnippet(
                                      id: existing?.id ?? '',
                                      name: nameCtrl.text.trim().isEmpty
                                          ? '未命名片段'
                                          : nameCtrl.text.trim(),
                                      categories: cats,
                                      modelHint: modelCtrl.text.trim(),
                                      nodes: nodes,
                                      rawText: raw,
                                      note: noteCtrl.text.trim(),
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
                        child: const Text('保存片段'),
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
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存提示词预设片段')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    final allCats = <String>{};
    for (final s in widget.controller.snippets) {
      allCats.addAll(s.categories);
    }
    final filtered = widget.controller.snippets.where((s) {
      if (_category != null && !s.categories.contains(_category)) return false;
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        return s.name.toLowerCase().contains(q) ||
            s.rawText.toLowerCase().contains(q) ||
            s.categories.any((cat) => cat.toLowerCase().contains(q));
      }
      return true;
    }).toList();

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '词条积木库 · Prompt Snippets',
                                style: StyleLoomTheme.serifStyle(
                                  fontSize: widget.isDesktop ? 26 : 21,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '不强分正负面，可在任意画师串正/负面框中多选导入为 [🧩 预设块] 并一键打散。',
                                style: TextStyle(fontSize: 13, color: c.muted),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.celadon,
                            foregroundColor: const Color(0xFFFFFEFA),
                          ),
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('新建预设片段'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: widget.isDesktop ? 320 : double.infinity,
                          child: TextField(
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: c.surface,
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 18,
                              ),
                              hintText: '搜索积木名称、词条或分类…',
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        if (allCats.isNotEmpty)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _FilterPill(
                                  label:
                                      '全部 (${widget.controller.snippets.length})',
                                  selected: _category == null,
                                  onTap: () => setState(() => _category = null),
                                ),
                                ...allCats.map(
                                  (cat) => _FilterPill(
                                    label: '#$cat',
                                    selected: _category == cat,
                                    onTap: () => setState(
                                      () => _category = _category == cat
                                          ? null
                                          : cat,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
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
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: c.celadonSoft,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.extension_rounded,
                                  size: 24,
                                  color: c.celadon,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '暂无提示词预设片段',
                                style: StyleLoomTheme.serifStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '例如新建「1girl, beautiful」或「光影氛围组」，即可导入画师串里按顺序编织拼装。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.muted,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: c.celadon,
                                  foregroundColor: const Color(0xFFFFFEFA),
                                ),
                                onPressed: () => _openEditor(),
                                icon: const Icon(Icons.add_rounded, size: 17),
                                label: const Text('立即新建'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (_, box) {
                          final colCount = box.maxWidth >= 1100
                              ? 3
                              : (box.maxWidth >= 680 ? 2 : 1);
                          return GridView.builder(
                            padding: EdgeInsets.only(
                              top: 20,
                              bottom: widget.isDesktop ? 40 : 96,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: colCount,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  mainAxisExtent: 206,
                                ),
                            itemCount: filtered.length,
                            itemBuilder: (_, idx) {
                              final sn = filtered[idx];
                              return _SnippetEditorialCard(
                                snippet: sn,
                                onEdit: () => _openEditor(sn),
                                onDelete: () => runActionWithFeedback(
                                  context,
                                  () => widget.controller.deleteSnippet(sn.id),
                                ),
                                onCopy: (target) async {
                                  final nodes = sn.nodes.isNotEmpty
                                      ? sn.nodes
                                      : await widget.controller.client
                                            .parseRawToNodes(sn.rawText);
                                  final out = await widget.controller.client
                                      .renderCopyNodes(
                                        nodes: nodes,
                                        modelSyntax: PromptSyntax.sdParens,
                                        targetSyntax: target,
                                      );
                                  if (context.mounted) {
                                    await copyTextWithFeedback(
                                      context,
                                      out,
                                      sn.name,
                                    );
                                  }
                                },
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({
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
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? c.celadon : c.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected ? null : c.cardShadow,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? const Color(0xFFFFFEFA) : c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SnippetEditorialCard extends StatelessWidget {
  const _SnippetEditorialCard({
    required this.snippet,
    required this.onEdit,
    required this.onDelete,
    required this.onCopy,
  });

  final PromptSnippet snippet;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function(TargetSyntax target) onCopy;

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
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.celadonSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '🧩 ${snippet.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.celadon,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '编辑',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.edit_rounded, size: 17, color: c.muted),
                onPressed: onEdit,
              ),
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
          if (snippet.modelHint.isNotEmpty ||
              snippet.categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (snippet.modelHint.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.trough,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      snippet.modelHint,
                      style: TextStyle(fontSize: 11, color: c.ink),
                    ),
                  ),
                ...snippet.categories.map(
                  (cat) => Text(
                    '#$cat',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.celadon,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.trough,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                snippet.rawText.isEmpty ? '（空内容）' : snippet.rawText,
                maxLines: 3,
                style: StyleLoomTheme.monoStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: c.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: SyntaxCopyButtons(
              label: '片段',
              compact: true,
              onCopy: onCopy,
            ),
          ),
        ],
      ),
    );
  }
}
