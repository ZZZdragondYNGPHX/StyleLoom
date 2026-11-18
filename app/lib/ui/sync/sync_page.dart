import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../models/core_models.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.controller});

  final AppController controller;

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
        remoteDir: _dirCtrl.text.trim().isEmpty ? '/StyleLoom' : _dirCtrl.text.trim(),
      );

  Future<void> _saveConfig() async {
    await widget.controller.saveWebDavConfig(_currentConfig());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV 配置已保存到本地')),
      );
    }
  }

  Future<void> _testWebdav() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final cfg = _currentConfig();
      await widget.controller.saveWebDavConfig(cfg);
      final msg = await widget.controller.client.testWebdav(cfg);
      if (mounted) setState(() => _statusMessage = msg);
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncWebdav() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final cfg = _currentConfig();
      await widget.controller.saveWebDavConfig(cfg);
      final rep = await widget.controller.client.syncWebdav(cfg);
      await widget.controller.refreshAll();
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
            '${widget.controller.client.vaultDir}${Platform.pathSeparator}exports');
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
    final recipes = widget.controller.recipes;
    if (recipes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可导出的画师串卡片')),
      );
      return;
    }
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
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
              onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, true),
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
    const group = XTypeGroup(label: 'StyleLoom 归档包', extensions: ['slpack', 'zip']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

    setState(() => _busy = true);
    try {
      String srcPath = file.path;
      if (srcPath.isEmpty || Platform.isAndroid) {
        // Ensure real readable temp file on Android content URIs
        final bytes = await file.readAsBytes();
        final tmpDir = Directory(
            '${widget.controller.client.vaultDir}${Platform.pathSeparator}tmp_import');
        if (!tmpDir.existsSync()) tmpDir.createSync(recursive: true);
        final tmpFile = File('${tmpDir.path}${Platform.pathSeparator}import.slpack');
        await tmpFile.writeAsBytes(bytes);
        srcPath = tmpFile.path;
      }
      final rep = await widget.controller.client.importSlpack(srcPath);
      await widget.controller.refreshAll();
      if (mounted) setState(() => _statusMessage = rep.message);
    } catch (e) {
      if (mounted) setState(() => _statusMessage = '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          width: double.infinity,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: StyleLoomTheme.border)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('双端数据同步与离线归档（.slpack + Koofr WebDAV）',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text(
                '支持离线 .slpack 压缩包互传，以及原生 HTTPS WebDAV 内容寻址增量同步（图片按 SHA-256 只上传一次）。',
                style: TextStyle(
                    fontSize: 12, color: StyleLoomTheme.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_statusMessage != null) ...[
                Card(
                  color: StyleLoomTheme.accentSoft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _statusMessage!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Offline .slpack section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.inventory_2_rounded,
                              size: 18, color: StyleLoomTheme.teal),
                          SizedBox(width: 8),
                          Text('离线压缩包 (.slpack)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '将画师串卡片、关联提示词片段、自定义模型模板与高清原图打包为单个 .slpack 文件，Windows 与 Android 之间任意传输合并。',
                        style: TextStyle(
                            fontSize: 12, color: StyleLoomTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
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
                ),
              ),

              const SizedBox(height: 14),

              // WebDAV section (Koofr + Custom)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.cloud_sync_rounded,
                              size: 18, color: StyleLoomTheme.accent),
                          SizedBox(width: 8),
                          Text('原生 HTTPS WebDAV 增量同步',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'koofr', label: Text('Koofr 快捷预设')),
                          ButtonSegment(
                              value: 'custom', label: Text('通用 WebDAV')),
                        ],
                        selected: {_preset},
                        onSelectionChanged: (s) {
                          setState(() {
                            _preset = s.first;
                            if (_preset == 'koofr') {
                              _endpointCtrl.text =
                                  'https://app.koofr.net/dav/Koofr';
                            }
                          });
                        },
                      ),
                      if (_preset == 'koofr') ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: StyleLoomTheme.surfaceHigh,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: StyleLoomTheme.border),
                          ),
                          child: const Text(
                            'Koofr 提示：WebDAV 地址固定为 https://app.koofr.net/dav/Koofr（区分大小写）；用户名填 Koofr 注册邮箱，密码请前往 Koofr 网页端 Preferences → Password → App passwords 生成「应用专用密码」（主登录密码会被拒绝）。',
                            style: TextStyle(
                                fontSize: 12,
                                color: StyleLoomTheme.textSecondary),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _endpointCtrl,
                        decoration:
                            const InputDecoration(labelText: 'WebDAV 端点 URL'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _userCtrl,
                              decoration: const InputDecoration(
                                  labelText: '账号邮箱 / 用户名'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _passCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: '应用专用密码 (App Password)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _dirCtrl,
                        decoration: const InputDecoration(
                            labelText: '远端同步子目录', hintText: '/StyleLoom'),
                      ),
                      const SizedBox(height: 14),
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
                            icon: const Icon(Icons.network_check_rounded,
                                size: 17),
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
