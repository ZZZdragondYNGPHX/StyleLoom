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
    final c = EditorialColors.of(context);
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
            s.categories.any((cat) => cat.toLowerCase().contains(q));
      }
      return true;
    }).toList();

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: c.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.celadonSoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.extension_rounded,
                      size: 17,
                      color: c.celadon,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '导入提示词预设片段',
                          style: StyleLoomTheme.serifStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        Text(
                          '多选后将作为 [🧩 预设块] 织入当前词条流，支持随时打散',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: c.muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText: '搜索预设名、词条或分类…',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              if (allCats.isNotEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _CategoryPill(
                        label: '全部',
                        selected: _category == null,
                        onTap: () => setState(() => _category = null),
                      ),
                      ...allCats.map(
                        (cat) => _CategoryPill(
                          label: cat,
                          selected: _category == cat,
                          onTap: () => setState(
                            () => _category = _category == cat ? null : cat,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          '暂无匹配的提示词预设\n请先前往「积木」页新建常用片段',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.muted, height: 1.5),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, idx) {
                          final sn = filtered[idx];
                          final checked = _selectedIds.contains(sn.id);
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() {
                              if (checked) {
                                _selectedIds.remove(sn.id);
                              } else {
                                _selectedIds.add(sn.id);
                              }
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: checked ? c.celadonSoft : c.trough,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: checked ? c.celadon : Colors.transparent,
                                  width: 1.4,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    checked
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    size: 20,
                                    color: checked ? c.celadon : c.muted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              '🧩 ${sn.name}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5,
                                                color: checked
                                                    ? c.celadon
                                                    : c.ink,
                                              ),
                                            ),
                                            ...sn.categories.take(3).map(
                                              (cat) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: c.surface,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  '#$cat',
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    color: c.muted,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          sn.rawText,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: c.muted,
                                            height: 1.4,
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
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.celadon,
                      foregroundColor: const Color(0xFFFFFEFA),
                    ),
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () {
                            final chosen = widget.snippets
                                .where((s) => _selectedIds.contains(s.id))
                                .toList();
                            Navigator.of(context).pop(chosen);
                          },
                    child: Text('织入已选 (${_selectedIds.length})'),
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

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
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
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? c.celadon : c.trough,
            borderRadius: BorderRadius.circular(999),
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
