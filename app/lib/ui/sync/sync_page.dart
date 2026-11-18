import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.controller, this.isDesktop = true});

  final AppController controller;
  final bool isDesktop;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  static const _platformChannel = MethodChannel('com.styleloom/platform');

  late String _preset;
  late TextEditingController _endpointCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  late TextEditingController _dirCtrl;

  bool _busy = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    final cfg = widget.controller.webDavConfig;
    _preset = cfg.preset;
    _endpointCtrl = TextEditingController(text: cfg.endpointUrl);
    _userCtrl = TextEditingController(text: cfg.username);
    _passCtrl = TextEditingController(text: cfg.password);
    _dirCtrl = TextEditingController(text: cfg.remoteDir);
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  WebDavConfig _currentConfig() => WebDavConfig(
    preset: _preset,
    endpointUrl: _endpointCtrl.text.trim(),
    username: _userCtrl.text.trim(),
    password: _passCtrl.text,
    remoteDir: _dirCtrl.text.trim().isEmpty
        ? '/StyleLoom'
        : _dirCtrl.text.trim(),
  );

  Future<void> _saveConfig() async {
    await widget.controller.saveWebDavConfig(_currentConfig());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('WebDAV 配置已保存到本地')));
    }
  }

  Future<void> _testWebdav() async {
    final controller = widget.controller;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final cfg = _currentConfig();
      await controller.saveWebDavConfig(cfg);
      final msg = await controller.client.testWebdav(cfg);
      if (mounted) setState(() => _statusMessage = msg);
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncWebdav() async {
    final controller = widget.controller;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final cfg = _currentConfig();
      await controller.saveWebDavConfig(cfg);
      final rep = await controller.client.syncWebdav(cfg);
      await controller.refreshAll();
      if (mounted) setState(() => _statusMessage = rep.message);
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '同步失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSlpack({List<String>? recipeIds}) async {
    setState(() => _busy = true);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'StyleLoom-backup-$ts.slpack';
      String? destPath;
      if (Platform.isAndroid) {
        final expDir = Directory(
          '${widget.controller.client.vaultDir}${Platform.pathSeparator}exports',
        );
        if (!expDir.existsSync()) expDir.createSync(recursive: true);
        destPath = '${expDir.path}${Platform.pathSeparator}$fileName';
      } else {
        final loc = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'StyleLoom 归档包', extensions: ['slpack']),
          ],
        );
        destPath = loc?.path;
      }
      if (destPath == null) return;
      if (!destPath.toLowerCase().endsWith('.slpack')) {
        destPath = '$destPath.slpack';
      }

      final rep = await widget.controller.client.exportSlpack(
        recipeIds: recipeIds,
        destPath: destPath,
      );
      if (Platform.isAndroid) {
        try {
          await _platformChannel.invokeMethod('shareFile', {
            'path': destPath,
            'mimeType': 'application/octet-stream',
          });
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _statusMessage = '${rep.message}\n保存位置：$destPath');
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSelectedRecipes() async {
    final c = EditorialColors.of(context);
    final recipes = widget.controller.recipes;
    if (recipes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前没有可导出的画师串卡片')));
      return;
    }
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: c.surface,
          title: const Text('选择要打包分享的画师串'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView.builder(
              itemCount: recipes.length,
              itemBuilder: (_, i) {
                final r = recipes[i];
                final checked = selected.contains(r.id);
                return CheckboxListTile(
                  value: checked,
                  title: Text(r.title.isEmpty ? '未命名卡片' : r.title),
                  subtitle: Text(
                    widget.controller.schemaById(r.schemaId)?.modelName ??
                        r.schemaId,
                  ),
                  onChanged: (_) => setDlg(() {
                    if (checked) {
                      selected.remove(r.id);
                    } else {
                      selected.add(r.id);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text('导出所选 (${selected.length})'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && selected.isNotEmpty) {
      await _exportSlpack(recipeIds: selected.toList());
    }
  }

  Future<void> _importSlpack() async {
    final controller = widget.controller;
    const group = XTypeGroup(
      label: 'StyleLoom 归档包',
      extensions: ['slpack', 'zip'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (!mounted || file == null) return;

    setState(() => _busy = true);
    try {
      String srcPath = file.path;
      if (srcPath.isEmpty || Platform.isAndroid) {
        final bytes = await file.readAsBytes();
        final tmpDir = Directory(
          '${controller.client.vaultDir}${Platform.pathSeparator}tmp_import',
        );
        if (!tmpDir.existsSync()) tmpDir.createSync(recursive: true);
        final tmpFile = File(
          '${tmpDir.path}${Platform.pathSeparator}import.slpack',
        );
        await tmpFile.writeAsBytes(bytes);
        srcPath = tmpFile.path;
      }
      final rep = await controller.client.importSlpack(srcPath);
      await controller.refreshAll();
      if (mounted) setState(() => _statusMessage = rep.message);
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = EditorialColors.of(context);
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
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: widget.isDesktop ? 10 : 14,
                  bottom: 18,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.hairline)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '同步与云匣 · .slpack & Koofr WebDAV',
                      style: StyleLoomTheme.serifStyle(
                        fontSize: widget.isDesktop ? 26 : 21,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '离线 .slpack 压缩包跨端互传，及原生 HTTPS WebDAV 内容寻址增量同步（原图按 SHA-256 仅上传一次）。',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    top: 20,
                    bottom: widget.isDesktop ? 40 : 96,
                  ),
                  children: [
                    if (_busy)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(
                          color: c.accent,
                          backgroundColor: c.trough,
                        ),
                      ),
                    if (_statusMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.celadonSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(
                          _statusMessage!,
                          style: StyleLoomTheme.monoStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    LayoutBuilder(
                      builder: (_, box) {
                        final split = box.maxWidth >= 820;
                        final slpackCard = _buildSlpackCard(context);
                        final webdavCard = _buildWebdavCard(context);
                        if (split) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: slpackCard),
                              const SizedBox(width: 22),
                              Expanded(flex: 7, child: webdavCard),
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            slpackCard,
                            const SizedBox(height: 16),
                            webdavCard,
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

  Widget _buildSlpackCard(BuildContext context) {
    final c = EditorialColors.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.celadonSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.inventory_2_rounded,
                  size: 18,
                  color: c.celadon,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '离线归档包 (.slpack)',
                  style: StyleLoomTheme.serifStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '将画师串卡片、关联词条积木、自定义模型模板与高清原图打包为单个 .slpack 文件，Windows 与 Android 之间自由传输并自动按 SHA-256 去重合并。',
            style: TextStyle(fontSize: 13, color: c.muted, height: 1.55),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.celadon,
                  foregroundColor: const Color(0xFFFFFEFA),
                ),
                onPressed: _busy ? null : () => _exportSlpack(),
                icon: const Icon(Icons.archive_rounded, size: 17),
                label: const Text('导出全库 .slpack'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _exportSelectedRecipes,
                icon: const Icon(Icons.checklist_rounded, size: 17),
                label: const Text('挑选卡片导出'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _importSlpack,
                icon: const Icon(Icons.unarchive_rounded, size: 17),
                label: const Text('导入 .slpack'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebdavCard(BuildContext context) {
    final c = EditorialColors.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.cloud_sync_rounded,
                  size: 18,
                  color: c.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '原生 HTTPS WebDAV 增量同步',
                  style: StyleLoomTheme.serifStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: c.trough,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PresetPill(
                    label: 'Koofr 快捷预设',
                    selected: _preset == 'koofr',
                    onTap: () => setState(() {
                      _preset = 'koofr';
                      _endpointCtrl.text = 'https://app.koofr.net/dav/Koofr';
                    }),
                  ),
                  _PresetPill(
                    label: '通用 WebDAV',
                    selected: _preset == 'custom',
                    onTap: () => setState(() => _preset = 'custom'),
                  ),
                ],
              ),
            ),
          ),
          if (_preset == 'koofr') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.trough,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Koofr 提示：WebDAV 地址固定为 https://app.koofr.net/dav/Koofr（区分大小写）；用户名填注册邮箱，密码请前往 Koofr 网页端 Preferences → Password → App passwords 生成「应用专用密码」（主登录密码会被拒绝）。',
                style: TextStyle(fontSize: 12, color: c.muted, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _endpointCtrl,
            decoration: const InputDecoration(labelText: 'WebDAV 端点 URL'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(labelText: '账号邮箱 / 用户名'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '应用专用密码 (App Password)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _dirCtrl,
            decoration: const InputDecoration(
              labelText: '远端同步子目录',
              hintText: '/StyleLoom',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _saveConfig,
                icon: const Icon(Icons.save_rounded, size: 17),
                label: const Text('保存配置'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testWebdav,
                icon: const Icon(Icons.network_check_rounded, size: 17),
                label: const Text('测试连接'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _syncWebdav,
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text('立即增量同步'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetPill extends StatelessWidget {
  const _PresetPill({
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
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected ? c.cardShadow : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? c.ink : c.muted,
          ),
        ),
      ),
    );
  }
}
