import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/copy_helpers.dart';
import '../widgets/prompt_capsule_editor.dart';

class SnippetsPage extends StatefulWidget {
  const SnippetsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends State<SnippetsPage> {
  String _query = '';
  String? _category;

  Future<void> _openEditor([PromptSnippet? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final catCtrl =
        TextEditingController(text: (existing?.categories ?? []).join(', '));
    final modelCtrl = TextEditingController(text: existing?.modelHint ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    var nodes = List<PromptNode>.of(existing?.nodes ?? []);
    var raw = existing?.rawText ?? '';
    if (nodes.isEmpty && raw.trim().isNotEmpty) {
      nodes = await widget.controller.client.parseRawToNodes(raw);
    }

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? '新建提示词预设（片段）' : '编辑提示词预设'),
          content: SizedBox(
            width: 640,
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
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
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
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('保存片段'),
            ),
          ],
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
            s.categories.any((c) => c.toLowerCase().contains(q));
      }
      return true;
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: StyleLoomTheme.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('提示词预设（独立片段积木库）',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text(
                          '不强分正负面，可在任意画师串的正/负面框中多选导入为 [🧩 预设块] 并支持一键打散。',
                          style: TextStyle(
                              fontSize: 12,
                              color: StyleLoomTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建预设片段'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText: '搜索提示词片段名称、内容或分类…',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              if (allCats.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('全部'),
                          selected: _category == null,
                          onSelected: (_) => setState(() => _category = null),
                        ),
                      ),
                      ...allCats.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(c),
                            selected: _category == c,
                            onSelected: (_) => setState(
                              () => _category = _category == c ? null : c,
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
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.extension_rounded,
                          size: 42, color: StyleLoomTheme.teal),
                      const SizedBox(height: 10),
                      const Text('暂无提示词预设片段',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      const Text(
                        '例如新建「1girl, beautiful」或「huge breasts」，即可导入画师串里按顺序拼装。',
                        style: TextStyle(
                            fontSize: 12, color: StyleLoomTheme.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _openEditor(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('立即新建'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final sn = filtered[idx];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text('🧩 ${sn.name}',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                      if (sn.modelHint.isNotEmpty)
                                        Chip(
                                          label: Text(sn.modelHint,
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ...sn.categories.map(
                                        (c) => Chip(
                                          label: Text('#$c',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: StyleLoomTheme.teal)),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SyntaxCopyButtons(
                                  label: '片段',
                                  compact: true,
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
                                          context, out, sn.name);
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: '编辑',
                                  icon: const Icon(Icons.edit_rounded, size: 18),
                                  onPressed: () => _openEditor(sn),
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 18),
                                  onPressed: () =>
                                      runActionWithFeedback(context, () => widget.controller.deleteSnippet(sn.id)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              sn.rawText,
                              style: const TextStyle(
                                fontSize: 13,
                                color: StyleLoomTheme.textSecondary,
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
    );
  }
}
