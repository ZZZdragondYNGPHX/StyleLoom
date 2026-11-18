pub mod builtin_schemas;
pub mod db;
pub mod inspector;
pub mod media;
pub mod models;
pub mod prompt_ast;
pub mod sync;

use crate::db::VaultDb;
use crate::models::{
    CoreError, CoreResult, PlatformSchema, PromptNode, PromptSnippet, PromptSyntax, RecipeFilter,
    StyleRecipe, TargetSyntax, WebDavConfig,
};
use crate::prompt_ast::{nodes_to_editable_raw, parse_raw_to_nodes, render_for_copy, ungroup_snippet_node};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

#[derive(Debug, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum CoreRequest {
    InitVault {
        vault_dir: String,
    },
    ListSchemas {
        vault_dir: String,
    },
    UpsertSchema {
        vault_dir: String,
        schema: PlatformSchema,
    },
    DeleteSchema {
        vault_dir: String,
        id: String,
    },
    ListSnippets {
        vault_dir: String,
        query: Option<String>,
        category: Option<String>,
    },
    SaveSnippet {
        vault_dir: String,
        snippet: PromptSnippet,
    },
    DeleteSnippet {
        vault_dir: String,
        id: String,
    },
    ListRecipes {
        vault_dir: String,
        filter: RecipeFilter,
    },
    GetRecipe {
        vault_dir: String,
        id: String,
    },
    SaveRecipe {
        vault_dir: String,
        recipe: StyleRecipe,
    },
    DeleteRecipe {
        vault_dir: String,
        id: String,
    },
    CloneRecipeToSchema {
        vault_dir: String,
        source_id: String,
        target_schema_id: String,
        new_title: Option<String>,
    },
    ImportImageFile {
        vault_dir: String,
        file_path: String,
    },
    ImportImageBase64 {
        vault_dir: String,
        data_b64: String,
    },
    InspectFile {
        file_path: String,
    },
    ParseRawToNodes {
        vault_dir: String,
        raw: String,
    },
    NodesToRaw {
        nodes: Vec<PromptNode>,
        syntax: PromptSyntax,
    },
    RenderCopyNodes {
        vault_dir: String,
        nodes: Vec<PromptNode>,
        model_syntax: PromptSyntax,
        target_syntax: TargetSyntax,
    },
    RenderRecipePrompt {
        vault_dir: String,
        recipe_id: String,
        side: String,
        target_syntax: TargetSyntax,
    },
    UngroupSnippetNode {
        vault_dir: String,
        nodes: Vec<PromptNode>,
        node_id: String,
    },
    ExportSlpack {
        vault_dir: String,
        recipe_ids: Option<Vec<String>>,
        dest_path: String,
    },
    ImportSlpack {
        vault_dir: String,
        src_path: String,
    },
    GetSetting {
        vault_dir: String,
        key: String,
    },
    SetSetting {
        vault_dir: String,
        key: String,
        value: Value,
    },
    TestWebdav {
        config: WebDavConfig,
    },
    SyncWebdav {
        vault_dir: String,
        config: WebDavConfig,
    },
}

#[derive(Debug, Serialize)]
pub struct CoreResponse {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

pub fn dispatch_request(req: CoreRequest) -> CoreResult<Value> {
    match req {
        CoreRequest::InitVault { vault_dir } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let schemas = db.list_schemas(false)?;
            Ok(json!({ "schemas": schemas }))
        }
        CoreRequest::ListSchemas { vault_dir } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            Ok(serde_json::to_value(db.list_schemas(false)?)?)
        }
        CoreRequest::UpsertSchema { vault_dir, schema } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            Ok(serde_json::to_value(db.upsert_schema(schema)?)?)
        }
        CoreRequest::DeleteSchema { vault_dir, id } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            db.delete_schema(&id)?;
            Ok(json!({ "deleted": id }))
        }
        CoreRequest::ListSnippets {
            vault_dir,
            query,
            category,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            Ok(serde_json::to_value(db.list_snippets(
                query.as_deref(),
                category.as_deref(),
                false,
            )?)?)
        }
        CoreRequest::SaveSnippet { vault_dir, snippet } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            Ok(serde_json::to_value(db.save_snippet(snippet)?)?)
        }
        CoreRequest::DeleteSnippet { vault_dir, id } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            db.delete_snippet(&id)?;
            Ok(json!({ "deleted": id }))
        }
        CoreRequest::ListRecipes { vault_dir, filter } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            Ok(serde_json::to_value(db.list_recipes(&filter, false)?)?)
        }
        CoreRequest::GetRecipe { vault_dir, id } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let recipe = db
                .get_recipe(&id)?
                .ok_or_else(|| CoreError::NotFound(format!("Recipe {id}")))?;
            Ok(serde_json::to_value(recipe)?)
        }
        CoreRequest::SaveRecipe { vault_dir, recipe } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            Ok(serde_json::to_value(db.save_recipe(recipe)?)?)
        }
        CoreRequest::DeleteRecipe { vault_dir, id } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            db.delete_recipe(&id)?;
            Ok(json!({ "deleted": id }))
        }
        CoreRequest::CloneRecipeToSchema {
            vault_dir,
            source_id,
            target_schema_id,
            new_title,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            Ok(serde_json::to_value(db.clone_recipe_to_schema(
                &source_id,
                &target_schema_id,
                new_title,
            )?)?)
        }
        CoreRequest::ImportImageFile {
            vault_dir,
            file_path,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let bytes = std::fs::read(Path::new(&file_path))?;
            let asset = media::import_image_bytes(&db.vault_dir, &bytes)?;
            db.upsert_image_asset(&asset)?;
            Ok(serde_json::to_value(asset)?)
        }
        CoreRequest::ImportImageBase64 {
            vault_dir,
            data_b64,
        } => {
            use base64::engine::general_purpose::STANDARD;
            use base64::Engine;
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let bytes = STANDARD
                .decode(data_b64.trim())
                .map_err(|e| CoreError::InvalidInput(format!("Invalid base64: {e}")))?;
            let asset = media::import_image_bytes(&db.vault_dir, &bytes)?;
            db.upsert_image_asset(&asset)?;
            Ok(serde_json::to_value(asset)?)
        }
        CoreRequest::InspectFile { file_path } => {
            let bytes = std::fs::read(Path::new(&file_path))?;
            let res = inspector::inspect_media_or_json(&bytes, &file_path)?;
            Ok(serde_json::to_value(res)?)
        }
        CoreRequest::ParseRawToNodes { vault_dir, raw } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let nodes = parse_raw_to_nodes(&raw, &|q| db.lookup_snippet_meta(q));
            Ok(serde_json::to_value(nodes)?)
        }
        CoreRequest::NodesToRaw { nodes, syntax } => {
            let s = nodes_to_editable_raw(&nodes, syntax);
            Ok(json!({ "raw": s }))
        }
        CoreRequest::RenderCopyNodes {
            vault_dir,
            nodes,
            model_syntax,
            target_syntax,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let out = render_for_copy(&nodes, model_syntax, target_syntax, &|sid| {
                db.resolve_snippet_nodes(sid)
            });
            Ok(json!({ "text": out }))
        }
        CoreRequest::RenderRecipePrompt {
            vault_dir,
            recipe_id,
            side,
            target_syntax,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let out = db.render_recipe_prompt(&recipe_id, &side, target_syntax)?;
            Ok(json!({ "text": out }))
        }
        CoreRequest::UngroupSnippetNode {
            vault_dir,
            nodes,
            node_id,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let out = ungroup_snippet_node(&nodes, &node_id, &|sid| {
                db.resolve_snippet_nodes(sid)
            });
            Ok(serde_json::to_value(out)?)
        }
        CoreRequest::ExportSlpack {
            vault_dir,
            recipe_ids,
            dest_path,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let rep = sync::export_slpack(&db, recipe_ids, Path::new(&dest_path))?;
            Ok(serde_json::to_value(rep)?)
        }
        CoreRequest::ImportSlpack {
            vault_dir,
            src_path,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let rep = sync::import_slpack(&db, Path::new(&src_path))?;
            Ok(serde_json::to_value(rep)?)
        }
        CoreRequest::GetSetting { vault_dir, key } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            Ok(db.get_setting(&key)?.unwrap_or(Value::Null))
        }
        CoreRequest::SetSetting {
            vault_dir,
            key,
            value,
        } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            db.set_setting(&key, &value)?;
            Ok(json!({ "saved": true }))
        }
        CoreRequest::TestWebdav { config } => {
            let msg = sync::test_webdav(&config)?;
            Ok(json!({ "message": msg }))
        }
        CoreRequest::SyncWebdav { vault_dir, config } => {
            let db = VaultDb::open(Path::new(&vault_dir))?;
            let rep = sync::sync_webdav(&db, &config)?;
            Ok(serde_json::to_value(rep)?)
        }
    }
}

pub fn invoke_json_str(request_json: &str) -> String {
    let res = std::panic::catch_unwind(|| -> CoreResult<Value> {
        let req: CoreRequest = serde_json::from_str(request_json)?;
        dispatch_request(req)
    });

    let resp = match res {
        Ok(Ok(data)) => CoreResponse {
            ok: true,
            data: Some(data),
            error: None,
        },
        Ok(Err(e)) => CoreResponse {
            ok: false,
            data: None,
            error: Some(e.to_string()),
        },
        Err(_) => CoreResponse {
            ok: false,
            data: None,
            error: Some("Rust core panic caught safely".into()),
        },
    };
    serde_json::to_string(&resp).unwrap_or_else(|_| {
        "{\"ok\":false,\"error\":\"Failed to serialize CoreResponse\"}".to_string()
    })
}

fn to_c_string_ptr(s: String) -> *mut c_char {
    let sanitized = s.replace('\0', " ");
    match CString::new(sanitized) {
        Ok(cs) => cs.into_raw(),
        Err(_) => CString::new("{\"ok\":false,\"error\":\"CString error\"}")
            .unwrap()
            .into_raw(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn styleloom_invoke_json(request_ptr: *const c_char) -> *mut c_char {
    if request_ptr.is_null() {
        return to_c_string_ptr(
            "{\"ok\":false,\"error\":\"Null request pointer\"}".to_string(),
        );
    }
    let c_str = CStr::from_ptr(request_ptr);
    let req_str = match c_str.to_str() {
        Ok(s) => s,
        Err(e) => {
            return to_c_string_ptr(format!(
                "{{\"ok\":false,\"error\":\"Invalid UTF-8 request: {e}\"}}"
            ));
        }
    };
    to_c_string_ptr(invoke_json_str(req_str))
}

#[no_mangle]
pub unsafe extern "C" fn styleloom_inspect_bytes(
    bytes_ptr: *const u8,
    len: usize,
    hint_ptr: *const c_char,
) -> *mut c_char {
    let hint = if hint_ptr.is_null() {
        ""
    } else {
        CStr::from_ptr(hint_ptr).to_str().unwrap_or("")
    };
    if bytes_ptr.is_null() || len == 0 {
        return to_c_string_ptr(
            "{\"ok\":false,\"error\":\"Empty bytes buffer\"}".to_string(),
        );
    }
    let slice = std::slice::from_raw_parts(bytes_ptr, len);
    let resp = match std::panic::catch_unwind(|| inspector::inspect_media_or_json(slice, hint)) {
        Ok(Ok(data)) => CoreResponse {
            ok: true,
            data: serde_json::to_value(data).ok(),
            error: None,
        },
        Ok(Err(e)) => CoreResponse {
            ok: false,
            data: None,
            error: Some(e.to_string()),
        },
        Err(_) => CoreResponse {
            ok: false,
            data: None,
            error: Some("Rust inspect panic caught safely".into()),
        },
    };
    to_c_string_ptr(serde_json::to_string(&resp).unwrap())
}

#[no_mangle]
pub unsafe extern "C" fn styleloom_free_buf(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}
