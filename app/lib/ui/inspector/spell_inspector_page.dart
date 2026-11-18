import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/copy_helpers.dart';

class SpellInspectorPage extends StatefulWidget {
  const SpellInspectorPage({
    super.key,
    required this.controller,
    this.isDesktop = true,
  });

  final AppController controller;
  final bool isDesktop;

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
  bool _rawExpanded = false;

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

  Future<void> _createCardFromInspection(
    InspectionResult res,
    InspectedStage stage,
  ) async {
    final asset = await widget.controller.client.importImageBytes(_previewBytes!);
    if (!mounted) return;
    final initParams = <String, dynamic>{};
    if (stage.steps != null) initParams['steps'] = stage.steps;
    if (stage.cfg != null) initParams['cfg'] = stage.cfg;
    if (stage.sampler != null) initParams['sampler'] = stage.sampler;
    if (stage.scheduler != null) initParams['scheduler'] = stage.scheduler;
    if (stage.shift != null) initParams['shift'] = stage.shift;
    widget.controller.openNewRecipeDraft(
      schemaId: res.suggestedSchemaId ?? 'nai_v5',
      initialParams: initParams,
      images: [asset.toRecipeRef()],
      title: _fileName?.replaceAll(RegExp(r'\.[^.]+$'), '') ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    final res = _result;
    final stages = res?.stages ?? [];
    final stage = stages.isNotEmpty
        ? stages[_stageIndex.clamp(0, stages.length - 1)]
        : null;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1480),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.isDesktop ? 28 : 14,
          ),
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
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '画作透镜 · Spell Inspector',
                            style: StyleLoomTheme.serifStyle(
                              fontSize: widget.isDesktop ? 26 : 21,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '纯本地读取 PNG（标准块与 stealth_pnginfo LSB 隐写）、WebUI EXIF 与 ComfyUI JSON，分项复制不污染预设库。',
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.file_open_rounded, size: 16),
                      label: const Text('选择图片 / JSON'),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(color: c.accent),
                      )
                    : (res == null && _error == null)
                    ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Container(
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
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: c.celadonSoft,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.biotech_rounded,
                                    size: 28,
                                    color: c.celadon,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '拖入或打开原图 / ComfyUI JSON',
                                  style: StyleLoomTheme.serifStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: c.ink,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '桌面端可直接拖拽 PNG / WebP / JSON 至窗口任意位置；Android 端可在相册点击「分享到 StyleLoom」。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.muted,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  onPressed: _pickFile,
                                  icon: const Icon(Icons.upload_file_rounded),
                                  label: const Text('打开文件解析'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.only(
                          top: 20,
                          bottom: widget.isDesktop ? 40 : 96,
                        ),
                        children: [
                          if (_error != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: c.accentSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '解析提示（$_fileName）：$_error',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: c.accent,
                                ),
                              ),
                            ),
                          if (res != null)
                            LayoutBuilder(
                              builder: (_, box) {
                                final split = box.maxWidth >= 820;
                                final leftCol = _buildSummaryCard(
                                  context,
                                  res,
                                  stage,
                                );
                                final rightCol = _buildDetailsColumn(
                                  context,
                                  res,
                                  stages,
                                  stage,
                                );
                                if (split) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(width: 340, child: leftCol),
                                      const SizedBox(width: 22),
                                      Expanded(child: rightCol),
                                    ],
                                  );
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    leftCol,
                                    const SizedBox(height: 16),
                                    rightCol,
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    InspectionResult res,
    InspectedStage? stage,
  ) {
    final c = EditorialColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_previewBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 280,
                color: c.museumBg,
                child: Image.memory(_previewBytes!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            _fileName ?? '解析结果',
            style: StyleLoomTheme.serifStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaPill(label: res.sourceKind, isCeladon: true),
              if (res.width != null && res.height != null)
                _MetaPill(label: '${res.width}×${res.height}'),
              if (res.suggestedSchemaId != null)
                _MetaPill(
                  label:
                      '推荐: ${widget.controller.schemaById(res.suggestedSchemaId!)?.modelName ?? res.suggestedSchemaId}',
                ),
            ],
          ),
          if (_previewBytes != null && stage != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => runActionWithFeedback(
                context,
                () => _createCardFromInspection(res, stage),
              ),
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 17),
              label: const Text('带入封面与参数建新卡'),
            ),
            const SizedBox(height: 6),
            Text(
              '仅携带图片与采样参数新建画师串，不会自动导入脏提示词。',
              style: TextStyle(fontSize: 11.5, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsColumn(
    BuildContext context,
    InspectionResult res,
    List<InspectedStage> stages,
    InspectedStage? stage,
  ) {
    final c = EditorialColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stages.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(stages.length, (i) {
                final active = _stageIndex == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _stageIndex = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: active ? c.accent : c.surface,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: active ? null : c.cardShadow,
                      ),
                      child: Text(
                        stages[i].stageName,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: active ? const Color(0xFFFFFEFA) : c.ink,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (stage != null) ...[
          _InspectTextBlock(
            title: '正面提示词 · Positive Prompt',
            text: stage.positivePrompt,
            onCopySyntax: (t) =>
                _copyConverted(stage.positivePrompt, '正面提示词', t),
          ),
          const SizedBox(height: 14),
          _InspectTextBlock(
            title: '负面提示词 · Negative Prompt / UC',
            text: stage.negativePrompt,
            onCopySyntax: (t) =>
                _copyConverted(stage.negativePrompt, '负面提示词', t),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: c.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '生成参数矩阵（点击任意磁贴复制）',
                  style: StyleLoomTheme.serifStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (stage.model != null)
                      _ParamKvTile('模型 Model', stage.model!),
                    if (stage.sampler != null)
                      _ParamKvTile('采样器 Sampler', stage.sampler!),
                    if (stage.scheduler != null)
                      _ParamKvTile('调度器 Scheduler', stage.scheduler!),
                    if (stage.steps != null)
                      _ParamKvTile('步数 Steps', '${stage.steps}'),
                    if (stage.cfg != null)
                      _ParamKvTile('引导 CFG', '${stage.cfg}'),
                    if (stage.shift != null)
                      _ParamKvTile('Flow Shift', '${stage.shift}'),
                    if (stage.size != null) _ParamKvTile('尺寸 Size', stage.size!),
                    if (stage.seed != null) _ParamKvTile('种子 Seed', stage.seed!),
                    ...stage.loras.map(
                      (l) => _ParamKvTile('LoRA', '${l.name} (${l.weight})'),
                    ),
                    ...stage.extraFields.map((e) => _ParamKvTile(e.$1, e.$2)),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => setState(() => _rawExpanded = !_rawExpanded),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '原始元数据载荷',
                        style: StyleLoomTheme.serifStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    Icon(
                      _rawExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: c.muted,
                    ),
                  ],
                ),
              ),
              if (_rawExpanded) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.trough,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    res.rawMetadata,
                    style: StyleLoomTheme.monoStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.isCeladon = false});
  final String label;
  final bool isCeladon;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isCeladon ? c.celadonSoft : c.trough,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: isCeladon ? c.celadon : c.ink,
        ),
      ),
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
    final c = EditorialColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: c.cardShadow,
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
              Text(
                title,
                style: StyleLoomTheme.serifStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
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
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.trough,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              text.isEmpty ? '（空）' : text,
              style: StyleLoomTheme.monoStyle(
                fontSize: 12.5,
                height: 1.5,
                color: text.isEmpty ? c.muted : c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamKvTile extends StatelessWidget {
  const _ParamKvTile(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => copyTextWithFeedback(context, value, label),
      child: Container(
        constraints: const BoxConstraints(minWidth: 136),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.trough,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: c.muted)),
            const SizedBox(height: 3),
            Text(
              value,
              style: StyleLoomTheme.monoStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
