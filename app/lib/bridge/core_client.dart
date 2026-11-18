import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../models/core_models.dart';

typedef _InvokeJsonNative = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _InvokeJsonDart = Pointer<Utf8> Function(Pointer<Utf8> request);

typedef _InspectBytesNative = Pointer<Utf8> Function(
    Pointer<Uint8> bytes, Size len, Pointer<Utf8> hint);
typedef _InspectBytesDart = Pointer<Utf8> Function(
    Pointer<Uint8> bytes, int len, Pointer<Utf8> hint);

typedef _FreeBufNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeBufDart = void Function(Pointer<Utf8> ptr);

class CoreException implements Exception {
  CoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

DynamicLibrary _openCoreLibrary([String? overridePath]) {
  if (overridePath != null && overridePath.isNotEmpty) {
    return DynamicLibrary.open(overridePath);
  }
  final envPath = Platform.environment['STYLELOOM_CORE_LIB'];
  if (envPath != null && envPath.isNotEmpty && File(envPath).existsSync()) {
    return DynamicLibrary.open(envPath);
  }

  if (Platform.isAndroid) {
    return DynamicLibrary.open('libstyleloom_core.so');
  }

  final exeDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isWindows) {
    final candidates = [
      '$exeDir\\styleloom_core.dll',
      'styleloom_core.dll',
      'rust\\target\\release\\styleloom_core.dll',
      '..\\rust\\target\\release\\styleloom_core.dll',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return DynamicLibrary.open(c);
    }
    return DynamicLibrary.open('styleloom_core.dll');
  }

  if (Platform.isLinux) {
    final candidates = [
      '$exeDir/lib/libstyleloom_core.so',
      '$exeDir/libstyleloom_core.so',
      'rust/target/release/libstyleloom_core.so',
      '../rust/target/release/libstyleloom_core.so',
      'rust/target/debug/libstyleloom_core.so',
      '../rust/target/debug/libstyleloom_core.so',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return DynamicLibrary.open(c);
    }
    return DynamicLibrary.open('libstyleloom_core.so');
  }

  if (Platform.isMacOS) {
    return DynamicLibrary.open('libstyleloom_core.dylib');
  }
  return DynamicLibrary.process();
}

String _invokeNativeSync(String reqJson, String? libPath) {
  final lib = _openCoreLibrary(libPath);
  final invokeFn = lib.lookupFunction<_InvokeJsonNative, _InvokeJsonDart>(
      'styleloom_invoke_json');
  final freeFn =
      lib.lookupFunction<_FreeBufNative, _FreeBufDart>('styleloom_free_buf');

  final reqPtr = reqJson.toNativeUtf8();
  Pointer<Utf8>? respPtr;
  try {
    respPtr = invokeFn(reqPtr);
    return respPtr.toDartString();
  } finally {
    calloc.free(reqPtr);
    if (respPtr != null && respPtr.address != 0) {
      freeFn(respPtr);
    }
  }
}

String _inspectBytesNativeSync(
    Uint8List bytes, String hint, String? libPath) {
  final lib = _openCoreLibrary(libPath);
  final inspectFn = lib.lookupFunction<_InspectBytesNative, _InspectBytesDart>(
      'styleloom_inspect_bytes');
  final freeFn =
      lib.lookupFunction<_FreeBufNative, _FreeBufDart>('styleloom_free_buf');

  final bufPtr = calloc<Uint8>(bytes.length);
  final hintPtr = hint.toNativeUtf8();
  Pointer<Utf8>? respPtr;
  try {
    bufPtr.asTypedList(bytes.length).setAll(0, bytes);
    respPtr = inspectFn(bufPtr, bytes.length, hintPtr);
    return respPtr.toDartString();
  } finally {
    calloc.free(bufPtr);
    calloc.free(hintPtr);
    if (respPtr != null && respPtr.address != 0) {
      freeFn(respPtr);
    }
  }
}

class StyleLoomClient {
  StyleLoomClient({required this.vaultDir, this.libraryPath});

  final String vaultDir;
  final String? libraryPath;

  static Future<String> resolveDefaultVaultDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    return '${docDir.path}${sep}StyleLoomVault';
  }

  String resolveVaultPath(String relPath) {
    if (relPath.isEmpty) return '';
    final normalized = relPath.replaceAll('/', Platform.pathSeparator);
    return '$vaultDir${Platform.pathSeparator}$normalized';
  }

  Future<dynamic> _invoke(Map<String, dynamic> payload) async {
    final reqJson = jsonEncode(payload);
    final libPath = libraryPath;
    final rawResp =
        await Isolate.run(() => _invokeNativeSync(reqJson, libPath));
    final decoded = jsonDecode(rawResp) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw CoreException(decoded['error'] as String? ?? '未知内核错误');
    }
    return decoded['data'];
  }

  Future<List<PlatformSchema>> initVault() async {
    final data = await _invoke({'op': 'init_vault', 'vault_dir': vaultDir})
        as Map<String, dynamic>;
    return ((data['schemas'] as List?) ?? [])
        .map((e) => PlatformSchema.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<PlatformSchema>> listSchemas() async {
    final data =
        await _invoke({'op': 'list_schemas', 'vault_dir': vaultDir}) as List;
    return data
        .map((e) => PlatformSchema.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<PlatformSchema> upsertSchema(PlatformSchema schema) async {
    final data = await _invoke({
      'op': 'upsert_schema',
      'vault_dir': vaultDir,
      'schema': schema.toJson(),
    }) as Map<String, dynamic>;
    return PlatformSchema.fromJson(data);
  }

  Future<void> deleteSchema(String id) async {
    await _invoke({'op': 'delete_schema', 'vault_dir': vaultDir, 'id': id});
  }

  Future<List<PromptSnippet>> listSnippets(
      {String? query, String? category}) async {
    final data = await _invoke({
      'op': 'list_snippets',
      'vault_dir': vaultDir,
      'query': query,
      'category': category,
    }) as List;
    return data
        .map((e) => PromptSnippet.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<PromptSnippet> saveSnippet(PromptSnippet snippet) async {
    final data = await _invoke({
      'op': 'save_snippet',
      'vault_dir': vaultDir,
      'snippet': snippet.toJson(),
    }) as Map<String, dynamic>;
    return PromptSnippet.fromJson(data);
  }

  Future<void> deleteSnippet(String id) async {
    await _invoke({'op': 'delete_snippet', 'vault_dir': vaultDir, 'id': id});
  }

  Future<List<StyleRecipe>> listRecipes({
    String? query,
    String? platform,
    String? schemaId,
    String? tag,
    bool favoriteOnly = false,
  }) async {
    final data = await _invoke({
      'op': 'list_recipes',
      'vault_dir': vaultDir,
      'filter': {
        'query': query,
        'platform': platform,
        'schema_id': schemaId,
        'tag': tag,
        'favorite_only': favoriteOnly,
      },
    }) as List;
    return data
        .map((e) => StyleRecipe.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<StyleRecipe> getRecipe(String id) async {
    final data = await _invoke({
      'op': 'get_recipe',
      'vault_dir': vaultDir,
      'id': id,
    }) as Map<String, dynamic>;
    return StyleRecipe.fromJson(data);
  }

  Future<StyleRecipe> saveRecipe(StyleRecipe recipe) async {
    final data = await _invoke({
      'op': 'save_recipe',
      'vault_dir': vaultDir,
      'recipe': recipe.toJson(),
    }) as Map<String, dynamic>;
    return StyleRecipe.fromJson(data);
  }

  Future<void> deleteRecipe(String id) async {
    await _invoke({'op': 'delete_recipe', 'vault_dir': vaultDir, 'id': id});
  }

  Future<StyleRecipe> cloneRecipeToSchema({
    required String sourceId,
    required String targetSchemaId,
    String? newTitle,
  }) async {
    final data = await _invoke({
      'op': 'clone_recipe_to_schema',
      'vault_dir': vaultDir,
      'source_id': sourceId,
      'target_schema_id': targetSchemaId,
      'new_title': newTitle,
    }) as Map<String, dynamic>;
    return StyleRecipe.fromJson(data);
  }

  Future<ImageAsset> importImageFile(String filePath) async {
    final data = await _invoke({
      'op': 'import_image_file',
      'vault_dir': vaultDir,
      'file_path': filePath,
    }) as Map<String, dynamic>;
    return ImageAsset.fromJson(data);
  }

  Future<ImageAsset> importImageBytes(Uint8List bytes) async {
    final data = await _invoke({
      'op': 'import_image_base64',
      'vault_dir': vaultDir,
      'data_b64': base64Encode(bytes),
    }) as Map<String, dynamic>;
    return ImageAsset.fromJson(data);
  }

  Future<InspectionResult> inspectFile(String filePath) async {
    final data = await _invoke({
      'op': 'inspect_file',
      'file_path': filePath,
    }) as Map<String, dynamic>;
    return InspectionResult.fromJson(data);
  }

  Future<InspectionResult> inspectBytes(Uint8List bytes, String hint) async {
    final libPath = libraryPath;
    final rawResp = await Isolate.run(
        () => _inspectBytesNativeSync(bytes, hint, libPath));
    final decoded = jsonDecode(rawResp) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw CoreException(decoded['error'] as String? ?? '解析失败');
    }
    return InspectionResult.fromJson(
        Map<String, dynamic>.from(decoded['data'] as Map));
  }

  Future<List<PromptNode>> parseRawToNodes(String raw) async {
    final data = await _invoke({
      'op': 'parse_raw_to_nodes',
      'vault_dir': vaultDir,
      'raw': raw,
    }) as List;
    return data
        .map((e) => PromptNode.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<String> nodesToRaw(
      List<PromptNode> nodes, PromptSyntax syntax) async {
    final data = await _invoke({
      'op': 'nodes_to_raw',
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'syntax': syntax.wire,
    }) as Map<String, dynamic>;
    return data['raw'] as String? ?? '';
  }

  Future<String> renderCopyNodes({
    required List<PromptNode> nodes,
    required PromptSyntax modelSyntax,
    TargetSyntax targetSyntax = TargetSyntax.asIs,
  }) async {
    final data = await _invoke({
      'op': 'render_copy_nodes',
      'vault_dir': vaultDir,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'model_syntax': modelSyntax.wire,
      'target_syntax': targetSyntax.wire,
    }) as Map<String, dynamic>;
    return data['text'] as String? ?? '';
  }

  Future<String> renderRecipePrompt({
    required String recipeId,
    required String side,
    TargetSyntax targetSyntax = TargetSyntax.asIs,
  }) async {
    final data = await _invoke({
      'op': 'render_recipe_prompt',
      'vault_dir': vaultDir,
      'recipe_id': recipeId,
      'side': side,
      'target_syntax': targetSyntax.wire,
    }) as Map<String, dynamic>;
    return data['text'] as String? ?? '';
  }

  Future<List<PromptNode>> ungroupSnippetNode({
    required List<PromptNode> nodes,
    required String nodeId,
  }) async {
    final data = await _invoke({
      'op': 'ungroup_snippet_node',
      'vault_dir': vaultDir,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'node_id': nodeId,
    }) as List;
    return data
        .map((e) => PromptNode.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<SyncReport> exportSlpack({
    List<String>? recipeIds,
    required String destPath,
  }) async {
    final data = await _invoke({
      'op': 'export_slpack',
      'vault_dir': vaultDir,
      'recipe_ids': recipeIds,
      'dest_path': destPath,
    }) as Map<String, dynamic>;
    return SyncReport.fromJson(data);
  }

  Future<SyncReport> importSlpack(String srcPath) async {
    final data = await _invoke({
      'op': 'import_slpack',
      'vault_dir': vaultDir,
      'src_path': srcPath,
    }) as Map<String, dynamic>;
    return SyncReport.fromJson(data);
  }

  Future<dynamic> getSetting(String key) async {
    return _invoke({'op': 'get_setting', 'vault_dir': vaultDir, 'key': key});
  }

  Future<void> setSetting(String key, dynamic value) async {
    await _invoke({
      'op': 'set_setting',
      'vault_dir': vaultDir,
      'key': key,
      'value': value,
    });
  }

  Future<String> testWebdav(WebDavConfig config) async {
    final data = await _invoke({
      'op': 'test_webdav',
      'config': config.toJson(),
    }) as Map<String, dynamic>;
    return data['message'] as String? ?? '连接成功';
  }

  Future<SyncReport> syncWebdav(WebDavConfig config) async {
    final data = await _invoke({
      'op': 'sync_webdav',
      'vault_dir': vaultDir,
      'config': config.toJson(),
    }) as Map<String, dynamic>;
    return SyncReport.fromJson(data);
  }
}
