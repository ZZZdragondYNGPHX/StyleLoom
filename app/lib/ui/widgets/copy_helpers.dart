import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../models/core_models.dart';

Future<void> runActionWithFeedback(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('操作失败：$e')));
  }
}

Future<void> copyTextWithFeedback(
  BuildContext context,
  String text,
  String label,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  final preview = text.length > 68 ? '${text.substring(0, 68)}…' : text;
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        text.isEmpty ? '$label 内容为空' : '已复制$label：$preview',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}

class SyntaxCopyButtons extends StatelessWidget {
  const SyntaxCopyButtons({
    super.key,
    required this.label,
    required this.onCopy,
    this.compact = false,
  });

  final String label;
  final Future<void> Function(TargetSyntax target) onCopy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          IconButton(
            tooltip: '复制$label',
            icon: const Icon(Icons.copy_rounded, size: 17),
            onPressed: () =>
                runActionWithFeedback(context, () => onCopy(TargetSyntax.asIs)),
            visualDensity: VisualDensity.compact,
          )
        else
          FilledButton.tonalIcon(
            onPressed: () =>
                runActionWithFeedback(context, () => onCopy(TargetSyntax.asIs)),
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: Text('复制$label', style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        PopupMenuButton<TargetSyntax>(
          tooltip: '转换目标权重语法后复制',
          onSelected: (target) =>
              runActionWithFeedback(context, () => onCopy(target)),
          padding: EdgeInsets.zero,
          itemBuilder: (_) => TargetSyntax.values
              .map(
                (t) => PopupMenuItem<TargetSyntax>(
                  value: t,
                  child: Text(t.label, style: const TextStyle(fontSize: 13)),
                ),
              )
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz_rounded, size: 15),
                SizedBox(width: 2),
                Text('转语法', style: TextStyle(fontSize: 11)),
                Icon(Icons.arrow_drop_down_rounded, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
