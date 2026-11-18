import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../theme/app_theme.dart';

class SnippetPickerDialog extends StatefulWidget {
  const SnippetPickerDialog({super.key, required this.snippets});

  final List<PromptSnippet> snippets;

  @override
  State<SnippetPickerDialog> createState() => _SnippetPickerDialogState();
}

class _SnippetPickerDialogState extends State<SnippetPickerDialog> {
  String _query = '';
  String? _category;
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final allCats = <String>{};
    for (final s in widget.snippets) {
      allCats.addAll(s.categories);
    }
    final filtered = widget.snippets.where((s) {
      if (_category != null && !s.categories.contains(_category)) return false;
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        return s.name.toLowerCase().contains(q) ||
            s.rawText.toLowerCase().contains(q) ||
            s.categories.any((c) => c.toLowerCase().contains(q));
      }
      return true;
    }).toList();

    return AlertDialog(
      title: const Text('导入提示词预设片段'),
      content: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                hintText: '搜索预设名、词条或分类…',
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
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无匹配的提示词预设\n请先前往「提示词预设」页新建常用片段',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: StyleLoomTheme.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, idx) {
                        final sn = filtered[idx];
                        final checked = _selectedIds.contains(sn.id);
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() {
                            if (checked) {
                              _selectedIds.remove(sn.id);
                            } else {
                              _selectedIds.add(sn.id);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: checked
                                  ? StyleLoomTheme.accentSoft
                                  : StyleLoomTheme.surfaceHigh,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: checked
                                    ? StyleLoomTheme.accent
                                    : StyleLoomTheme.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: checked,
                                  onChanged: (_) => setState(() {
                                    if (checked) {
                                      _selectedIds.remove(sn.id);
                                    } else {
                                      _selectedIds.add(sn.id);
                                    }
                                  }),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '🧩 ${sn.name}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(width: 8),
                                          ...sn.categories.take(3).map(
                                                (c) => Container(
                                                  margin: const EdgeInsets.only(
                                                      right: 4),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: StyleLoomTheme.bg,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    c,
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        color: StyleLoomTheme
                                                            .textSecondary),
                                                  ),
                                                ),
                                              ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        sn.rawText,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: StyleLoomTheme.textSecondary,
                                        ),
                                      ),
                                    ],
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  final chosen = widget.snippets
                      .where((s) => _selectedIds.contains(s.id))
                      .toList();
                  Navigator.of(context).pop(chosen);
                },
          child: Text('导入已选 (${_selectedIds.length})'),
        ),
      ],
    );
  }
}
