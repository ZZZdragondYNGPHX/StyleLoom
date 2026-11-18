use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("Parse error: {0}")]
    Parse(String),
    #[error("Sync error: {0}")]
    Sync(String),
    #[error("Not found: {0}")]
    NotFound(String),
    #[error("Invalid input: {0}")]
    InvalidInput(String),
}

pub type CoreResult<T> = Result<T, CoreError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PromptSyntax {
    NaiColon,
    NaiBraces,
    SdParens,
    AnimaAt,
    MossSpace,
}

impl PromptSyntax {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::NaiColon => "nai_colon",
            Self::NaiBraces => "nai_braces",
            Self::SdParens => "sd_parens",
            Self::AnimaAt => "anima_at",
            Self::MossSpace => "moss_space",
        }
    }

    pub fn from_str_lossy(s: &str) -> Self {
        match s.trim() {
            "nai_colon" => Self::NaiColon,
            "nai_braces" => Self::NaiBraces,
            "sd_parens" => Self::SdParens,
            "anima_at" => Self::AnimaAt,
            "moss_space" => Self::MossSpace,
            _ => Self::SdParens,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TargetSyntax {
    AsIs,
    NaiColon,
    NaiBraces,
    SdParens,
    AnimaAt,
    MossSpace,
}

impl TargetSyntax {
    pub fn resolve(self, model_default: PromptSyntax) -> PromptSyntax {
        match self {
            Self::AsIs => model_default,
            Self::NaiColon => PromptSyntax::NaiColon,
            Self::NaiBraces => PromptSyntax::NaiBraces,
            Self::SdParens => PromptSyntax::SdParens,
            Self::AnimaAt => PromptSyntax::AnimaAt,
            Self::MossSpace => PromptSyntax::MossSpace,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ParamFieldType {
    Slider,
    Stepper,
    Select,
    Toggle,
    Resolution,
    LoraList,
    Text,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ParamFieldDef {
    pub key: String,
    pub label: String,
    pub field_type: ParamFieldType,
    pub default_value: Value,
    #[serde(default)]
    pub min: Option<f64>,
    #[serde(default)]
    pub max: Option<f64>,
    #[serde(default)]
    pub step: Option<f64>,
    #[serde(default)]
    pub recommended_min: Option<f64>,
    #[serde(default)]
    pub recommended_max: Option<f64>,
    #[serde(default)]
    pub options: Vec<String>,
    #[serde(default)]
    pub resolution_presets: Vec<String>,
    #[serde(default)]
    pub hint: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlatformSchema {
    pub id: String,
    pub platform: String,
    pub model_name: String,
    pub default_syntax: PromptSyntax,
    pub fields: Vec<ParamFieldDef>,
    #[serde(default)]
    pub is_builtin: bool,
    #[serde(default)]
    pub updated_at: i64,
    #[serde(default)]
    pub deleted: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum PromptNode {
    Token {
        id: String,
        text: String,
        #[serde(default = "default_weight")]
        weight: f64,
        #[serde(default = "default_true")]
        enabled: bool,
    },
    SnippetRef {
        id: String,
        snippet_id: String,
        fallback_name: String,
        #[serde(default)]
        fallback_raw: String,
        #[serde(default = "default_weight")]
        weight: f64,
        #[serde(default = "default_true")]
        enabled: bool,
    },
}

fn default_weight() -> f64 {
    1.0
}

fn default_true() -> bool {
    true
}

impl PromptNode {
    pub fn id(&self) -> &str {
        match self {
            Self::Token { id, .. } | Self::SnippetRef { id, .. } => id,
        }
    }

    pub fn is_enabled(&self) -> bool {
        match self {
            Self::Token { enabled, .. } | Self::SnippetRef { enabled, .. } => *enabled,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PromptSnippet {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub categories: Vec<String>,
    #[serde(default)]
    pub model_hint: String,
    #[serde(default)]
    pub nodes: Vec<PromptNode>,
    #[serde(default)]
    pub raw_text: String,
    #[serde(default)]
    pub note: String,
    #[serde(default)]
    pub updated_at: i64,
    #[serde(default)]
    pub deleted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImageAsset {
    pub sha256: String,
    pub ext: String,
    pub width: u32,
    pub height: u32,
    pub byte_size: u64,
    pub blob_rel_path: String,
    pub thumb_rel_path: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecipeImageRef {
    pub sha256: String,
    pub ext: String,
    pub width: u32,
    pub height: u32,
    pub blob_rel_path: String,
    pub thumb_rel_path: String,
    #[serde(default)]
    pub caption: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StyleRecipe {
    pub id: String,
    pub title: String,
    pub schema_id: String,
    #[serde(default)]
    pub positive_nodes: Vec<PromptNode>,
    #[serde(default)]
    pub positive_raw: String,
    #[serde(default)]
    pub negative_nodes: Vec<PromptNode>,
    #[serde(default)]
    pub negative_raw: String,
    #[serde(default)]
    pub params: Map<String, Value>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub source_url: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub rating: u8,
    #[serde(default)]
    pub favorite: bool,
    #[serde(default)]
    pub images: Vec<RecipeImageRef>,
    #[serde(default)]
    pub created_at: i64,
    #[serde(default)]
    pub updated_at: i64,
    #[serde(default)]
    pub deleted: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct RecipeFilter {
    #[serde(default)]
    pub query: Option<String>,
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default)]
    pub schema_id: Option<String>,
    #[serde(default)]
    pub tag: Option<String>,
    #[serde(default)]
    pub favorite_only: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InspectedLora {
    pub name: String,
    pub weight: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InspectedStage {
    pub stage_name: String,
    pub positive_prompt: String,
    pub negative_prompt: String,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub sampler: Option<String>,
    #[serde(default)]
    pub scheduler: Option<String>,
    #[serde(default)]
    pub steps: Option<i64>,
    #[serde(default)]
    pub cfg: Option<f64>,
    #[serde(default)]
    pub seed: Option<String>,
    #[serde(default)]
    pub size: Option<String>,
    #[serde(default)]
    pub shift: Option<f64>,
    #[serde(default)]
    pub loras: Vec<InspectedLora>,
    #[serde(default)]
    pub extra_fields: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InspectionResult {
    pub source_kind: String,
    pub suggested_schema_id: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub stages: Vec<InspectedStage>,
    pub raw_metadata: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebDavConfig {
    pub preset: String,
    pub endpoint_url: String,
    pub username: String,
    pub password: String,
    pub remote_dir: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SyncReport {
    pub uploaded_blobs: usize,
    pub downloaded_blobs: usize,
    pub pushed_schemas: usize,
    pub pulled_schemas: usize,
    pub pushed_snippets: usize,
    pub pulled_snippets: usize,
    pub pushed_recipes: usize,
    pub pulled_recipes: usize,
    pub conflict_copies: usize,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncSnapshot {
    pub format_version: u32,
    pub exported_at: i64,
    pub schemas: Vec<PlatformSchema>,
    pub snippets: Vec<PromptSnippet>,
    pub recipes: Vec<StyleRecipe>,
    #[serde(default)]
    pub assets: Vec<ImageAsset>,
}
