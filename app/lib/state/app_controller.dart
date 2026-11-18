import 'package:flutter/foundation.dart';

import '../bridge/core_client.dart';
import '../models/core_models.dart';

class AppController extends ChangeNotifier {
  AppController({required this.client});

  final StyleLoomClient client;

  bool initialized = false;
  bool loading = false;
  String? errorMessage;
  int _recipeRequest = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<PlatformSchema> schemas = [];
  List<PromptSnippet> snippets = [];
  List<StyleRecipe> recipes = [];

  // Navigation & Drawer
  int activeNavIndex = 0; // 0:瀑布流 1:提示词预设 2:原图解析 3:模型模板 4:同步备份
  StyleRecipe? selectedRecipe;
  bool creatingNewRecipe = false;
  String? inspectorPendingPath;
  Uint8List? inspectorPendingBytes;
  String? inspectorPendingName;

  // Waterfall Filters & Grid Density
  String searchQuery = '';
  String? filterPlatform;
  String? filterSchemaId;
  String? filterTag;
  bool favoriteOnly = false;
  int desktopColumns = 4;
  int mobileColumns = 2;

  // WebDAV persisted config
  WebDavConfig webDavConfig = WebDavConfig.koofrDefault();

  Future<void> initialize() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      schemas = await client.initVault();
      snippets = await client.listSnippets();
      recipes = await _fetchFilteredRecipes();

      final savedDav = await client.getSetting('webdav_config');
      if (savedDav is Map) {
        webDavConfig = WebDavConfig.fromJson(
          Map<String, dynamic>.from(savedDav),
        );
      }
      final savedCols = await client.getSetting('grid_columns');
      if (savedCols is Map) {
        desktopColumns = ((savedCols['desktop'] as num?)?.toInt() ?? 4).clamp(
          2,
          8,
        );
        mobileColumns = ((savedCols['mobile'] as num?)?.toInt() ?? 2).clamp(
          1,
          4,
        );
      }
      initialized = true;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  PlatformSchema? schemaById(String id) {
    for (final s in schemas) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<String> get allPlatforms {
    final set = <String>{};
    for (final s in schemas) {
      set.add(s.platform);
    }
    return set.toList();
  }

  List<String> get allRecipeTags {
    final set = <String>{};
    for (final r in recipes) {
      set.addAll(r.tags);
    }
    return set.toList()..sort();
  }

  Future<List<StyleRecipe>> _fetchFilteredRecipes() {
    return client.listRecipes(
      query: searchQuery.trim().isEmpty ? null : searchQuery.trim(),
      platform: filterPlatform,
      schemaId: filterSchemaId,
      tag: filterTag,
      favoriteOnly: favoriteOnly,
    );
  }

  Future<void> refreshAll() async {
    schemas = await client.listSchemas();
    snippets = await client.listSnippets();
    await refreshRecipes();
    final selectedId = selectedRecipe?.id;
    if (selectedId != null && selectedId.isNotEmpty) {
      try {
        final refreshed = await client.getRecipe(selectedId);
        if (selectedRecipe?.id == selectedId) {
          selectedRecipe = refreshed.deleted ? null : refreshed;
        }
      } catch (_) {
        if (selectedRecipe?.id == selectedId) selectedRecipe = null;
      }
    }
    notifyListeners();
  }

  Future<void> refreshRecipes() async {
    final request = ++_recipeRequest;
    try {
      final result = await _fetchFilteredRecipes();
      if (request != _recipeRequest || _disposed) return;
      recipes = result;
      errorMessage = null;
    } catch (e) {
      if (request != _recipeRequest || _disposed) return;
      errorMessage = '加载画师串失败：$e';
    }
    notifyListeners();
  }

  void setNavIndex(int idx) {
    activeNavIndex = idx;
    notifyListeners();
  }

  void openNewRecipeDraft({
    String schemaId = 'nai_v5',
    String positive = '',
    String negative = '',
    Map<String, dynamic>? initialParams,
    List<RecipeImageRef> images = const [],
    String title = '',
  }) {
    final schema =
        schemaById(schemaId) ?? (schemas.isNotEmpty ? schemas.first : null);
    final mergedParams = schema?.defaultParams() ?? <String, dynamic>{};
    if (initialParams != null) {
      mergedParams.addAll(initialParams);
    }
    creatingNewRecipe = true;
    selectedRecipe = StyleRecipe(
      id: '',
      title: title,
      schemaId: schema?.id ?? schemaId,
      positiveRaw: positive,
      negativeRaw: negative,
      params: mergedParams,
      images: images,
    );
    activeNavIndex = 0;
    notifyListeners();
  }

  void selectRecipe(StyleRecipe? recipe) {
    creatingNewRecipe = false;
    selectedRecipe = recipe;
    notifyListeners();
  }

  void closeRecipeDrawer() {
    creatingNewRecipe = false;
    selectedRecipe = null;
    notifyListeners();
  }

  void openInspectorWithFile(String filePath) {
    inspectorPendingPath = filePath;
    inspectorPendingBytes = null;
    inspectorPendingName = null;
    activeNavIndex = 2;
    notifyListeners();
  }

  void openInspectorWithBytes(Uint8List bytes, String filename) {
    inspectorPendingPath = null;
    inspectorPendingBytes = bytes;
    inspectorPendingName = filename;
    activeNavIndex = 2;
    notifyListeners();
  }

  Future<void> updateFilters({
    String? query,
    String? platform,
    bool clearPlatform = false,
    String? schemaId,
    bool clearSchema = false,
    String? tag,
    bool clearTag = false,
    bool? favorite,
  }) async {
    if (query != null) searchQuery = query;
    if (clearPlatform) {
      filterPlatform = null;
      filterSchemaId = null;
    } else if (platform != null) {
      filterPlatform = platform;
      filterSchemaId = null;
    }
    if (clearSchema) {
      filterSchemaId = null;
    } else if (schemaId != null) {
      filterSchemaId = schemaId;
    }
    if (clearTag) {
      filterTag = null;
    } else if (tag != null) {
      filterTag = tag;
    }
    if (favorite != null) favoriteOnly = favorite;
    notifyListeners();
    await refreshRecipes();
  }

  Future<void> setColumns({int? desktop, int? mobile}) async {
    if (desktop != null) desktopColumns = desktop.clamp(2, 8);
    if (mobile != null) mobileColumns = mobile.clamp(1, 4);
    notifyListeners();
    await client.setSetting('grid_columns', {
      'desktop': desktopColumns,
      'mobile': mobileColumns,
    });
  }

  Future<StyleRecipe> saveRecipe(StyleRecipe recipe) async {
    final selection = selectedRecipe;
    final saved = await client.saveRecipe(recipe);
    if (identical(selectedRecipe, selection)) {
      creatingNewRecipe = false;
      selectedRecipe = saved;
    }
    await refreshRecipes();
    notifyListeners();
    return saved;
  }

  Future<void> deleteRecipe(String id) async {
    await client.deleteRecipe(id);
    if (selectedRecipe?.id == id) {
      selectedRecipe = null;
      creatingNewRecipe = false;
    }
    await refreshRecipes();
    notifyListeners();
  }

  Future<StyleRecipe> cloneRecipeToSchema(
    String sourceId,
    String targetSchemaId,
  ) async {
    final cloned = await client.cloneRecipeToSchema(
      sourceId: sourceId,
      targetSchemaId: targetSchemaId,
    );
    await refreshRecipes();
    selectedRecipe = cloned;
    creatingNewRecipe = false;
    notifyListeners();
    return cloned;
  }

  Future<void> toggleFavorite(StyleRecipe recipe) async {
    final updated = StyleRecipe(
      id: recipe.id,
      title: recipe.title,
      schemaId: recipe.schemaId,
      positiveNodes: recipe.positiveNodes,
      positiveRaw: recipe.positiveRaw,
      negativeNodes: recipe.negativeNodes,
      negativeRaw: recipe.negativeRaw,
      params: recipe.params,
      tags: recipe.tags,
      sourceUrl: recipe.sourceUrl,
      notes: recipe.notes,
      rating: recipe.rating,
      favorite: !recipe.favorite,
      images: recipe.images,
      createdAt: recipe.createdAt,
      updatedAt: recipe.updatedAt,
    );
    final saved = await client.saveRecipe(updated);
    if (selectedRecipe?.id == saved.id) selectedRecipe = saved;
    await refreshRecipes();
  }

  Future<PromptSnippet> saveSnippet(PromptSnippet snippet) async {
    final saved = await client.saveSnippet(snippet);
    snippets = await client.listSnippets();
    notifyListeners();
    return saved;
  }

  Future<void> deleteSnippet(String id) async {
    await client.deleteSnippet(id);
    snippets = await client.listSnippets();
    notifyListeners();
  }

  Future<PlatformSchema> saveSchema(PlatformSchema schema) async {
    final saved = await client.upsertSchema(schema);
    schemas = await client.listSchemas();
    notifyListeners();
    return saved;
  }

  Future<void> deleteSchema(String id) async {
    await client.deleteSchema(id);
    schemas = await client.listSchemas();
    notifyListeners();
  }

  Future<void> saveWebDavConfig(WebDavConfig cfg) async {
    webDavConfig = cfg;
    await client.setSetting('webdav_config', cfg.toJson());
    notifyListeners();
  }
}
