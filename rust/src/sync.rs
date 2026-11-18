use crate::db::VaultDb;
use crate::media;
use crate::models::{
    CoreError, CoreResult, ImageAsset, PlatformSchema, PromptSnippet, StyleRecipe, SyncReport,
    SyncSnapshot, WebDavConfig,
};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use chrono::Utc;
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use quick_xml::events::Event;
use quick_xml::Reader;
use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{Read, Write};
use std::path::Path;
use std::time::Duration;
use uuid::Uuid;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipArchive, ZipWriter};

fn validate_snapshot(snapshot: &SyncSnapshot) -> CoreResult<()> {
    if snapshot.format_version != 1 {
        return Err(CoreError::Sync(format!(
            "不支持的备份版本：{}",
            snapshot.format_version
        )));
    }
    for recipe in &snapshot.recipes {
        for image in &recipe.images {
            validate_image_paths(
                &image.sha256,
                &image.ext,
                &image.blob_rel_path,
                &image.thumb_rel_path,
            )?;
        }
    }
    for asset in &snapshot.assets {
        validate_image_paths(
            &asset.sha256,
            &asset.ext,
            &asset.blob_rel_path,
            &asset.thumb_rel_path,
        )?;
    }
    Ok(())
}

fn validate_image_paths(sha: &str, ext: &str, blob: &str, thumb: &str) -> CoreResult<()> {
    if sha.len() != 64
        || !sha
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        || !matches!(ext, "png" | "jpg" | "webp")
    {
        return Err(CoreError::Sync("备份中的图片标识无效".into()));
    }
    let prefix = &sha[..2];
    if blob != format!("blobs/{prefix}/{sha}.{ext}")
        || (thumb != format!("thumbs/{prefix}/{sha}.png")
            && thumb != format!("thumbs/{prefix}/{sha}.jpg"))
    {
        return Err(CoreError::Sync("备份中的图片路径无效".into()));
    }
    Ok(())
}

fn read_limited(reader: impl Read, limit: u64) -> CoreResult<Vec<u8>> {
    let mut bytes = Vec::new();
    reader.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return Err(CoreError::Sync("备份内容超过支持的大小".into()));
    }
    Ok(bytes)
}

fn resolve_snippet_ids_recursive(
    db: &VaultDb,
    recipes: &[StyleRecipe],
) -> CoreResult<Vec<PromptSnippet>> {
    let all_snippets = db.list_snippets(None, None, false)?;
    let by_id: HashMap<String, PromptSnippet> = all_snippets
        .into_iter()
        .map(|s| (s.id.clone(), s))
        .collect();

    let mut needed = HashSet::new();
    let mut queue = Vec::new();
    for r in recipes {
        for n in r.positive_nodes.iter().chain(r.negative_nodes.iter()) {
            if let crate::models::PromptNode::SnippetRef { snippet_id, .. } = n {
                if !snippet_id.is_empty() && needed.insert(snippet_id.clone()) {
                    queue.push(snippet_id.clone());
                }
            }
        }
    }
    let mut depth = 0;
    while !queue.is_empty() && depth < 4 {
        let cur = std::mem::take(&mut queue);
        for sid in cur {
            if let Some(sn) = by_id.get(&sid) {
                for n in &sn.nodes {
                    if let crate::models::PromptNode::SnippetRef { snippet_id, .. } = n {
                        if !snippet_id.is_empty() && needed.insert(snippet_id.clone()) {
                            queue.push(snippet_id.clone());
                        }
                    }
                }
            }
        }
        depth += 1;
    }

    Ok(needed
        .into_iter()
        .filter_map(|id| by_id.get(&id).cloned())
        .collect())
}

pub fn export_slpack(
    db: &VaultDb,
    recipe_ids: Option<Vec<String>>,
    dest_path: &Path,
) -> CoreResult<SyncReport> {
    let (schemas, snippets, recipes) = match recipe_ids {
        None => (
            db.list_schemas(false)?,
            db.list_snippets(None, None, false)?,
            db.list_recipes(&Default::default(), false)?,
        ),
        Some(ids) => {
            let id_set: HashSet<String> = ids.into_iter().collect();
            let all_recipes = db.list_recipes(&Default::default(), false)?;
            let selected_recipes: Vec<StyleRecipe> = all_recipes
                .into_iter()
                .filter(|r| id_set.contains(&r.id))
                .collect();
            let schema_ids: HashSet<String> = selected_recipes
                .iter()
                .map(|r| r.schema_id.clone())
                .collect();
            let schemas: Vec<PlatformSchema> = db
                .list_schemas(false)?
                .into_iter()
                .filter(|s| schema_ids.contains(&s.id))
                .collect();
            let snippets = resolve_snippet_ids_recursive(db, &selected_recipes)?;
            (schemas, snippets, selected_recipes)
        }
    };

    let mut asset_map: HashMap<String, ImageAsset> = db
        .list_image_assets()?
        .into_iter()
        .map(|a| (a.sha256.clone(), a))
        .collect();

    let mut blob_entries: Vec<(String, String)> = Vec::new();
    let mut seen_sha = HashSet::new();
    for r in &recipes {
        for img in &r.images {
            if seen_sha.insert(img.sha256.clone()) {
                blob_entries.push((img.sha256.clone(), img.blob_rel_path.clone()));
                asset_map
                    .entry(img.sha256.clone())
                    .or_insert_with(|| ImageAsset {
                        sha256: img.sha256.clone(),
                        ext: img.ext.clone(),
                        width: img.width,
                        height: img.height,
                        byte_size: 0,
                        blob_rel_path: img.blob_rel_path.clone(),
                        thumb_rel_path: img.thumb_rel_path.clone(),
                        created_at: r.created_at,
                    });
            }
        }
    }

    let snapshot = SyncSnapshot {
        format_version: 1,
        exported_at: Utc::now().timestamp(),
        schemas: schemas.clone(),
        snippets: snippets.clone(),
        recipes: recipes.clone(),
        assets: seen_sha
            .iter()
            .filter_map(|sha| asset_map.get(sha).cloned())
            .collect(),
    };

    validate_snapshot(&snapshot)?;
    for (_, rel_path) in &blob_entries {
        if !db.vault_dir.join(rel_path).is_file() {
            return Err(CoreError::Sync(format!(
                "原图缺失，无法导出完整备份：{rel_path}"
            )));
        }
    }

    if let Some(parent) = dest_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let file = File::create(dest_path)?;
    let mut zip = ZipWriter::new(file);
    let opts = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);

    zip.start_file("manifest.json", opts)
        .map_err(|e| CoreError::Sync(e.to_string()))?;
    let manifest_bytes = serde_json::to_vec_pretty(&snapshot)?;
    zip.write_all(&manifest_bytes)?;

    let mut uploaded_blobs = 0usize;
    for (sha, rel_path) in &blob_entries {
        let abs = db.vault_dir.join(rel_path);
        if abs.exists() {
            let ext = Path::new(rel_path)
                .extension()
                .and_then(|s| s.to_str())
                .unwrap_or("png");
            zip.start_file(format!("blobs/{sha}.{ext}"), opts)
                .map_err(|e| CoreError::Sync(e.to_string()))?;
            let bytes = std::fs::read(abs)?;
            zip.write_all(&bytes)?;
            uploaded_blobs += 1;
        }
    }

    zip.finish().map_err(|e| CoreError::Sync(e.to_string()))?;

    Ok(SyncReport {
        uploaded_blobs,
        pushed_schemas: schemas.len(),
        pushed_snippets: snippets.len(),
        pushed_recipes: recipes.len(),
        message: format!(
            "已导出 .slpack：{} 张画师串卡片、{} 条提示词预设、{} 张图片",
            recipes.len(),
            snippets.len(),
            uploaded_blobs
        ),
        ..Default::default()
    })
}

pub fn import_slpack(db: &VaultDb, src_path: &Path) -> CoreResult<SyncReport> {
    let file = File::open(src_path)?;
    let mut zip = ZipArchive::new(file).map_err(|e| CoreError::Sync(e.to_string()))?;

    let manifest_bytes = {
        let mf = zip
            .by_name("manifest.json")
            .map_err(|_| CoreError::Sync("无效的 .slpack 文件：缺少 manifest.json".into()))?;
        read_limited(mf, 32 * 1024 * 1024)?
    };
    let mut snapshot: SyncSnapshot = serde_json::from_slice(&manifest_bytes)?;
    validate_snapshot(&snapshot)?;

    let mut report = SyncReport::default();

    // Import blobs first (deduplicating via sha256)
    let names: Vec<String> = (0..zip.len())
        .filter_map(|i| zip.by_index(i).ok().map(|f| f.name().to_string()))
        .collect();
    let mut available = db
        .list_image_assets()?
        .into_iter()
        .filter(|a| db.vault_dir.join(&a.blob_rel_path).is_file())
        .map(|a| a.sha256)
        .collect::<HashSet<_>>();
    let mut blob_names = Vec::new();
    for name in names {
        if name.starts_with("blobs/") && !name.ends_with('/') {
            let zf = zip
                .by_name(&name)
                .map_err(|e| CoreError::Sync(e.to_string()))?;
            let bytes = read_limited(zf, 256 * 1024 * 1024)?;
            let sha = media::sha256_hex(&bytes);
            let claimed_sha = name
                .strip_prefix("blobs/")
                .unwrap_or("")
                .split('.')
                .next()
                .unwrap_or("");
            if sha != claimed_sha {
                return Err(CoreError::Sync(format!("备份图片校验失败：{name}")));
            }
            available.insert(sha);
            blob_names.push(name);
        }
    }
    for recipe in &snapshot.recipes {
        if !recipe.deleted
            && recipe
                .images
                .iter()
                .any(|img| !available.contains(&img.sha256))
        {
            return Err(CoreError::Sync(format!(
                "备份缺少「{}」的原图",
                recipe.title
            )));
        }
    }
    for name in blob_names {
        let zf = zip
            .by_name(&name)
            .map_err(|e| CoreError::Sync(e.to_string()))?;
        let bytes = read_limited(zf, 256 * 1024 * 1024)?;
        let asset = media::import_image_bytes(&db.vault_dir, &bytes)?;
        db.upsert_image_asset(&asset)?;
        report.downloaded_blobs += 1;
    }
    let assets: HashMap<_, _> = db
        .list_image_assets()?
        .into_iter()
        .map(|a| (a.sha256.clone(), a))
        .collect();
    for recipe in &mut snapshot.recipes {
        normalize_recipe_images(recipe, &assets);
    }

    for s in snapshot.schemas {
        let local = db.get_schema(&s.id)?;
        if local.map(|l| s.updated_at > l.updated_at).unwrap_or(true) {
            db.upsert_schema_raw(&s)?;
            report.pulled_schemas += 1;
        }
    }

    for sn in snapshot.snippets {
        let local = db.get_snippet(&sn.id)?;
        if local.map(|l| sn.updated_at > l.updated_at).unwrap_or(true) {
            db.upsert_snippet_raw(&sn)?;
            report.pulled_snippets += 1;
        }
    }

    for r in snapshot.recipes {
        let local = db.get_recipe(&r.id)?;
        match local {
            None => {
                db.upsert_recipe_raw(&r)?;
                report.pulled_recipes += 1;
            }
            Some(l) if r.updated_at > l.updated_at => {
                db.upsert_recipe_raw(&r)?;
                report.pulled_recipes += 1;
            }
            _ => {}
        }
    }

    report.message = format!(
        "已导入 .slpack：{} 张画师串卡片、{} 条提示词预设、{} 张图片",
        report.pulled_recipes, report.pulled_snippets, report.downloaded_blobs
    );
    Ok(report)
}

fn normalized_endpoint(cfg: &WebDavConfig) -> CoreResult<String> {
    let base = if cfg.preset == "koofr" && cfg.endpoint_url.trim().is_empty() {
        "https://app.koofr.net/dav/Koofr"
    } else {
        cfg.endpoint_url.trim()
    };
    if base.is_empty() {
        return Err(CoreError::InvalidInput("WebDAV 地址不能为空".into()));
    }
    Ok(base.trim_end_matches('/').to_string())
}

fn normalized_remote_dir(cfg: &WebDavConfig) -> CoreResult<String> {
    let clean = cfg.remote_dir.trim().trim_matches('/');
    let clean = if clean.is_empty() { "StyleLoom" } else { clean };
    let mut segments = Vec::new();
    for segment in clean.split('/').filter(|s| !s.is_empty()) {
        if matches!(segment, "." | "..") {
            return Err(CoreError::InvalidInput("同步目录不能包含 . 或 ..".into()));
        }
        let encoded: String = segment
            .bytes()
            .map(|b| {
                if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
                    (b as char).to_string()
                } else {
                    format!("%{b:02X}")
                }
            })
            .collect();
        segments.push(encoded);
    }
    Ok(segments.join("/"))
}

fn ensure_sync_root(
    agent: &ureq::Agent,
    auth: &str,
    base: &str,
    rdir: &str,
    is_koofr: bool,
) -> CoreResult<String> {
    let mut root = base.to_string();
    for segment in rdir.split('/') {
        root.push('/');
        root.push_str(segment);
        ensure_remote_dir(agent, auth, &root, is_koofr)?;
    }
    Ok(root)
}

fn auth_header(cfg: &WebDavConfig) -> String {
    let token = B64.encode(format!("{}:{}", cfg.username.trim(), cfg.password));
    format!("Basic {token}")
}

fn webdav_agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(30))
        .build()
}

fn map_ureq_err(err: ureq::Error, is_koofr: bool) -> CoreError {
    match err {
        ureq::Error::Status(401, _) => CoreError::Sync(if is_koofr {
            "WebDAV 认证失败 (401)：Koofr 请填写注册邮箱，并使用后台生成的「应用专用密码 (App Password)」而非主密码".into()
        } else {
            "WebDAV 认证失败 (401)：请检查用户名与密码/应用专用密码".into()
        }),
        ureq::Error::Status(403, _) => {
            CoreError::Sync("WebDAV 权限不足 (403)：请检查目标路径是否具备读写权限（Koofr 请使用 /dav/Koofr 而非只读根目录 /dav/）".into())
        }
        ureq::Error::Status(code, resp) => {
            CoreError::Sync(format!("WebDAV HTTP 错误 ({code}): {}", resp.status_text()))
        }
        ureq::Error::Transport(t) => CoreError::Sync(format!("WebDAV 网络连接失败: {t}")),
    }
}

fn ensure_remote_dir(agent: &ureq::Agent, auth: &str, url: &str, is_koofr: bool) -> CoreResult<()> {
    match agent
        .request("MKCOL", url)
        .set("Authorization", auth)
        .call()
    {
        Ok(_) => Ok(()),
        Err(ureq::Error::Status(405, _)) => Ok(()),
        Err(e) => Err(map_ureq_err(e, is_koofr)),
    }
}

fn parse_propfind_names(xml_text: &str) -> HashSet<String> {
    let mut reader = Reader::from_str(xml_text);
    reader.config_mut().trim_text(true);
    let mut in_href = false;
    let mut names = HashSet::new();

    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) => {
                let local = e.local_name();
                if local.as_ref().eq_ignore_ascii_case(b"href") {
                    in_href = true;
                }
            }
            Ok(Event::End(e)) => {
                let local = e.local_name();
                if local.as_ref().eq_ignore_ascii_case(b"href") {
                    in_href = false;
                }
            }
            Ok(Event::Text(t)) if in_href => {
                if let Ok(raw) = t.unescape() {
                    let s = raw.trim().trim_end_matches('/');
                    if let Some(last) = s.rsplit('/').next() {
                        if !last.is_empty() && last.contains('.') {
                            names.insert(last.to_string());
                        }
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
    }
    names
}

pub fn test_webdav(cfg: &WebDavConfig) -> CoreResult<String> {
    let base = normalized_endpoint(cfg)?;
    let auth = auth_header(cfg);
    let agent = webdav_agent();
    let is_koofr = cfg.preset == "koofr" || base.contains("koofr.net");

    let resp = agent
        .request("PROPFIND", &format!("{base}/"))
        .set("Authorization", &auth)
        .set("Depth", "0")
        .call()
        .map_err(|e| map_ureq_err(e, is_koofr))?;

    let status = resp.status();
    let rdir = normalized_remote_dir(cfg)?;
    ensure_sync_root(&agent, &auth, &base, &rdir, is_koofr)?;
    Ok(format!(
        "WebDAV 连接成功 (HTTP {status})，已就绪同步目录：/{rdir}"
    ))
}

fn fetch_remote_snapshot(
    agent: &ureq::Agent,
    auth: &str,
    snapshot_url: &str,
    is_koofr: bool,
) -> CoreResult<(Option<SyncSnapshot>, Option<String>)> {
    match agent.get(snapshot_url).set("Authorization", auth).call() {
        Ok(resp) => {
            let etag = resp.header("ETag").map(str::to_string);
            let compressed = read_limited(resp.into_reader(), 32 * 1024 * 1024)?;
            let dec = GzDecoder::new(compressed.as_slice());
            let json_bytes = read_limited(dec, 32 * 1024 * 1024)?;
            let snap: SyncSnapshot = serde_json::from_slice(&json_bytes)?;
            validate_snapshot(&snap)?;
            Ok((Some(snap), etag))
        }
        Err(ureq::Error::Status(404, _)) => Ok((None, None)),
        Err(e) => Err(map_ureq_err(e, is_koofr)),
    }
}

pub fn sync_webdav(db: &VaultDb, cfg: &WebDavConfig) -> CoreResult<SyncReport> {
    let base = normalized_endpoint(cfg)?;
    let rdir = normalized_remote_dir(cfg)?;
    let auth = auth_header(cfg);
    let agent = webdav_agent();
    let is_koofr = cfg.preset == "koofr" || base.contains("koofr.net");

    let root_url = ensure_sync_root(&agent, &auth, &base, &rdir, is_koofr)?;
    let blobs_url = format!("{root_url}/blobs");
    let records_url = format!("{root_url}/records");
    let snapshot_url = format!("{records_url}/snapshot.json.gz");

    ensure_remote_dir(&agent, &auth, &blobs_url, is_koofr)?;
    ensure_remote_dir(&agent, &auth, &records_url, is_koofr)?;

    // 1. List existing remote blobs
    let prop_resp = agent
        .request("PROPFIND", &format!("{blobs_url}/"))
        .set("Authorization", &auth)
        .set("Depth", "1")
        .call()
        .map_err(|e| map_ureq_err(e, is_koofr))?;
    let prop_xml = prop_resp.into_string()?;
    let remote_blobs = parse_propfind_names(&prop_xml);

    // 2. Fetch remote snapshot
    let (remote_snap_opt, remote_etag) =
        fetch_remote_snapshot(&agent, &auth, &snapshot_url, is_koofr)?;
    let remote_exists = remote_snap_opt.is_some();
    let sync_key = format!("webdav_last_sync:{root_url}");
    let last_sync_at = db
        .get_setting(&sync_key)?
        .and_then(|v| v.as_i64())
        .unwrap_or(0);

    let mut report = SyncReport::default();

    // 3. Upload local image blobs missing on remote
    let local_assets = db.list_image_assets()?;
    for asset in &local_assets {
        let filename = format!("{}.{}", asset.sha256, asset.ext);
        if !remote_blobs.contains(&filename) {
            let abs = db.vault_dir.join(&asset.blob_rel_path);
            if abs.exists() {
                let bytes = std::fs::read(&abs)?;
                agent
                    .put(&format!("{blobs_url}/{filename}"))
                    .set("Authorization", &auth)
                    .set("Content-Type", "application/octet-stream")
                    .send_bytes(&bytes)
                    .map_err(|e| map_ureq_err(e, is_koofr))?;
                report.uploaded_blobs += 1;
            }
        }
    }

    // 4. Merge schemas, snippets, recipes
    let local_schemas: HashMap<String, PlatformSchema> = db
        .list_schemas(true)?
        .into_iter()
        .map(|s| (s.id.clone(), s))
        .collect();
    let local_snippets: HashMap<String, PromptSnippet> = db
        .list_snippets(None, None, true)?
        .into_iter()
        .map(|s| (s.id.clone(), s))
        .collect();
    let local_recipes: HashMap<String, StyleRecipe> = db
        .list_recipes(&Default::default(), true)?
        .into_iter()
        .map(|r| (r.id.clone(), r))
        .collect();

    let mut merged_schemas = local_schemas.clone();
    let mut merged_snippets = local_snippets.clone();
    let mut merged_recipes = local_recipes.clone();

    if let Some(rsnap) = remote_snap_opt {
        let remote_schema_ids: HashSet<_> = rsnap.schemas.iter().map(|s| &s.id).collect();
        let remote_snippet_ids: HashSet<_> = rsnap.snippets.iter().map(|s| &s.id).collect();
        let remote_recipe_ids: HashSet<_> = rsnap.recipes.iter().map(|r| &r.id).collect();
        report.pushed_schemas = local_schemas
            .keys()
            .filter(|id| !remote_schema_ids.contains(id))
            .count();
        report.pushed_snippets = local_snippets
            .keys()
            .filter(|id| !remote_snippet_ids.contains(id))
            .count();
        report.pushed_recipes = local_recipes
            .keys()
            .filter(|id| !remote_recipe_ids.contains(id))
            .count();
        for rs in rsnap.schemas {
            match local_schemas.get(&rs.id) {
                None => {
                    db.upsert_schema_raw(&rs)?;
                    merged_schemas.insert(rs.id.clone(), rs);
                    report.pulled_schemas += 1;
                }
                Some(ls) if rs.updated_at > ls.updated_at => {
                    db.upsert_schema_raw(&rs)?;
                    merged_schemas.insert(rs.id.clone(), rs);
                    report.pulled_schemas += 1;
                }
                Some(ls) if ls.updated_at > rs.updated_at => {
                    report.pushed_schemas += 1;
                }
                _ => {}
            }
        }

        for rsn in rsnap.snippets {
            match local_snippets.get(&rsn.id) {
                None => {
                    db.upsert_snippet_raw(&rsn)?;
                    merged_snippets.insert(rsn.id.clone(), rsn);
                    report.pulled_snippets += 1;
                }
                Some(lsn) if rsn != *lsn => {
                    let both_modified = last_sync_at > 0
                        && lsn.updated_at > last_sync_at
                        && rsn.updated_at > last_sync_at
                        && !lsn.deleted
                        && !rsn.deleted;
                    if both_modified {
                        // Preserve loser as conflict copy
                        let mut conflict = if rsn.updated_at >= lsn.updated_at {
                            lsn.clone()
                        } else {
                            rsn.clone()
                        };
                        conflict.id = Uuid::new_v4().to_string();
                        conflict.name = format!("{} (冲突副本)", conflict.name);
                        conflict.updated_at = Utc::now().timestamp_millis();
                        db.upsert_snippet_raw(&conflict)?;
                        merged_snippets.insert(conflict.id.clone(), conflict);
                        report.conflict_copies += 1;
                    }
                    if rsn.updated_at >= lsn.updated_at {
                        db.upsert_snippet_raw(&rsn)?;
                        merged_snippets.insert(rsn.id.clone(), rsn);
                        report.pulled_snippets += 1;
                    } else {
                        report.pushed_snippets += 1;
                    }
                }
                _ => {}
            }
        }

        for rr in rsnap.recipes {
            match local_recipes.get(&rr.id) {
                None => {
                    db.upsert_recipe_raw(&rr)?;
                    merged_recipes.insert(rr.id.clone(), rr);
                    report.pulled_recipes += 1;
                }
                Some(lr) if rr != *lr => {
                    let both_modified = last_sync_at > 0
                        && lr.updated_at > last_sync_at
                        && rr.updated_at > last_sync_at
                        && !lr.deleted
                        && !rr.deleted;
                    if both_modified {
                        let mut conflict = if rr.updated_at >= lr.updated_at {
                            lr.clone()
                        } else {
                            rr.clone()
                        };
                        conflict.id = Uuid::new_v4().to_string();
                        conflict.title = format!("{} (冲突副本)", conflict.title);
                        conflict.updated_at = Utc::now().timestamp_millis();
                        db.upsert_recipe_raw(&conflict)?;
                        merged_recipes.insert(conflict.id.clone(), conflict);
                        report.conflict_copies += 1;
                    }
                    if rr.updated_at >= lr.updated_at {
                        db.upsert_recipe_raw(&rr)?;
                        merged_recipes.insert(rr.id.clone(), rr);
                        report.pulled_recipes += 1;
                    } else {
                        report.pushed_recipes += 1;
                    }
                }
                _ => {}
            }
        }
    } else {
        report.pushed_schemas = merged_schemas.len();
        report.pushed_snippets = merged_snippets.len();
        report.pushed_recipes = merged_recipes.len();
    }

    // 5. Download missing blobs referenced by active merged recipes
    let local_sha_set: HashSet<String> = db
        .list_image_assets()?
        .into_iter()
        .filter(|a| {
            db.vault_dir.join(&a.blob_rel_path).is_file()
                && db.vault_dir.join(&a.thumb_rel_path).is_file()
        })
        .map(|a| a.sha256)
        .collect();
    let mut downloaded_set = HashSet::new();
    for recipe in merged_recipes.values() {
        if recipe.deleted {
            continue;
        }
        for img in &recipe.images {
            if !local_sha_set.contains(&img.sha256) && downloaded_set.insert(img.sha256.clone()) {
                let filename = format!("{}.{}", img.sha256, img.ext);
                let resp = agent
                    .get(&format!("{blobs_url}/{filename}"))
                    .set("Authorization", &auth)
                    .call()
                    .map_err(|e| map_ureq_err(e, is_koofr))?;
                let bytes = read_limited(resp.into_reader(), 256 * 1024 * 1024)?;
                if media::sha256_hex(&bytes) != img.sha256 {
                    return Err(CoreError::Sync(format!("远端图片校验失败：{filename}")));
                }
                let asset = media::import_image_bytes(&db.vault_dir, &bytes)?;
                db.upsert_image_asset(&asset)?;
                report.downloaded_blobs += 1;
            }
        }
    }

    // 6. Push merged snapshot back to WebDAV
    let final_assets = db.list_image_assets()?;
    let asset_map: HashMap<_, _> = final_assets
        .iter()
        .map(|a| (a.sha256.clone(), a.clone()))
        .collect();
    for recipe in merged_recipes.values_mut() {
        if let Some(latest) = db.get_recipe(&recipe.id)? {
            if latest.updated_at > recipe.updated_at {
                *recipe = latest;
            }
        }
        normalize_recipe_images(recipe, &asset_map);
        db.upsert_recipe_raw(recipe)?;
    }
    let now = Utc::now().timestamp_millis();
    let final_snap = SyncSnapshot {
        format_version: 1,
        exported_at: now,
        schemas: merged_schemas.into_values().collect(),
        snippets: merged_snippets.into_values().collect(),
        recipes: merged_recipes.into_values().collect(),
        assets: final_assets,
    };
    let json_bytes = serde_json::to_vec(&final_snap)?;
    let mut enc = GzEncoder::new(Vec::new(), Compression::default());
    enc.write_all(&json_bytes)?;
    let gz_bytes = enc.finish()?;

    let mut upload = agent
        .put(&snapshot_url)
        .set("Authorization", &auth)
        .set("Content-Type", "application/gzip");
    if let Some(etag) = remote_etag {
        upload = upload.set("If-Match", &etag);
    } else if !remote_exists {
        upload = upload.set("If-None-Match", "*");
    }
    upload
        .send_bytes(&gz_bytes)
        .map_err(|e| map_ureq_err(e, is_koofr))?;

    db.set_setting(&sync_key, &serde_json::json!(now))?;

    report.message = format!(
        "WebDAV 同步完成：上传图片 {}、下载图片 {}、拉取卡片 {}、推送卡片 {}、冲突副本 {}",
        report.uploaded_blobs,
        report.downloaded_blobs,
        report.pulled_recipes,
        report.pushed_recipes,
        report.conflict_copies
    );
    Ok(report)
}

fn normalize_recipe_images(recipe: &mut StyleRecipe, assets: &HashMap<String, ImageAsset>) {
    for image in &mut recipe.images {
        if let Some(asset) = assets.get(&image.sha256) {
            image.ext = asset.ext.clone();
            image.width = asset.width;
            image.height = asset.height;
            image.blob_rel_path = asset.blob_rel_path.clone();
            image.thumb_rel_path = asset.thumb_rel_path.clone();
        }
    }
}
