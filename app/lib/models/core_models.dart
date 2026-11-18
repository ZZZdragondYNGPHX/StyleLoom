import 'dart:convert';

enum PromptSyntax {
  naiColon('nai_colon', 'NovelAI :: 数值'),
  naiBraces('nai_braces', 'NovelAI {} 括号'),
  sdParens('sd_parens', 'SD / ComfyUI ()'),
  animaAt('anima_at', 'Anima @画师'),
  mossSpace('moss_space', 'MOSS 空格去下划线');

  const PromptSyntax(this.wire, this.label);
  final String wire;
  final String label;

  static PromptSyntax fromWire(String? w) {
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return PromptSyntax.sdParens;
  }
}

enum TargetSyntax {
  asIs('as_is', '按模型原格式'),
  naiColon('nai_colon', 'NAI V4.5/V5 (::)'),
  naiBraces('nai_braces', 'NAI 传统 ({})'),
  sdParens('sd_parens', 'SDXL / ComfyUI (())'),
  animaAt('anima_at', 'Anima (@artist)'),
  mossSpace('moss_space', 'MOSS (空格去下划线)');

  const TargetSyntax(this.wire, this.label);
  final String wire;
  final String label;
}

enum ParamFieldType {
  slider('slider'),
  stepper('stepper'),
  select('select'),
  toggle('toggle'),
  resolution('resolution'),
  loraList('lora_list'),
  text('text');

  const ParamFieldType(this.wire);
  final String wire;

  static ParamFieldType fromWire(String? w) {
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return ParamFieldType.text;
  }
}

class ParamFieldDef {
  ParamFieldDef({
    required this.key,
    required this.label,
    required this.fieldType,
    required this.defaultValue,
    this.min,
    this.max,
    this.step,
    this.recommendedMin,
    this.recommendedMax,
    this.options = const [],
    this.resolutionPresets = const [],
    this.hint,
  });

  final String key;
  final String label;
  final ParamFieldType fieldType;
  final dynamic defaultValue;
  final double? min;
  final double? max;
  final double? step;
  final double? recommendedMin;
  final double? recommendedMax;
  final List<String> options;
  final List<String> resolutionPresets;
  final String? hint;

  factory ParamFieldDef.fromJson(Map<String, dynamic> j) => ParamFieldDef(
        key: j['key'] as String? ?? '',
        label: j['label'] as String? ?? '',
        fieldType: ParamFieldType.fromWire(j['field_type'] as String?),
        defaultValue: j['default_value'],
        min: (j['min'] as num?)?.toDouble(),
        max: (j['max'] as num?)?.toDouble(),
        step: (j['step'] as num?)?.toDouble(),
        recommendedMin: (j['recommended_min'] as num?)?.toDouble(),
        recommendedMax: (j['recommended_max'] as num?)?.toDouble(),
        options: ((j['options'] as List?) ?? []).map((e) => '$e').toList(),
        resolutionPresets: ((j['resolution_presets'] as List?) ?? [])
            .map((e) => '$e')
            .toList(),
        hint: j['hint'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'field_type': fieldType.wire,
        'default_value': defaultValue,
        'min': min,
        'max': max,
        'step': step,
        'recommended_min': recommendedMin,
        'recommended_max': recommendedMax,
        'options': options,
        'resolution_presets': resolutionPresets,
        'hint': hint,
      };
}

class PlatformSchema {
  PlatformSchema({
    required this.id,
    required this.platform,
    required this.modelName,
    required this.defaultSyntax,
    required this.fields,
    this.isBuiltin = false,
    this.updatedAt = 0,
    this.deleted = false,
  });

  final String id;
  final String platform;
  final String modelName;
  final PromptSyntax defaultSyntax;
  final List<ParamFieldDef> fields;
  final bool isBuiltin;
  final int updatedAt;
  final bool deleted;

  String get displayLabel => '$platform · $modelName';

  factory PlatformSchema.fromJson(Map<String, dynamic> j) => PlatformSchema(
        id: j['id'] as String? ?? '',
        platform: j['platform'] as String? ?? '',
        modelName: j['model_name'] as String? ?? '',
        defaultSyntax: PromptSyntax.fromWire(j['default_syntax'] as String?),
        fields: ((j['fields'] as List?) ?? [])
            .map((e) => ParamFieldDef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        isBuiltin: j['is_builtin'] as bool? ?? false,
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
        deleted: j['deleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'platform': platform,
        'model_name': modelName,
        'default_syntax': defaultSyntax.wire,
        'fields': fields.map((f) => f.toJson()).toList(),
        'is_builtin': isBuiltin,
        'updated_at': updatedAt,
        'deleted': deleted,
      };

  Map<String, dynamic> defaultParams() {
    final map = <String, dynamic>{};
    for (final f in fields) {
      map[f.key] = jsonDecode(jsonEncode(f.defaultValue));
    }
    return map;
  }
}

sealed class PromptNode {
  const PromptNode({
    required this.id,
    required this.weight,
    required this.enabled,
  });

  final String id;
  final double weight;
  final bool enabled;

  factory PromptNode.fromJson(Map<String, dynamic> j) {
    final kind = j['kind'] as String? ?? 'token';
    if (kind == 'snippet_ref') {
      return SnippetRefNode(
        id: j['id'] as String? ?? '',
        snippetId: j['snippet_id'] as String? ?? '',
        fallbackName: j['fallback_name'] as String? ?? '',
        fallbackRaw: j['fallback_raw'] as String? ?? '',
        weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
        enabled: j['enabled'] as bool? ?? true,
      );
    }
    return TokenNode(
      id: j['id'] as String? ?? '',
      text: j['text'] as String? ?? '',
      weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
      enabled: j['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson();

  PromptNode copyWithState({double? weight, bool? enabled});
}

class TokenNode extends PromptNode {
  const TokenNode({
    required super.id,
    required this.text,
    super.weight = 1.0,
    super.enabled = true,
  });

  final String text;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'token',
        'id': id,
        'text': text,
        'weight': weight,
        'enabled': enabled,
      };

  @override
  TokenNode copyWithState({String? text, double? weight, bool? enabled}) =>
      TokenNode(
        id: id,
        text: text ?? this.text,
        weight: weight ?? this.weight,
        enabled: enabled ?? this.enabled,
      );
}

class SnippetRefNode extends PromptNode {
  const SnippetRefNode({
    required super.id,
    required this.snippetId,
    required this.fallbackName,
    this.fallbackRaw = '',
    super.weight = 1.0,
    super.enabled = true,
  });

  final String snippetId;
  final String fallbackName;
  final String fallbackRaw;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'snippet_ref',
        'id': id,
        'snippet_id': snippetId,
        'fallback_name': fallbackName,
        'fallback_raw': fallbackRaw,
        'weight': weight,
        'enabled': enabled,
      };

  @override
  SnippetRefNode copyWithState({double? weight, bool? enabled}) =>
      SnippetRefNode(
        id: id,
        snippetId: snippetId,
        fallbackName: fallbackName,
        fallbackRaw: fallbackRaw,
        weight: weight ?? this.weight,
        enabled: enabled ?? this.enabled,
      );
}

class PromptSnippet {
  PromptSnippet({
    required this.id,
    required this.name,
    this.categories = const [],
    this.modelHint = '',
    this.nodes = const [],
    this.rawText = '',
    this.note = '',
    this.updatedAt = 0,
    this.deleted = false,
  });

  final String id;
  final String name;
  final List<String> categories;
  final String modelHint;
  final List<PromptNode> nodes;
  final String rawText;
  final String note;
  final int updatedAt;
  final bool deleted;

  factory PromptSnippet.fromJson(Map<String, dynamic> j) => PromptSnippet(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        categories:
            ((j['categories'] as List?) ?? []).map((e) => '$e').toList(),
        modelHint: j['model_hint'] as String? ?? '',
        nodes: ((j['nodes'] as List?) ?? [])
            .map((e) => PromptNode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        rawText: j['raw_text'] as String? ?? '',
        note: j['note'] as String? ?? '',
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
        deleted: j['deleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'categories': categories,
        'model_hint': modelHint,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'raw_text': rawText,
        'note': note,
        'updated_at': updatedAt,
        'deleted': deleted,
      };
}

class ImageAsset {
  ImageAsset({
    required this.sha256,
    required this.ext,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.blobRelPath,
    required this.thumbRelPath,
    required this.createdAt,
  });

  final String sha256;
  final String ext;
  final int width;
  final int height;
  final int byteSize;
  final String blobRelPath;
  final String thumbRelPath;
  final int createdAt;

  factory ImageAsset.fromJson(Map<String, dynamic> j) => ImageAsset(
        sha256: j['sha256'] as String? ?? '',
        ext: j['ext'] as String? ?? 'png',
        width: (j['width'] as num?)?.toInt() ?? 512,
        height: (j['height'] as num?)?.toInt() ?? 512,
        byteSize: (j['byte_size'] as num?)?.toInt() ?? 0,
        blobRelPath: j['blob_rel_path'] as String? ?? '',
        thumbRelPath: j['thumb_rel_path'] as String? ?? '',
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );

  RecipeImageRef toRecipeRef({String caption = ''}) => RecipeImageRef(
        sha256: sha256,
        ext: ext,
        width: width,
        height: height,
        blobRelPath: blobRelPath,
        thumbRelPath: thumbRelPath,
        caption: caption,
      );
}

class RecipeImageRef {
  RecipeImageRef({
    required this.sha256,
    required this.ext,
    required this.width,
    required this.height,
    required this.blobRelPath,
    required this.thumbRelPath,
    this.caption = '',
  });

  final String sha256;
  final String ext;
  final int width;
  final int height;
  final String blobRelPath;
  final String thumbRelPath;
  final String caption;

  double get aspectRatio => height <= 0 ? 1.0 : (width / height).clamp(0.35, 2.8);

  factory RecipeImageRef.fromJson(Map<String, dynamic> j) => RecipeImageRef(
        sha256: j['sha256'] as String? ?? '',
        ext: j['ext'] as String? ?? 'png',
        width: (j['width'] as num?)?.toInt() ?? 832,
        height: (j['height'] as num?)?.toInt() ?? 1216,
        blobRelPath: j['blob_rel_path'] as String? ?? '',
        thumbRelPath: j['thumb_rel_path'] as String? ?? '',
        caption: j['caption'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'sha256': sha256,
        'ext': ext,
        'width': width,
        'height': height,
        'blob_rel_path': blobRelPath,
        'thumb_rel_path': thumbRelPath,
        'caption': caption,
      };
}

class StyleRecipe {
  StyleRecipe({
    required this.id,
    required this.title,
    required this.schemaId,
    this.positiveNodes = const [],
    this.positiveRaw = '',
    this.negativeNodes = const [],
    this.negativeRaw = '',
    this.params = const {},
    this.tags = const [],
    this.sourceUrl = '',
    this.notes = '',
    this.rating = 0,
    this.favorite = false,
    this.images = const [],
    this.createdAt = 0,
    this.updatedAt = 0,
    this.deleted = false,
  });

  final String id;
  final String title;
  final String schemaId;
  final List<PromptNode> positiveNodes;
  final String positiveRaw;
  final List<PromptNode> negativeNodes;
  final String negativeRaw;
  final Map<String, dynamic> params;
  final List<String> tags;
  final String sourceUrl;
  final String notes;
  final int rating;
  final bool favorite;
  final List<RecipeImageRef> images;
  final int createdAt;
  final int updatedAt;
  final bool deleted;

  factory StyleRecipe.fromJson(Map<String, dynamic> j) => StyleRecipe(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        schemaId: j['schema_id'] as String? ?? 'nai_v5',
        positiveNodes: ((j['positive_nodes'] as List?) ?? [])
            .map((e) => PromptNode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        positiveRaw: j['positive_raw'] as String? ?? '',
        negativeNodes: ((j['negative_nodes'] as List?) ?? [])
            .map((e) => PromptNode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        negativeRaw: j['negative_raw'] as String? ?? '',
        params: Map<String, dynamic>.from((j['params'] as Map?) ?? {}),
        tags: ((j['tags'] as List?) ?? []).map((e) => '$e').toList(),
        sourceUrl: j['source_url'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        favorite: j['favorite'] as bool? ?? false,
        images: ((j['images'] as List?) ?? [])
            .map((e) => RecipeImageRef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
        deleted: j['deleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'schema_id': schemaId,
        'positive_nodes': positiveNodes.map((n) => n.toJson()).toList(),
        'positive_raw': positiveRaw,
        'negative_nodes': negativeNodes.map((n) => n.toJson()).toList(),
        'negative_raw': negativeRaw,
        'params': params,
        'tags': tags,
        'source_url': sourceUrl,
        'notes': notes,
        'rating': rating,
        'favorite': favorite,
        'images': images.map((i) => i.toJson()).toList(),
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted,
      };
}

class InspectedLora {
  InspectedLora({required this.name, required this.weight});
  final String name;
  final double weight;

  factory InspectedLora.fromJson(Map<String, dynamic> j) => InspectedLora(
        name: j['name'] as String? ?? '',
        weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
      );
}

class InspectedStage {
  InspectedStage({
    required this.stageName,
    required this.positivePrompt,
    required this.negativePrompt,
    this.model,
    this.sampler,
    this.scheduler,
    this.steps,
    this.cfg,
    this.seed,
    this.size,
    this.shift,
    this.loras = const [],
    this.extraFields = const [],
  });

  final String stageName;
  final String positivePrompt;
  final String negativePrompt;
  final String? model;
  final String? sampler;
  final String? scheduler;
  final int? steps;
  final double? cfg;
  final String? seed;
  final String? size;
  final double? shift;
  final List<InspectedLora> loras;
  final List<(String, String)> extraFields;

  factory InspectedStage.fromJson(Map<String, dynamic> j) => InspectedStage(
        stageName: j['stage_name'] as String? ?? '参数详情',
        positivePrompt: j['positive_prompt'] as String? ?? '',
        negativePrompt: j['negative_prompt'] as String? ?? '',
        model: j['model'] as String?,
        sampler: j['sampler'] as String?,
        scheduler: j['scheduler'] as String?,
        steps: (j['steps'] as num?)?.toInt(),
        cfg: (j['cfg'] as num?)?.toDouble(),
        seed: j['seed'] as String?,
        size: j['size'] as String?,
        shift: (j['shift'] as num?)?.toDouble(),
        loras: ((j['loras'] as List?) ?? [])
            .map((e) => InspectedLora.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        extraFields: ((j['extra_fields'] as List?) ?? []).map((e) {
          final arr = e as List;
          return ('${arr[0]}', '${arr[1]}');
        }).toList(),
      );
}

class InspectionResult {
  InspectionResult({
    required this.sourceKind,
    this.suggestedSchemaId,
    this.width,
    this.height,
    required this.stages,
    required this.rawMetadata,
  });

  final String sourceKind;
  final String? suggestedSchemaId;
  final int? width;
  final int? height;
  final List<InspectedStage> stages;
  final String rawMetadata;

  factory InspectionResult.fromJson(Map<String, dynamic> j) => InspectionResult(
        sourceKind: j['source_kind'] as String? ?? '',
        suggestedSchemaId: j['suggested_schema_id'] as String?,
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        stages: ((j['stages'] as List?) ?? [])
            .map((e) => InspectedStage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        rawMetadata: j['raw_metadata'] as String? ?? '',
      );
}

class WebDavConfig {
  WebDavConfig({
    required this.preset,
    required this.endpointUrl,
    required this.username,
    required this.password,
    required this.remoteDir,
  });

  final String preset;
  final String endpointUrl;
  final String username;
  final String password;
  final String remoteDir;

  factory WebDavConfig.koofrDefault() => WebDavConfig(
        preset: 'koofr',
        endpointUrl: 'https://app.koofr.net/dav/Koofr',
        username: '',
        password: '',
        remoteDir: '/StyleLoom',
      );

  factory WebDavConfig.fromJson(Map<String, dynamic> j) => WebDavConfig(
        preset: j['preset'] as String? ?? 'koofr',
        endpointUrl:
            j['endpoint_url'] as String? ?? 'https://app.koofr.net/dav/Koofr',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        remoteDir: j['remote_dir'] as String? ?? '/StyleLoom',
      );

  Map<String, dynamic> toJson() => {
        'preset': preset,
        'endpoint_url': endpointUrl,
        'username': username,
        'password': password,
        'remote_dir': remoteDir,
      };
}

class SyncReport {
  SyncReport({
    this.uploadedBlobs = 0,
    this.downloadedBlobs = 0,
    this.pushedSchemas = 0,
    this.pulledSchemas = 0,
    this.pushedSnippets = 0,
    this.pulledSnippets = 0,
    this.pushedRecipes = 0,
    this.pulledRecipes = 0,
    this.conflictCopies = 0,
    this.message = '',
  });

  final int uploadedBlobs;
  final int downloadedBlobs;
  final int pushedSchemas;
  final int pulledSchemas;
  final int pushedSnippets;
  final int pulledSnippets;
  final int pushedRecipes;
  final int pulledRecipes;
  final int conflictCopies;
  final String message;

  factory SyncReport.fromJson(Map<String, dynamic> j) => SyncReport(
        uploadedBlobs: (j['uploaded_blobs'] as num?)?.toInt() ?? 0,
        downloadedBlobs: (j['downloaded_blobs'] as num?)?.toInt() ?? 0,
        pushedSchemas: (j['pushed_schemas'] as num?)?.toInt() ?? 0,
        pulledSchemas: (j['pulled_schemas'] as num?)?.toInt() ?? 0,
        pushedSnippets: (j['pushed_snippets'] as num?)?.toInt() ?? 0,
        pulledSnippets: (j['pulled_snippets'] as num?)?.toInt() ?? 0,
        pushedRecipes: (j['pushed_recipes'] as num?)?.toInt() ?? 0,
        pulledRecipes: (j['pulled_recipes'] as num?)?.toInt() ?? 0,
        conflictCopies: (j['conflict_copies'] as num?)?.toInt() ?? 0,
        message: j['message'] as String? ?? '',
      );
}
