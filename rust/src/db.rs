use crate::builtin_schemas::builtin_schemas;
use crate::models::{
    CoreError, CoreResult, ImageAsset, PlatformSchema, PromptNode, PromptSnippet, PromptSyntax,
    RecipeFilter, StyleRecipe, TargetSyntax,
};
use crate::prompt_ast::{nodes_to_editable_raw, parse_raw_to_nodes, render_for_copy};
use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::Duration;
use uuid::Uuid;

pub struct VaultDb {
    pub vault_dir: PathBuf,
    conn: Connection,
}

impl VaultDb {
    pub fn open(vault_dir: &Path) -> CoreResult<Self> {
        std::fs::create_dir_all(vault_dir)?;
        std::fs::create_dir_all(vault_dir.join("blobs"))?;
        std::fs::create_dir_all(vault_dir.join("thumbs"))?;

        let db_path = vault_dir.join("styleloom.db");
        let conn = Connection::open(db_path)?;
        conn.busy_timeout(Duration::from_secs(10))?;
        conn.execute_batch(
            "
            PRAGMA journal_mode = WAL;
            PRAGMA foreign_keys = ON;
            ",
        )?;

        let db = Self {
            vault_dir: vault_dir.to_path_buf(),
            conn,
        };
        db.migrate()?;
        db.seed_builtin_schemas()?;
        Ok(db)
    }

    fn migrate(&self) -> CoreResult<()> {
        self.conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS schemas (
                id TEXT PRIMARY KEY,
                platform TEXT NOT NULL,
                model_name TEXT NOT NULL,
                default_syntax TEXT NOT NULL,
                fields_json TEXT NOT NULL,
                is_builtin INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS snippets (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                categories_json TEXT NOT NULL,
                model_hint TEXT NOT NULL DEFAULT '',
                nodes_json TEXT NOT NULL,
                raw_text TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS recipes (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                schema_id TEXT NOT NULL,
                positive_nodes_json TEXT NOT NULL,
                positive_raw TEXT NOT NULL,
                negative_nodes_json TEXT NOT NULL,
                negative_raw TEXT NOT NULL,
                params_json TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                source_url TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                rating INTEGER NOT NULL DEFAULT 0,
                favorite INTEGER NOT NULL DEFAULT 0,
                images_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS recipes_fts USING fts5(
                id UNINDEXED,
                title,
                positive_raw,
                negative_raw,
                tags,
                notes
            );

            CREATE TABLE IF NOT EXISTS image_assets (
                sha256 TEXT PRIMARY KEY,
                ext TEXT NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                byte_size INTEGER NOT NULL,
                blob_rel_path TEXT NOT NULL,
                thumb_rel_path TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS kv_settings (
                key TEXT PRIMARY KEY,
                value_json TEXT NOT NULL
            );
            ",
        )?;
        Ok(())
    }

    fn seed_builtin_schemas(&self) -> CoreResult<()> {
        for schema in builtin_schemas() {
            let needs_refresh: Option<bool> = self
                .conn
                .query_row(
                    "SELECT is_builtin AND NOT deleted AND updated_at < ?2 FROM schemas WHERE id = ?1",
                    params![schema.id, schema.updated_at],
                    |r| r.get(0),
                )
                .optional()?;
            match needs_refresh {
                None => self.upsert_schema_raw(&schema)?,
                Some(true) => {
                    self.conn.execute(
                        "UPDATE schemas SET fields_json = ?3, updated_at = ?2
                         WHERE id = ?1 AND is_builtin AND NOT deleted AND updated_at < ?2",
                        params![schema.id, schema.updated_at, serde_json::to_string(&schema.fields)?],
                    )?;
                }
                Some(false) => (),
            }
        }
        Ok(())
    }

    pub fn upsert_schema_raw(&self, schema: &PlatformSchema) -> CoreResult<()> {
        let fields_json = serde_json::to_string(&schema.fields)?;
        self.conn.execute(
            "
            INSERT INTO schemas (id, platform, model_name, default_syntax, fields_json, is_builtin, updated_at, deleted)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(id) DO UPDATE SET
                platform = excluded.platform,
                model_name = excluded.model_name,
                default_syntax = excluded.default_syntax,
                fields_json = excluded.fields_json,
                is_builtin = excluded.is_builtin,
                updated_at = excluded.updated_at,
                deleted = excluded.deleted
            ",
            params![
                schema.id,
                schema.platform,
                schema.model_name,
                schema.default_syntax.as_str(),
                fields_json,
                if schema.is_builtin { 1 } else { 0 },
                schema.updated_at,
                if schema.deleted { 1 } else { 0 }
            ],
        )?;
        Ok(())
    }

    pub fn upsert_schema(&self, mut schema: PlatformSchema) -> CoreResult<PlatformSchema> {
        if schema.id.trim().is_empty() {
            schema.id = format!("custom_{}", Uuid::new_v4().simple());
        }
        let previous = self
            .get_schema(&schema.id)?
            .map(|s| s.updated_at)
            .unwrap_or(0);
        schema.updated_at = Utc::now().timestamp_millis().max(previous + 1);
        self.upsert_schema_raw(&schema)?;
        Ok(schema)
    }

    pub fn delete_schema(&self, id: &str) -> CoreResult<()> {
        let now = Utc::now()
            .timestamp_millis()
            .max(self.get_schema(id)?.map(|s| s.updated_at + 1).unwrap_or(0));
        let used: bool = self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM recipes WHERE schema_id = ?1 AND deleted = 0)",
            params![id],
            |r| r.get(0),
        )?;
        if used {
            return Err(CoreError::InvalidInput(
                "该模板仍被画师串使用，请先切换卡片的模型模板".into(),
            ));
        }
        self.conn.execute(
            "UPDATE schemas SET deleted = 1, updated_at = ?2 WHERE id = ?1 AND is_builtin = 0",
            params![id, now],
        )?;
        Ok(())
    }

    pub fn list_schemas(&self, include_deleted: bool) -> CoreResult<Vec<PlatformSchema>> {
        let sql = if include_deleted {
            "SELECT id, platform, model_name, default_syntax, fields_json, is_builtin, updated_at, deleted FROM schemas ORDER BY is_builtin DESC, platform ASC, model_name ASC"
        } else {
            "SELECT id, platform, model_name, default_syntax, fields_json, is_builtin, updated_at, deleted FROM schemas WHERE deleted = 0 ORDER BY is_builtin DESC, platform ASC, model_name ASC"
        };
        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map([], |row| {
            let syn_str: String = row.get(3)?;
            let fields_str: String = row.get(4)?;
            let fields = serde_json::from_str(&fields_str).unwrap_or_default();
            Ok(PlatformSchema {
                id: row.get(0)?,
                platform: row.get(1)?,
                model_name: row.get(2)?,
                default_syntax: PromptSyntax::from_str_lossy(&syn_str),
                fields,
                is_builtin: row.get::<_, i64>(5)? != 0,
                updated_at: row.get(6)?,
                deleted: row.get::<_, i64>(7)? != 0,
            })
        })?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r?);
        }
        Ok(out)
    }

    pub fn get_schema(&self, id: &str) -> CoreResult<Option<PlatformSchema>> {
        self.conn
            .query_row(
                "SELECT id, platform, model_name, default_syntax, fields_json, is_builtin, updated_at, deleted FROM schemas WHERE id = ?1",
                params![id],
                |row| {
                    let syn_str: String = row.get(3)?;
                    let fields_str: String = row.get(4)?;
                    let fields = serde_json::from_str(&fields_str).unwrap_or_default();
                    Ok(PlatformSchema {
                        id: row.get(0)?,
                        platform: row.get(1)?,
                        model_name: row.get(2)?,
                        default_syntax: PromptSyntax::from_str_lossy(&syn_str),
                        fields,
                        is_builtin: row.get::<_, i64>(5)? != 0,
                        updated_at: row.get(6)?,
                        deleted: row.get::<_, i64>(7)? != 0,
                    })
                },
            )
            .optional()
            .map_err(CoreError::from)
    }

    pub fn lookup_snippet_meta(&self, id_or_name: &str) -> Option<(String, String, String)> {
        self.conn
            .query_row(
                "SELECT id, name, raw_text FROM snippets WHERE id = ?1 OR (deleted = 0 AND lower(name) = lower(?1)) ORDER BY (id = ?1) DESC LIMIT 1",
                params![id_or_name],
                |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?)),
            )
            .optional()
            .ok()
            .flatten()
    }

    pub fn resolve_snippet_nodes(&self, id: &str) -> Option<(Vec<PromptNode>, String)> {
        self.conn
            .query_row(
                "SELECT nodes_json, raw_text FROM snippets WHERE deleted = 0 AND id = ?1",
                params![id],
                |r| {
                    let nj: String = r.get(0)?;
                    let rt: String = r.get(1)?;
                    let nodes: Vec<PromptNode> = serde_json::from_str(&nj).unwrap_or_default();
                    Ok((nodes, rt))
                },
            )
            .optional()
            .ok()
            .flatten()
    }

    pub fn upsert_snippet_raw(&self, snippet: &PromptSnippet) -> CoreResult<()> {
        self.conn.execute(
            "
            INSERT INTO snippets (id, name, categories_json, model_hint, nodes_json, raw_text, note, updated_at, deleted)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                categories_json = excluded.categories_json,
                model_hint = excluded.model_hint,
                nodes_json = excluded.nodes_json,
                raw_text = excluded.raw_text,
                note = excluded.note,
                updated_at = excluded.updated_at,
                deleted = excluded.deleted
            ",
            params![
                snippet.id,
                snippet.name,
                serde_json::to_string(&snippet.categories)?,
                snippet.model_hint,
                serde_json::to_string(&snippet.nodes)?,
                snippet.raw_text,
                snippet.note,
                snippet.updated_at,
                if snippet.deleted { 1 } else { 0 }
            ],
        )?;
        Ok(())
    }

    pub fn save_snippet(&self, mut snippet: PromptSnippet) -> CoreResult<PromptSnippet> {
        if snippet.id.trim().is_empty() {
            snippet.id = Uuid::new_v4().to_string();
        }
        if snippet.nodes.is_empty() && !snippet.raw_text.trim().is_empty() {
            snippet.nodes = parse_raw_to_nodes(&snippet.raw_text, &|q| self.lookup_snippet_meta(q));
        } else if !snippet.nodes.is_empty() {
            snippet.raw_text = nodes_to_editable_raw(&snippet.nodes, PromptSyntax::SdParens);
        }
        let previous = self
            .get_snippet(&snippet.id)?
            .map(|s| s.updated_at)
            .unwrap_or(0);
        snippet.updated_at = Utc::now().timestamp_millis().max(previous + 1);
        self.upsert_snippet_raw(&snippet)?;
        Ok(snippet)
    }

    pub fn delete_snippet(&self, id: &str) -> CoreResult<()> {
        let now = Utc::now()
            .timestamp_millis()
            .max(self.get_snippet(id)?.map(|s| s.updated_at + 1).unwrap_or(0));
        self.conn.execute(
            "UPDATE snippets SET deleted = 1, updated_at = ?2 WHERE id = ?1",
            params![id, now],
        )?;
        Ok(())
    }

    pub fn list_snippets(
        &self,
        query: Option<&str>,
        category: Option<&str>,
        include_deleted: bool,
    ) -> CoreResult<Vec<PromptSnippet>> {
        let sql = if include_deleted {
            "SELECT id, name, categories_json, model_hint, nodes_json, raw_text, note, updated_at, deleted FROM snippets ORDER BY updated_at DESC"
        } else {
            "SELECT id, name, categories_json, model_hint, nodes_json, raw_text, note, updated_at, deleted FROM snippets WHERE deleted = 0 ORDER BY updated_at DESC"
        };
        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map([], |row| {
            let cats: Vec<String> =
                serde_json::from_str(&row.get::<_, String>(2)?).unwrap_or_default();
            let nodes: Vec<PromptNode> =
                serde_json::from_str(&row.get::<_, String>(4)?).unwrap_or_default();
            Ok(PromptSnippet {
                id: row.get(0)?,
                name: row.get(1)?,
                categories: cats,
                model_hint: row.get(3)?,
                nodes,
                raw_text: row.get(5)?,
                note: row.get(6)?,
                updated_at: row.get(7)?,
                deleted: row.get::<_, i64>(8)? != 0,
            })
        })?;

        let q_lower = query
            .map(|s| s.trim().to_ascii_lowercase())
            .filter(|s| !s.is_empty());
        let cat_filter = category
            .map(|s| s.trim().to_ascii_lowercase())
            .filter(|s| !s.is_empty());

        let mut out = Vec::new();
        for r in rows {
            let item = r?;
            if let Some(ref c) = cat_filter {
                if !item
                    .categories
                    .iter()
                    .any(|ic| ic.to_ascii_lowercase() == *c)
                {
                    continue;
                }
            }
            if let Some(ref q) = q_lower {
                let hit = item.name.to_ascii_lowercase().contains(q)
                    || item.raw_text.to_ascii_lowercase().contains(q)
                    || item.note.to_ascii_lowercase().contains(q)
                    || item
                        .categories
                        .iter()
                        .any(|c| c.to_ascii_lowercase().contains(q));
                if !hit {
                    continue;
                }
            }
            out.push(item);
        }
        Ok(out)
    }

    pub fn get_snippet(&self, id: &str) -> CoreResult<Option<PromptSnippet>> {
        self.conn
            .query_row(
                "SELECT id, name, categories_json, model_hint, nodes_json, raw_text, note, updated_at, deleted FROM snippets WHERE id = ?1",
                params![id],
                |row| {
                    let cats: Vec<String> =
                        serde_json::from_str(&row.get::<_, String>(2)?).unwrap_or_default();
                    let nodes: Vec<PromptNode> =
                        serde_json::from_str(&row.get::<_, String>(4)?).unwrap_or_default();
                    Ok(PromptSnippet {
                        id: row.get(0)?,
                        name: row.get(1)?,
                        categories: cats,
                        model_hint: row.get(3)?,
                        nodes,
                        raw_text: row.get(5)?,
                        note: row.get(6)?,
                        updated_at: row.get(7)?,
                        deleted: row.get::<_, i64>(8)? != 0,
                    })
                },
            )
            .optional()
            .map_err(CoreError::from)
    }

    pub fn upsert_image_asset(&self, asset: &ImageAsset) -> CoreResult<()> {
        self.conn.execute(
            "
            INSERT INTO image_assets (sha256, ext, width, height, byte_size, blob_rel_path, thumb_rel_path, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(sha256) DO NOTHING
            ",
            params![
                asset.sha256,
                asset.ext,
                asset.width as i64,
                asset.height as i64,
                asset.byte_size as i64,
                asset.blob_rel_path,
                asset.thumb_rel_path,
                asset.created_at
            ],
        )?;
        Ok(())
    }

    pub fn list_image_assets(&self) -> CoreResult<Vec<ImageAsset>> {
        let mut stmt = self.conn.prepare(
            "SELECT sha256, ext, width, height, byte_size, blob_rel_path, thumb_rel_path, created_at FROM image_assets",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(ImageAsset {
                sha256: row.get(0)?,
                ext: row.get(1)?,
                width: row.get::<_, i64>(2)? as u32,
                height: row.get::<_, i64>(3)? as u32,
                byte_size: row.get::<_, i64>(4)? as u64,
                blob_rel_path: row.get(5)?,
                thumb_rel_path: row.get(6)?,
                created_at: row.get(7)?,
            })
        })?;
        let mut out = Vec::new();
        for r in rows {
            out.push(r?);
        }
        Ok(out)
    }

    fn refresh_recipe_fts(&self, recipe: &StyleRecipe) -> CoreResult<()> {
        self.conn
            .execute("DELETE FROM recipes_fts WHERE id = ?1", params![recipe.id])?;
        if !recipe.deleted {
            let tags_joined = recipe.tags.join(" ");
            self.conn.execute(
                "INSERT INTO recipes_fts (id, title, positive_raw, negative_raw, tags, notes) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    recipe.id,
                    recipe.title,
                    recipe.positive_raw,
                    recipe.negative_raw,
                    tags_joined,
                    recipe.notes
                ],
            )?;
        }
        Ok(())
    }

    pub fn upsert_recipe_raw(&self, recipe: &StyleRecipe) -> CoreResult<()> {
        let transaction = self.conn.unchecked_transaction()?;
        self.conn.execute(
            "
            INSERT INTO recipes (
                id, title, schema_id, positive_nodes_json, positive_raw,
                negative_nodes_json, negative_raw, params_json, tags_json,
                source_url, notes, rating, favorite, images_json,
                created_at, updated_at, deleted
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                schema_id = excluded.schema_id,
                positive_nodes_json = excluded.positive_nodes_json,
                positive_raw = excluded.positive_raw,
                negative_nodes_json = excluded.negative_nodes_json,
                negative_raw = excluded.negative_raw,
                params_json = excluded.params_json,
                tags_json = excluded.tags_json,
                source_url = excluded.source_url,
                notes = excluded.notes,
                rating = excluded.rating,
                favorite = excluded.favorite,
                images_json = excluded.images_json,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted = excluded.deleted
            ",
            params![
                recipe.id,
                recipe.title,
                recipe.schema_id,
                serde_json::to_string(&recipe.positive_nodes)?,
                recipe.positive_raw,
                serde_json::to_string(&recipe.negative_nodes)?,
                recipe.negative_raw,
                serde_json::to_string(&recipe.params)?,
                serde_json::to_string(&recipe.tags)?,
                recipe.source_url,
                recipe.notes,
                recipe.rating as i64,
                if recipe.favorite { 1 } else { 0 },
                serde_json::to_string(&recipe.images)?,
                recipe.created_at,
                recipe.updated_at,
                if recipe.deleted { 1 } else { 0 }
            ],
        )?;
        self.refresh_recipe_fts(recipe)?;
        transaction.commit()?;
        Ok(())
    }

    pub fn save_recipe(&self, mut recipe: StyleRecipe) -> CoreResult<StyleRecipe> {
        let now = Utc::now().timestamp();
        if recipe.id.trim().is_empty() {
            recipe.id = Uuid::new_v4().to_string();
            recipe.created_at = now;
        } else if recipe.created_at == 0 {
            recipe.created_at = now;
        }
        let previous = self
            .get_recipe(&recipe.id)?
            .map(|r| r.updated_at)
            .unwrap_or(0);
        recipe.updated_at = Utc::now().timestamp_millis().max(previous + 1);

        let syntax = self
            .get_schema(&recipe.schema_id)?
            .map(|s| s.default_syntax)
            .unwrap_or(PromptSyntax::SdParens);

        if recipe.positive_nodes.is_empty() && !recipe.positive_raw.trim().is_empty() {
            recipe.positive_nodes =
                parse_raw_to_nodes(&recipe.positive_raw, &|q| self.lookup_snippet_meta(q));
        } else if !recipe.positive_nodes.is_empty() {
            recipe.positive_raw = nodes_to_editable_raw(&recipe.positive_nodes, syntax);
        }

        if recipe.negative_nodes.is_empty() && !recipe.negative_raw.trim().is_empty() {
            recipe.negative_nodes =
                parse_raw_to_nodes(&recipe.negative_raw, &|q| self.lookup_snippet_meta(q));
        } else if !recipe.negative_nodes.is_empty() {
            recipe.negative_raw = nodes_to_editable_raw(&recipe.negative_nodes, syntax);
        }

        self.upsert_recipe_raw(&recipe)?;
        Ok(recipe)
    }

    pub fn delete_recipe(&self, id: &str) -> CoreResult<()> {
        let now = Utc::now()
            .timestamp_millis()
            .max(self.get_recipe(id)?.map(|r| r.updated_at + 1).unwrap_or(0));
        self.conn.execute(
            "UPDATE recipes SET deleted = 1, updated_at = ?2 WHERE id = ?1",
            params![id, now],
        )?;
        self.conn
            .execute("DELETE FROM recipes_fts WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn get_recipe(&self, id: &str) -> CoreResult<Option<StyleRecipe>> {
        self.conn
            .query_row(
                "SELECT id, title, schema_id, positive_nodes_json, positive_raw, negative_nodes_json, negative_raw, params_json, tags_json, source_url, notes, rating, favorite, images_json, created_at, updated_at, deleted FROM recipes WHERE id = ?1",
                params![id],
                |row| {
                    Ok(StyleRecipe {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        schema_id: row.get(2)?,
                        positive_nodes: serde_json::from_str(&row.get::<_, String>(3)?).unwrap_or_default(),
                        positive_raw: row.get(4)?,
                        negative_nodes: serde_json::from_str(&row.get::<_, String>(5)?).unwrap_or_default(),
                        negative_raw: row.get(6)?,
                        params: serde_json::from_str(&row.get::<_, String>(7)?).unwrap_or_default(),
                        tags: serde_json::from_str(&row.get::<_, String>(8)?).unwrap_or_default(),
                        source_url: row.get(9)?,
                        notes: row.get(10)?,
                        rating: row.get::<_, i64>(11)? as u8,
                        favorite: row.get::<_, i64>(12)? != 0,
                        images: serde_json::from_str(&row.get::<_, String>(13)?).unwrap_or_default(),
                        created_at: row.get(14)?,
                        updated_at: row.get(15)?,
                        deleted: row.get::<_, i64>(16)? != 0,
                    })
                },
            )
            .optional()
            .map_err(CoreError::from)
    }

    pub fn list_recipes(
        &self,
        filter: &RecipeFilter,
        include_deleted: bool,
    ) -> CoreResult<Vec<StyleRecipe>> {
        let schemas = self.list_schemas(true)?;
        let schema_platform_map: std::collections::HashMap<String, String> =
            schemas.into_iter().map(|s| (s.id, s.platform)).collect();

        let fts_ids: Option<HashSet<String>> = if let Some(ref q) = filter.query {
            let trimmed = q.trim();
            if trimmed.is_empty() {
                None
            } else {
                let fts_query = trimmed
                    .split_whitespace()
                    .map(|w| format!("\"{}\"*", w.replace('"', "")))
                    .collect::<Vec<_>>()
                    .join(" ");
                let mut ids = HashSet::new();
                if let Ok(mut stmt) = self
                    .conn
                    .prepare("SELECT id FROM recipes_fts WHERE recipes_fts MATCH ?1")
                {
                    if let Ok(rows) = stmt.query_map(params![fts_query], |r| r.get::<_, String>(0))
                    {
                        for id in rows.flatten() {
                            ids.insert(id);
                        }
                    }
                }
                Some(ids)
            }
        } else {
            None
        };

        let sql = if include_deleted {
            "SELECT id, title, schema_id, positive_nodes_json, positive_raw, negative_nodes_json, negative_raw, params_json, tags_json, source_url, notes, rating, favorite, images_json, created_at, updated_at, deleted FROM recipes ORDER BY favorite DESC, updated_at DESC"
        } else {
            "SELECT id, title, schema_id, positive_nodes_json, positive_raw, negative_nodes_json, negative_raw, params_json, tags_json, source_url, notes, rating, favorite, images_json, created_at, updated_at, deleted FROM recipes WHERE deleted = 0 ORDER BY favorite DESC, updated_at DESC"
        };
        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map([], |row| {
            Ok(StyleRecipe {
                id: row.get(0)?,
                title: row.get(1)?,
                schema_id: row.get(2)?,
                positive_nodes: serde_json::from_str(&row.get::<_, String>(3)?).unwrap_or_default(),
                positive_raw: row.get(4)?,
                negative_nodes: serde_json::from_str(&row.get::<_, String>(5)?).unwrap_or_default(),
                negative_raw: row.get(6)?,
                params: serde_json::from_str(&row.get::<_, String>(7)?).unwrap_or_default(),
                tags: serde_json::from_str(&row.get::<_, String>(8)?).unwrap_or_default(),
                source_url: row.get(9)?,
                notes: row.get(10)?,
                rating: row.get::<_, i64>(11)? as u8,
                favorite: row.get::<_, i64>(12)? != 0,
                images: serde_json::from_str(&row.get::<_, String>(13)?).unwrap_or_default(),
                created_at: row.get(14)?,
                updated_at: row.get(15)?,
                deleted: row.get::<_, i64>(16)? != 0,
            })
        })?;

        let q_lower = filter
            .query
            .as_deref()
            .map(|s| s.trim().to_ascii_lowercase())
            .filter(|s| !s.is_empty());

        let mut out = Vec::new();
        for r in rows {
            let item = r?;
            if filter.favorite_only && !item.favorite {
                continue;
            }
            if let Some(ref sid) = filter.schema_id {
                if !sid.is_empty() && item.schema_id != *sid {
                    continue;
                }
            }
            if let Some(ref plat) = filter.platform {
                if !plat.is_empty() {
                    let item_plat = schema_platform_map
                        .get(&item.schema_id)
                        .map(String::as_str)
                        .unwrap_or("");
                    if item_plat != plat {
                        continue;
                    }
                }
            }
            if let Some(ref tag) = filter.tag {
                if !tag.is_empty() && !item.tags.iter().any(|t| t == tag) {
                    continue;
                }
            }
            if let Some(ref q) = q_lower {
                let fts_match = fts_ids
                    .as_ref()
                    .map(|set| set.contains(&item.id))
                    .unwrap_or(false);
                let substr_match = item.title.to_ascii_lowercase().contains(q)
                    || item.positive_raw.to_ascii_lowercase().contains(q)
                    || item.negative_raw.to_ascii_lowercase().contains(q)
                    || item.notes.to_ascii_lowercase().contains(q)
                    || item.tags.iter().any(|t| t.to_ascii_lowercase().contains(q));
                if !fts_match && !substr_match {
                    continue;
                }
            }
            out.push(item);
        }
        Ok(out)
    }

    pub fn render_recipe_prompt(
        &self,
        recipe_id: &str,
        side: &str,
        target: TargetSyntax,
    ) -> CoreResult<String> {
        let recipe = self
            .get_recipe(recipe_id)?
            .ok_or_else(|| CoreError::NotFound(format!("Recipe {recipe_id}")))?;
        let model_syntax = self
            .get_schema(&recipe.schema_id)?
            .map(|s| s.default_syntax)
            .unwrap_or(PromptSyntax::SdParens);

        let nodes = if side == "negative" {
            &recipe.negative_nodes
        } else {
            &recipe.positive_nodes
        };

        Ok(render_for_copy(nodes, model_syntax, target, &|sid| {
            self.resolve_snippet_nodes(sid)
        }))
    }

    pub fn clone_recipe_to_schema(
        &self,
        source_id: &str,
        target_schema_id: &str,
        new_title: Option<String>,
    ) -> CoreResult<StyleRecipe> {
        let src = self
            .get_recipe(source_id)?
            .ok_or_else(|| CoreError::NotFound(format!("Recipe {source_id}")))?;
        let target_schema = self
            .get_schema(target_schema_id)?
            .ok_or_else(|| CoreError::NotFound(format!("Schema {target_schema_id}")))?;

        let mut new_params = serde_json::Map::new();
        for f in &target_schema.fields {
            if let Some(existing) = src.params.get(&f.key) {
                new_params.insert(f.key.clone(), existing.clone());
            } else {
                new_params.insert(f.key.clone(), f.default_value.clone());
            }
        }

        let cloned = StyleRecipe {
            id: String::new(),
            title: new_title
                .unwrap_or_else(|| format!("{} ({})", src.title, target_schema.model_name)),
            schema_id: target_schema.id,
            positive_nodes: src.positive_nodes.clone(),
            positive_raw: nodes_to_editable_raw(&src.positive_nodes, target_schema.default_syntax),
            negative_nodes: src.negative_nodes.clone(),
            negative_raw: nodes_to_editable_raw(&src.negative_nodes, target_schema.default_syntax),
            params: new_params,
            tags: src.tags,
            source_url: src.source_url,
            notes: src.notes,
            rating: src.rating,
            favorite: false,
            images: src.images,
            created_at: 0,
            updated_at: 0,
            deleted: false,
        };
        self.save_recipe(cloned)
    }

    pub fn set_setting(&self, key: &str, val: &serde_json::Value) -> CoreResult<()> {
        let json_str = serde_json::to_string(val)?;
        self.conn.execute(
            "INSERT INTO kv_settings (key, value_json) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json",
            params![key, json_str],
        )?;
        Ok(())
    }

    pub fn get_setting(&self, key: &str) -> CoreResult<Option<serde_json::Value>> {
        let opt: Option<String> = self
            .conn
            .query_row(
                "SELECT value_json FROM kv_settings WHERE key = ?1",
                params![key],
                |r| r.get(0),
            )
            .optional()?;
        match opt {
            Some(s) => Ok(Some(serde_json::from_str(&s)?)),
            None => Ok(None),
        }
    }
}
