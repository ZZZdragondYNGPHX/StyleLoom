import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../theme/app_theme.dart';

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
    final c = EditorialColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          Tooltip(
            message: '复制$label',
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => runActionWithFeedback(
                context,
                () => onCopy(TargetSyntax.asIs),
              ),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.trough,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded, size: 13, color: c.ink),
                    const SizedBox(width: 4),
                    Text(
                      '复制',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => runActionWithFeedback(
              context,
              () => onCopy(TargetSyntax.asIs),
            ),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 13, color: c.accent),
                  const SizedBox(width: 5),
                  Text(
                    label.isEmpty ? '复制' : '复制$label',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(width: 4),
        PopupMenuButton<TargetSyntax>(
          tooltip: '转换目标权重语法后复制',
          onSelected: (target) =>
              runActionWithFeedback(context, () => onCopy(target)),
          padding: EdgeInsets.zero,
          itemBuilder: (_) => TargetSyntax.values
              .map(
                (t) => PopupMenuItem<TargetSyntax>(
                  value: t,
                  child: Text(t.label, style: const TextStyle(fontSize: 12.5)),
                ),
              )
              .toList(),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: c.trough,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz_rounded, size: 13, color: c.ink),
                const SizedBox(width: 3),
                Text(
                  '转语法',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
                Icon(Icons.arrow_drop_down_rounded, size: 15, color: c.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
