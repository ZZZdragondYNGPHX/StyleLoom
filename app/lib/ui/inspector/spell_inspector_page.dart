import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/copy_helpers.dart';

class SpellInspectorPage extends StatefulWidget {
  const SpellInspectorPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SpellInspectorPage> createState() => _SpellInspectorPageState();
}

class _SpellInspectorPageState extends State<SpellInspectorPage> {
  Uint8List? _previewBytes;
  String? _fileName;
  InspectionResult? _result;
  String? _error;
  bool _loading = false;
  int _stageIndex = 0;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _consumePendingIfAny();
  }

  @override
  void didUpdateWidget(covariant SpellInspectorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _consumePendingIfAny();
  }

  void _consumePendingIfAny() {
    final ctrl = widget.controller;
    if (ctrl.inspectorPendingPath != null) {
      final path = ctrl.inspectorPendingPath!;
      ctrl.inspectorPendingPath = null;
      _inspectFilePath(path);
    } else if (ctrl.inspectorPendingBytes != null) {
      final bytes = ctrl.inspectorPendingBytes!;
      final name = ctrl.inspectorPendingName ?? 'dropped';
      ctrl.inspectorPendingBytes = null;
      ctrl.inspectorPendingName = null;
      _inspectBytes(bytes, name);
    }
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: '原图或 ComfyUI 工作流',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'json'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (!mounted || file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _inspectBytes(bytes, file.name);
  }

  Future<void> _inspectFilePath(String path) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _fileName = path.split(RegExp(r'[/\\]')).last;
      _stageIndex = 0;
      _result = null;
      _previewBytes = null;
    });
    try {
      final res = await widget.controller.client.inspectFile(path);
      Uint8List? imgBytes;
      final lower = path.toLowerCase();
      if (!lower.endsWith('.json')) {
        imgBytes = await XFile(path).readAsBytes();
      }
      if (mounted && request == _request) {
        setState(() {
          _result = res;
          _previewBytes = imgBytes;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _result = null;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _inspectBytes(Uint8List bytes, String name) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _fileName = name;
      _previewBytes = name.toLowerCase().endsWith('.json') ? null : bytes;
      _stageIndex = 0;
      _result = null;
    });
    try {
      final res = await widget.controller.client.inspectBytes(bytes, name);
      if (mounted && request == _request) setState(() => _result = res);
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _result = null;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _copyConverted(
    String rawPrompt,
    String label,
    TargetSyntax t,
  ) async {
    final nodes = await widget.controller.client.parseRawToNodes(rawPrompt);
    final out = await widget.controller.client.renderCopyNodes(
      nodes: nodes,
      modelSyntax: PromptSyntax.sdParens,
      targetSyntax: t,
    );
    if (mounted) {
      await copyTextWithFeedback(context, out, label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;
    final stages = res?.stages ?? [];
    final stage = stages.isNotEmpty
        ? stages[_stageIndex.clamp(0, stages.length - 1)]
        : null;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: StyleLoomTheme.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '原图与工作流解析查看器（Spell Inspector）',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '支持 PNG（标准块 + stealth_pnginfo LSB 隐写）、WebUI EXIF 与 ComfyUI JSON；纯展示与分项复制，不自动污染预设库。',
                      style: TextStyle(
                        fontSize: 12,
                        color: StyleLoomTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.file_open_rounded, size: 17),
                label: const Text('选择图片 / JSON'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (res == null && _error == null)
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.biotech_rounded,
                              size: 46,
                              color: StyleLoomTheme.teal,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '拖入或选择图片 / ComfyUI JSON',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '桌面端可直接拖拽文件到此窗口；Android 端可在相册/社交软件点击「分享到 StyleLoom」。',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: StyleLoomTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.upload_file_rounded),
                              label: const Text('打开文件解析'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Card(
                        color: Colors.redAccent.withValues(alpha: 0.14),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            '解析提示（$_fileName）：$_error',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    if (res != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_previewBytes != null)
                            Container(
                              width: 140,
                              height: 180,
                              margin: const EdgeInsets.only(right: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: StyleLoomTheme.border,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.memory(
                                _previewBytes!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _fileName ?? '解析结果',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        Chip(label: Text(res.sourceKind)),
                                        if (res.width != null &&
                                            res.height != null)
                                          Chip(
                                            label: Text(
                                              '${res.width}×${res.height}',
                                            ),
                                          ),
                                        if (res.suggestedSchemaId != null)
                                          Chip(
                                            label: Text(
                                              '推荐模板: ${widget.controller.schemaById(res.suggestedSchemaId!)?.modelName ?? res.suggestedSchemaId}',
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (_previewBytes != null &&
                                        stage != null) ...[
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final asset = await widget
                                              .controller
                                              .client
                                              .importImageBytes(_previewBytes!);
                                          if (!mounted) return;
                                          final initParams =
                                              <String, dynamic>{};
                                          if (stage.steps != null) {
                                            initParams['steps'] = stage.steps;
                                          }
                                          if (stage.cfg != null) {
                                            initParams['cfg'] = stage.cfg;
                                          }
                                          if (stage.sampler != null) {
                                            initParams['sampler'] =
                                                stage.sampler;
                                          }
                                          if (stage.scheduler != null) {
                                            initParams['scheduler'] =
                                                stage.scheduler;
                                          }
                                          if (stage.shift != null) {
                                            initParams['shift'] = stage.shift;
                                          }
                                          widget.controller.openNewRecipeDraft(
                                            schemaId:
                                                res.suggestedSchemaId ??
                                                'nai_v5',
                                            initialParams: initParams,
                                            images: [asset.toRecipeRef()],
                                            title:
                                                _fileName?.replaceAll(
                                                  RegExp(r'\.[^.]+$'),
                                                  '',
                                                ) ??
                                                '',
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.add_photo_alternate_rounded,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          '以此图作封面 + 带入参数建新卡片（不强制导入脏提示词）',
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (stages.length > 1) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: List.generate(
                            stages.length,
                            (i) => ChoiceChip(
                              label: Text(stages[i].stageName),
                              selected: _stageIndex == i,
                              onSelected: (_) =>
                                  setState(() => _stageIndex = i),
                            ),
                          ),
                        ),
                      ],
                      if (stage != null) ...[
                        const SizedBox(height: 12),
                        _InspectTextBlock(
                          title: '正面提示词 (Positive Prompt)',
                          text: stage.positivePrompt,
                          onCopySyntax: (t) =>
                              _copyConverted(stage.positivePrompt, '正面提示词', t),
                        ),
                        const SizedBox(height: 10),
                        _InspectTextBlock(
                          title: '负面提示词 (Negative Prompt / UC)',
                          text: stage.negativePrompt,
                          onCopySyntax: (t) =>
                              _copyConverted(stage.negativePrompt, '负面提示词', t),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '生成参数（点击任意项右侧复制）',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (stage.model != null)
                                      _ParamCopyChip('模型', stage.model!),
                                    if (stage.sampler != null)
                                      _ParamCopyChip('采样器', stage.sampler!),
                                    if (stage.scheduler != null)
                                      _ParamCopyChip('调度器', stage.scheduler!),
                                    if (stage.steps != null)
                                      _ParamCopyChip('Steps', '${stage.steps}'),
                                    if (stage.cfg != null)
                                      _ParamCopyChip('CFG', '${stage.cfg}'),
                                    if (stage.shift != null)
                                      _ParamCopyChip(
                                        'Flow Shift',
                                        '${stage.shift}',
                                      ),
                                    if (stage.size != null)
                                      _ParamCopyChip('尺寸', stage.size!),
                                    if (stage.seed != null)
                                      _ParamCopyChip('Seed', stage.seed!),
                                    ...stage.loras.map(
                                      (l) => _ParamCopyChip(
                                        'LoRA',
                                        '${l.name} (${l.weight})',
                                      ),
                                    ),
                                    ...stage.extraFields.map(
                                      (e) => _ParamCopyChip(e.$1, e.$2),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ExpansionTile(
                        title: const Text(
                          '原始元数据载荷',
                          style: TextStyle(fontSize: 13),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              res.rawMetadata,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _InspectTextBlock extends StatelessWidget {
  const _InspectTextBlock({
    required this.title,
    required this.text,
    required this.onCopySyntax,
  });

  final String title;
  final String text;
  final Future<void> Function(TargetSyntax target) onCopySyntax;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                SyntaxCopyButtons(
                  label: '',
                  onCopy: (t) async {
                    if (t == TargetSyntax.asIs) {
                      await copyTextWithFeedback(context, text, title);
                    } else {
                      await onCopySyntax(t);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              text.isEmpty ? '（空）' : text,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: text.isEmpty
                    ? StyleLoomTheme.textSecondary
                    : StyleLoomTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParamCopyChip extends StatelessWidget {
  const _ParamCopyChip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.copy_rounded, size: 14),
      label: Text('$label: $value', style: const TextStyle(fontSize: 12)),
      onPressed: () => copyTextWithFeedback(context, value, label),
    );
  }
}
