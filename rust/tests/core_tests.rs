use image::{Rgba, RgbaImage};
use serde_json::{json, Map};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use std::thread;
use styleloom_core::db::VaultDb;
use styleloom_core::inspector::{encode_stealth_pngcomp_for_test, inspect_media_or_json};
use styleloom_core::media;
use styleloom_core::models::{
    ParamFieldDef, ParamFieldType, PlatformSchema, PromptNode, PromptSnippet, PromptSyntax,
    RecipeFilter, RecipeImageRef, StyleRecipe, TargetSyntax, WebDavConfig,
};
use styleloom_core::prompt_ast::{nodes_to_editable_raw, parse_raw_to_nodes, ungroup_snippet_node};
use styleloom_core::sync;

// Tiny temp dir helper without extra crate
struct TempVault {
    path: std::path::PathBuf,
}

impl TempVault {
    fn new(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "styleloom_test_{}_{}",
            name,
            uuid::Uuid::new_v4().simple()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        Self { path: dir }
    }
}

impl Drop for TempVault {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

fn make_png_with_text(chunks: &[(&str, &str)], w: u32, h: u32) -> Vec<u8> {
    let mut out = Vec::new();
    let mut enc = png::Encoder::new(&mut out, w, h);
    enc.set_color(png::ColorType::Rgba);
    enc.set_depth(png::BitDepth::Eight);
    for (k, v) in chunks {
        enc.add_text_chunk((*k).to_string(), (*v).to_string())
            .unwrap();
    }
    let mut writer = enc.write_header().unwrap();
    let data = vec![200u8; (w * h * 4) as usize];
    writer.write_image_data(&data).unwrap();
    drop(writer);
    out
}

#[test]
fn test_builtin_schemas_and_custom_crud() {
    let tv = TempVault::new("schemas");
    let db = VaultDb::open(&tv.path).unwrap();
    let schemas = db.list_schemas(false).unwrap();
    assert_eq!(schemas.len(), 11);

    for id in [
        "nai_v5",
        "nai_v4_5",
        "nai_v3",
        "comfy_anima_base",
        "comfy_anima_turbo",
        "comfy_moss",
        "comfy_illustrious",
        "comfy_noobai_vpred",
        "comfy_lumina2",
        "comfy_chroma",
        "webui_forge",
    ] {
        assert!(schemas.iter().any(|s| s.id == id), "missing builtin {id}");
    }

    // Cannot delete builtin
    db.delete_schema("nai_v5").unwrap();
    assert!(db.get_schema("nai_v5").unwrap().unwrap().deleted == false);

    // Custom schema CRUD
    let custom = PlatformSchema {
        id: String::new(),
        platform: "CustomLab".into(),
        model_name: "MyCustomV2".into(),
        default_syntax: PromptSyntax::NaiColon,
        fields: vec![ParamFieldDef {
            key: "guidance".into(),
            label: "Guidance".into(),
            field_type: ParamFieldType::Slider,
            default_value: json!(4.2),
            min: Some(1.0),
            max: Some(10.0),
            step: Some(0.1),
            recommended_min: Some(3.5),
            recommended_max: Some(5.0),
            options: vec![],
            resolution_presets: vec![],
            hint: Some("Custom hint".into()),
        }],
        is_builtin: false,
        updated_at: 0,
        deleted: false,
    };
    let saved = db.upsert_schema(custom).unwrap();
    assert!(saved.id.starts_with("custom_"));
    assert_eq!(db.list_schemas(false).unwrap().len(), 12);

    db.delete_schema(&saved.id).unwrap();
    assert_eq!(db.list_schemas(false).unwrap().len(), 11);
}

#[test]
fn test_prompt_ast_plan_b_snippets_ungroup_and_5_syntaxes() {
    let tv = TempVault::new("ast");
    let db = VaultDb::open(&tv.path).unwrap();

    let sn_a = db
        .save_snippet(PromptSnippet {
            id: "sn_a".into(),
            name: "预设A".into(),
            categories: vec!["人物".into()],
            model_hint: "Universal".into(),
            nodes: vec![],
            raw_text: "1girl, beautiful".into(),
            note: String::new(),
            updated_at: 0,
            deleted: false,
        })
        .unwrap();

    let sn_b = db
        .save_snippet(PromptSnippet {
            id: "sn_b".into(),
            name: "预设B".into(),
            categories: vec!["身材".into()],
            model_hint: "Universal".into(),
            nodes: vec![],
            raw_text: "huge breasts".into(),
            note: String::new(),
            updated_at: 0,
            deleted: false,
        })
        .unwrap();

    let pos_nodes = vec![
        PromptNode::Token {
            id: "t1".into(),
            text: "huge".into(),
            weight: 1.0,
            enabled: true,
        },
        PromptNode::SnippetRef {
            id: "ref_a".into(),
            snippet_id: sn_a.id.clone(),
            fallback_name: sn_a.name.clone(),
            fallback_raw: sn_a.raw_text.clone(),
            weight: 1.0,
            enabled: true,
        },
        PromptNode::SnippetRef {
            id: "ref_b".into(),
            snippet_id: sn_b.id.clone(),
            fallback_name: sn_b.name.clone(),
            fallback_raw: sn_b.raw_text.clone(),
            weight: 1.0,
            enabled: true,
        },
    ];

    let mut recipe = db
        .save_recipe(StyleRecipe {
            id: String::new(),
            title: "测试画师串".into(),
            schema_id: "nai_v5".into(),
            positive_nodes: pos_nodes,
            positive_raw: String::new(),
            negative_nodes: vec![PromptNode::Token {
                id: "n1".into(),
                text: "lowres".into(),
                weight: 1.0,
                enabled: true,
            }],
            negative_raw: String::new(),
            params: Map::new(),
            tags: vec!["厚涂".into()],
            source_url: String::new(),
            notes: String::new(),
            rating: 5,
            favorite: true,
            images: vec![],
            created_at: 0,
            updated_at: 0,
            deleted: false,
        })
        .unwrap();

    // 1. Copy expands SnippetRefs: huge, 1girl, beautiful, huge breasts
    let rendered = db
        .render_recipe_prompt(&recipe.id, "positive", TargetSyntax::AsIs)
        .unwrap();
    assert_eq!(rendered, "huge, 1girl, beautiful, huge breasts");

    // 2. Muting [预设B] skips it on copy
    if let PromptNode::SnippetRef { enabled, .. } = &mut recipe.positive_nodes[2] {
        *enabled = false;
    }
    recipe = db.save_recipe(recipe).unwrap();
    let rendered_muted = db
        .render_recipe_prompt(&recipe.id, "positive", TargetSyntax::AsIs)
        .unwrap();
    assert_eq!(rendered_muted, "huge, 1girl, beautiful");

    // 3. Roundtrip Capsule <-> Editable Raw preserves SnippetRef and muted markers
    let raw_repr = nodes_to_editable_raw(&recipe.positive_nodes, PromptSyntax::NaiColon);
    assert!(raw_repr.contains("[[preset:预设A|sn_a]]"));
    assert!(raw_repr.contains("/*off: [[preset:预设B|sn_b]] */"));
    let reparsed = parse_raw_to_nodes(&raw_repr, &|q| db.lookup_snippet_meta(q));
    assert_eq!(reparsed.len(), 3);
    assert!(!reparsed[2].is_enabled());

    // 4. Live edit of 预设A reflects dynamically in recipe copy
    let mut sn_a_updated = db.get_snippet("sn_a").unwrap().unwrap();
    sn_a_updated.nodes.clear();
    sn_a_updated.raw_text = "1girl, very aesthetic".into();
    db.save_snippet(sn_a_updated).unwrap();
    let rendered_live = db
        .render_recipe_prompt(&recipe.id, "positive", TargetSyntax::AsIs)
        .unwrap();
    assert_eq!(rendered_live, "huge, 1girl, very aesthetic");

    // 5. Plan B Ungroup ("一键打散") explodes ref_a into standalone Tokens
    let ungrouped = ungroup_snippet_node(&recipe.positive_nodes, "ref_a", &|sid| {
        db.resolve_snippet_nodes(sid)
    });
    assert_eq!(ungrouped.len(), 4);
    assert!(matches!(
        &ungrouped[1],
        PromptNode::Token { text, .. } if text == "1girl"
    ));
    assert!(matches!(
        &ungrouped[2],
        PromptNode::Token { text, .. } if text == "very aesthetic"
    ));

    // 6. All 5 syntax conversions
    let weighted_nodes = parse_raw_to_nodes("1.15::artist:mika_pikazo, long_hair::", &|_| None);
    let r_nai_colon = styleloom_core::prompt_ast::render_for_copy(
        &weighted_nodes,
        PromptSyntax::NaiColon,
        TargetSyntax::NaiColon,
        &|_| None,
    );
    assert_eq!(r_nai_colon, "1.15::artist:mika_pikazo::, 1.15::long_hair::");

    let r_sd = styleloom_core::prompt_ast::render_for_copy(
        &weighted_nodes,
        PromptSyntax::NaiColon,
        TargetSyntax::SdParens,
        &|_| None,
    );
    assert_eq!(r_sd, "(artist:mika_pikazo:1.15), (long_hair:1.15)");

    let r_braces = styleloom_core::prompt_ast::render_for_copy(
        &weighted_nodes,
        PromptSyntax::NaiColon,
        TargetSyntax::NaiBraces,
        &|_| None,
    );
    assert_eq!(r_braces, "{{{artist:mika_pikazo}}}, {{{long_hair}}}");

    let r_anima = styleloom_core::prompt_ast::render_for_copy(
        &weighted_nodes,
        PromptSyntax::NaiColon,
        TargetSyntax::AnimaAt,
        &|_| None,
    );
    assert_eq!(r_anima, "(@mika_pikazo:1.15), (long_hair:1.15)");

    let r_moss = styleloom_core::prompt_ast::render_for_copy(
        &weighted_nodes,
        PromptSyntax::NaiColon,
        TargetSyntax::MossSpace,
        &|_| None,
    );
    assert_eq!(r_moss, "(mika pikazo:1.15), (long hair:1.15)");
}

#[test]
fn test_inspector_novelai_a1111_and_stealth_pngcomp() {
    // 1. NovelAI V5 standard PNG text chunks
    let nai_comment = json!({
        "prompt": "1girl, solo",
        "uc": "lowres",
        "steps": 28,
        "scale": 5.5,
        "seed": 99887766,
        "sampler": "k_dpmpp_2m",
        "noise_schedule": "karras",
        "smea": false,
        "v4_prompt": {
            "caption": {
                "base_caption": "1girl, solo, 1.2::artist:ask::",
                "char_captions": []
            }
        },
        "v4_negative_prompt": {
            "caption": {
                "base_caption": "blurry, lowres",
                "char_captions": []
            }
        }
    })
    .to_string();
    let nai_png = make_png_with_text(
        &[
            ("Software", "NovelAI"),
            ("Source", "NovelAI Diffusion V5"),
            ("Comment", &nai_comment),
        ],
        16,
        16,
    );
    let res_nai = inspect_media_or_json(&nai_png, "test.png").unwrap();
    assert_eq!(res_nai.suggested_schema_id.as_deref(), Some("nai_v5"));
    assert_eq!(
        res_nai.stages[0].positive_prompt,
        "1girl, solo, 1.2::artist:ask::"
    );
    assert_eq!(res_nai.stages[0].negative_prompt, "blurry, lowres");
    assert_eq!(res_nai.stages[0].steps, Some(28));

    // 2. A1111 PNG
    let a1111_text = "masterpiece, 1girl, silver hair\nNegative prompt: worst quality, lowres\nSteps: 24, Sampler: Euler a, Schedule type: Karras, CFG scale: 4.5, Seed: 12345, Size: 832x1216, Model: illustriousXL_v01";
    let a1111_png = make_png_with_text(&[("parameters", a1111_text)], 16, 16);
    let res_a1111 = inspect_media_or_json(&a1111_png, "a1111.png").unwrap();
    assert_eq!(
        res_a1111.suggested_schema_id.as_deref(),
        Some("comfy_illustrious")
    );
    assert_eq!(res_a1111.stages[0].steps, Some(24));
    assert_eq!(res_a1111.stages[0].cfg, Some(4.5));

    // 3. Stealth PNGInfo (zero text chunks, Alpha LSB + Gzip)
    let mut rgba = RgbaImage::from_pixel(64, 64, Rgba([120, 140, 160, 255]));
    let stealth_json = json!({
        "prompt": "1girl, stealth magic, 1.3::artist:rella::",
        "uc": "bad anatomy",
        "steps": 30,
        "scale": 6.0,
        "seed": 424242,
        "sampler": "k_euler_ancestral"
    })
    .to_string();
    let stealth_png = encode_stealth_pngcomp_for_test(&mut rgba, &stealth_json).unwrap();
    let res_stealth = inspect_media_or_json(&stealth_png, "stealth.png").unwrap();
    assert!(res_stealth.source_kind.contains("Stealth"));
    assert_eq!(
        res_stealth.stages[0].positive_prompt,
        "1girl, stealth magic, 1.3::artist:rella::"
    );
    assert_eq!(res_stealth.stages[0].negative_prompt, "bad anatomy");
    assert_eq!(res_stealth.stages[0].steps, Some(30));
}

#[test]
fn test_inspector_comfyui_ui_workflow_and_api_json() {
    let ui_workflow = json!({
        "nodes": [
            { "id": 1, "type": "UNETLoader", "inputs": [], "widgets_values": ["moss-image-sft.safetensors", "default"] },
            { "id": 2, "type": "LoraLoaderModelOnly", "inputs": [{ "name": "model", "link": 10 }], "widgets_values": ["d3style.safetensors", 0.9] },
            { "id": 3, "type": "ModelSamplingAuraFlow", "inputs": [{ "name": "model", "link": 11 }], "widgets_values": [5.0] },
            { "id": 4, "type": "CLIPTextEncode", "inputs": [], "widgets_values": ["Anime-style digital illustration, silver hair"] },
            { "id": 5, "type": "CLIPTextEncode", "inputs": [], "widgets_values": ["photorealistic, 3d"] },
            { "id": 6, "type": "EmptySD3LatentImage", "inputs": [], "widgets_values": [832, 1216, 1] },
            {
                "id": 7,
                "type": "KSampler",
                "inputs": [
                    { "name": "model", "link": 12 },
                    { "name": "positive", "link": 13 },
                    { "name": "negative", "link": 14 },
                    { "name": "latent_image", "link": 15 }
                ],
                "widgets_values": [777888, "fixed", 30, 2.8, "euler", "simple", 1.0]
            }
        ],
        "links": [
            [10, 1, 0, 2, 0, "MODEL"],
            [11, 2, 0, 3, 0, "MODEL"],
            [12, 3, 0, 7, 0, "MODEL"],
            [13, 4, 0, 7, 1, "CONDITIONING"],
            [14, 5, 0, 7, 2, "CONDITIONING"],
            [15, 6, 0, 7, 3, "LATENT"]
        ]
    });

    let res = inspect_media_or_json(ui_workflow.to_string().as_bytes(), "moss.json").unwrap();
    assert_eq!(res.suggested_schema_id.as_deref(), Some("comfy_moss"));
    let st = &res.stages[0];
    assert_eq!(st.model.as_deref(), Some("moss-image-sft.safetensors"));
    assert_eq!(st.shift, Some(5.0));
    assert_eq!(st.steps, Some(30));
    assert_eq!(st.cfg, Some(2.8));
    assert_eq!(st.loras.len(), 1);
    assert_eq!(st.loras[0].name, "d3style.safetensors");
    assert_eq!(
        st.positive_prompt,
        "Anime-style digital illustration, silver hair"
    );
    assert_eq!(st.negative_prompt, "photorealistic, 3d");
    assert_eq!(st.size.as_deref(), Some("832x1216"));
}

#[test]
fn test_slpack_export_import_clone_and_fts() {
    let tv_a = TempVault::new("slpack_a");
    let tv_b = TempVault::new("slpack_b");
    let db_a = VaultDb::open(&tv_a.path).unwrap();

    let png_bytes = make_png_with_text(&[("Description", "hello")], 32, 48);
    let asset = media::import_image_bytes(&db_a.vault_dir, &png_bytes).unwrap();
    db_a.upsert_image_asset(&asset).unwrap();
    assert!(db_a.vault_dir.join(&asset.thumb_rel_path).exists());

    let sn = db_a
        .save_snippet(PromptSnippet {
            id: "sn_1".into(),
            name: "光影".into(),
            categories: vec!["氛围".into()],
            model_hint: String::new(),
            nodes: vec![],
            raw_text: "dramatic lighting".into(),
            note: String::new(),
            updated_at: 0,
            deleted: false,
        })
        .unwrap();

    let recipe = db_a
        .save_recipe(StyleRecipe {
            id: String::new(),
            title: "霓虹赛博画风".into(),
            schema_id: "nai_v5".into(),
            positive_nodes: vec![
                PromptNode::Token {
                    id: "t1".into(),
                    text: "artist:ask".into(),
                    weight: 1.2,
                    enabled: true,
                },
                PromptNode::SnippetRef {
                    id: "r1".into(),
                    snippet_id: sn.id.clone(),
                    fallback_name: sn.name.clone(),
                    fallback_raw: sn.raw_text.clone(),
                    weight: 1.0,
                    enabled: true,
                },
            ],
            positive_raw: String::new(),
            negative_nodes: vec![],
            negative_raw: "lowres".into(),
            params: Map::new(),
            tags: vec!["厚涂".into(), "霓虹".into()],
            source_url: String::new(),
            notes: "测试笔记".into(),
            rating: 5,
            favorite: true,
            images: vec![RecipeImageRef {
                sha256: asset.sha256.clone(),
                ext: asset.ext.clone(),
                width: asset.width,
                height: asset.height,
                blob_rel_path: asset.blob_rel_path.clone(),
                thumb_rel_path: asset.thumb_rel_path.clone(),
                caption: "封面".into(),
            }],
            created_at: 0,
            updated_at: 0,
            deleted: false,
        })
        .unwrap();

    // FTS5 search
    let hits = db_a
        .list_recipes(
            &RecipeFilter {
                query: Some("霓虹".into()),
                ..Default::default()
            },
            false,
        )
        .unwrap();
    assert_eq!(hits.len(), 1);

    // Clone to Anima
    let cloned = db_a
        .clone_recipe_to_schema(&recipe.id, "comfy_anima_base", None)
        .unwrap();
    assert_eq!(cloned.schema_id, "comfy_anima_base");
    assert!(cloned.positive_raw.contains("(@ask:1.2)"));

    // Export .slpack -> import into Vault B
    let pack_path = tv_a.path.join("backup.slpack");
    let exp_rep = sync::export_slpack(&db_a, None, &pack_path).unwrap();
    assert_eq!(exp_rep.pushed_recipes, 2);
    assert_eq!(exp_rep.uploaded_blobs, 1);

    let db_b = VaultDb::open(&tv_b.path).unwrap();
    let imp_rep = sync::import_slpack(&db_b, &pack_path).unwrap();
    assert_eq!(imp_rep.pulled_recipes, 2);
    assert_eq!(imp_rep.pulled_snippets, 1);
    assert_eq!(imp_rep.downloaded_blobs, 1);
    assert!(db_b.vault_dir.join(&asset.blob_rel_path).exists());
    assert!(db_b.vault_dir.join(&asset.thumb_rel_path).exists());
}

#[derive(Default)]
struct MockDavState {
    files: HashMap<String, Vec<u8>>,
    dirs: std::collections::HashSet<String>,
    put_counts: HashMap<String, usize>,
    reject_snapshot_put: bool,
}

fn spawn_mock_webdav(expected_auth: String) -> (String, Arc<Mutex<MockDavState>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let state = Arc::new(Mutex::new(MockDavState::default()));
    let state_clone = Arc::clone(&state);

    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { break };
            let mut buf = Vec::new();
            let mut tmp = [0u8; 4096];
            let header_end;
            loop {
                let n = stream.read(&mut tmp).unwrap_or(0);
                if n == 0 {
                    header_end = None;
                    break;
                }
                buf.extend_from_slice(&tmp[..n]);
                if let Some(pos) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                    header_end = Some(pos + 4);
                    break;
                }
            }
            let Some(hend) = header_end else { continue };
            let headers_str = String::from_utf8_lossy(&buf[..hend]).to_string();
            let mut lines = headers_str.lines();
            let first = lines.next().unwrap_or("");
            let mut parts = first.split_whitespace();
            let method = parts.next().unwrap_or("GET");
            let path = parts.next().unwrap_or("/");

            let mut content_len = 0usize;
            let mut auth_val = String::new();
            let mut if_match = None;
            let mut if_none_match = None;
            for line in lines {
                if let Some((k, v)) = line.split_once(':') {
                    if k.eq_ignore_ascii_case("content-length") {
                        content_len = v.trim().parse().unwrap_or(0);
                    } else if k.eq_ignore_ascii_case("authorization") {
                        auth_val = v.trim().to_string();
                    } else if k.eq_ignore_ascii_case("if-match") {
                        if_match = Some(v.trim().to_string());
                    } else if k.eq_ignore_ascii_case("if-none-match") {
                        if_none_match = Some(v.trim().to_string());
                    }
                }
            }

            let mut body = buf[hend..].to_vec();
            while body.len() < content_len {
                let n = stream.read(&mut tmp).unwrap_or(0);
                if n == 0 {
                    break;
                }
                body.extend_from_slice(&tmp[..n]);
            }
            body.truncate(content_len);

            if auth_val != expected_auth {
                let resp =
                    "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                let _ = stream.write_all(resp.as_bytes());
                continue;
            }

            let mut st = state_clone.lock().unwrap();
            match method {
                "MKCOL" => {
                    let clean = path.trim_end_matches('/').to_string();
                    if st.dirs.contains(&clean) {
                        let _ = stream.write_all(b"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    } else {
                        st.dirs.insert(clean);
                        let _ = stream.write_all(b"HTTP/1.1 201 Created\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    }
                }
                "PROPFIND" => {
                    let prefix = path.trim_end_matches('/');
                    let mut xml = String::from("<?xml version=\"1.0\" encoding=\"utf-8\"?><D:multistatus xmlns:D=\"DAV:\">");
                    xml.push_str(&format!("<D:response><D:href>{path}</D:href></D:response>"));
                    for k in st.files.keys() {
                        if k.starts_with(prefix) && k != prefix {
                            xml.push_str(&format!("<D:response><D:href>{k}</D:href></D:response>"));
                        }
                    }
                    xml.push_str("</D:multistatus>");
                    let header = format!(
                        "HTTP/1.1 207 Multi-Status\r\nContent-Type: application/xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        xml.len()
                    );
                    let _ = stream.write_all(header.as_bytes());
                    let _ = stream.write_all(xml.as_bytes());
                }
                "PUT" => {
                    let etag = st
                        .files
                        .get(path)
                        .map(|data| format!("\"{}\"", media::sha256_hex(data)));
                    if (path.ends_with("snapshot.json.gz") && st.reject_snapshot_put)
                        || (if_match.is_some() && if_match != etag)
                        || (if_none_match.as_deref() == Some("*") && etag.is_some())
                    {
                        let _ = stream.write_all(b"HTTP/1.1 412 Precondition Failed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                        continue;
                    }
                    *st.put_counts.entry(path.to_string()).or_insert(0) += 1;
                    st.files.insert(path.to_string(), body);
                    let _ = stream.write_all(
                        b"HTTP/1.1 201 Created\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                    );
                }
                "GET" => {
                    if let Some(data) = st.files.get(path) {
                        let header = format!(
                            "HTTP/1.1 200 OK\r\nETag: \"{}\"\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                            media::sha256_hex(data), data.len()
                        );
                        let _ = stream.write_all(header.as_bytes());
                        let _ = stream.write_all(data);
                    } else {
                        let _ = stream.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    }
                }
                _ => {
                    let _ = stream.write_all(b"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                }
            }
        }
    });

    (format!("http://{addr}/dav/Koofr"), state)
}

#[test]
fn test_webdav_mock_sync_incremental_and_401_and_conflict() {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;

    let expected_auth = format!("Basic {}", STANDARD.encode("user@example.com:app-pass-123"));
    let (endpoint, state) = spawn_mock_webdav(expected_auth);

    // 1. 401 check with wrong password
    let bad_cfg = WebDavConfig {
        preset: "koofr".into(),
        endpoint_url: endpoint.clone(),
        username: "user@example.com".into(),
        password: "wrong".into(),
        remote_dir: "/StyleLoom".into(),
    };
    let err_msg = sync::test_webdav(&bad_cfg).unwrap_err().to_string();
    assert!(err_msg.contains("401"));
    assert!(err_msg.contains("应用专用密码"));

    // 2. Good config test & initial sync from Vault A
    let cfg = WebDavConfig {
        preset: "koofr".into(),
        endpoint_url: endpoint,
        username: "user@example.com".into(),
        password: "app-pass-123".into(),
        remote_dir: "/StyleLoom".into(),
    };
    assert!(sync::test_webdav(&cfg).unwrap().contains("连接成功"));

    let tv_a = TempVault::new("dav_a");
    let tv_b = TempVault::new("dav_b");
    let db_a = VaultDb::open(&tv_a.path).unwrap();

    let png_bytes = make_png_with_text(&[("Description", "dav test")], 24, 24);
    let asset = media::import_image_bytes(&db_a.vault_dir, &png_bytes).unwrap();
    db_a.upsert_image_asset(&asset).unwrap();

    let recipe_a = db_a
        .save_recipe(StyleRecipe {
            id: "rec_sync_1".into(),
            title: "Koofr 同步测试".into(),
            schema_id: "nai_v5".into(),
            positive_nodes: vec![],
            positive_raw: "1girl, solo".into(),
            negative_nodes: vec![],
            negative_raw: "lowres".into(),
            params: Map::new(),
            tags: vec![],
            source_url: String::new(),
            notes: "v1".into(),
            rating: 4,
            favorite: false,
            images: vec![RecipeImageRef {
                sha256: asset.sha256.clone(),
                ext: asset.ext.clone(),
                width: asset.width,
                height: asset.height,
                blob_rel_path: asset.blob_rel_path.clone(),
                thumb_rel_path: asset.thumb_rel_path.clone(),
                caption: String::new(),
            }],
            created_at: 0,
            updated_at: 0,
            deleted: false,
        })
        .unwrap();

    let rep_a1 = sync::sync_webdav(&db_a, &cfg).unwrap();
    assert_eq!(rep_a1.uploaded_blobs, 1);

    // 3. Vault B pulls down
    let db_b = VaultDb::open(&tv_b.path).unwrap();
    let rep_b1 = sync::sync_webdav(&db_b, &cfg).unwrap();
    assert_eq!(rep_b1.downloaded_blobs, 1);
    assert_eq!(rep_b1.pulled_recipes, 1);
    assert!(db_b.vault_dir.join(&asset.blob_rel_path).exists());

    // 4. Vault B edits notes and syncs up -> blob must NOT be re-uploaded!
    let mut rec_b = db_b.get_recipe(&recipe_a.id).unwrap().unwrap();
    rec_b.notes = "edited on B".into();
    rec_b.updated_at += 2000;
    db_b.upsert_recipe_raw(&rec_b).unwrap();

    let rep_b2 = sync::sync_webdav(&db_b, &cfg).unwrap();
    assert_eq!(rep_b2.uploaded_blobs, 0);

    let blob_put_path = format!("/dav/Koofr/StyleLoom/blobs/{}.{}", asset.sha256, asset.ext);
    assert_eq!(state.lock().unwrap().put_counts[&blob_put_path], 1);

    // 5. Concurrent edit conflict preservation
    let mut rec_a_edit = db_a.get_recipe(&recipe_a.id).unwrap().unwrap();
    rec_a_edit.notes = "edited concurrently on A".into();
    rec_a_edit.updated_at += 5000;
    db_a.upsert_recipe_raw(&rec_a_edit).unwrap();

    let rep_a2 = sync::sync_webdav(&db_a, &cfg).unwrap();
    assert_eq!(rep_a2.conflict_copies, 1);
    let all_a = db_a.list_recipes(&RecipeFilter::default(), false).unwrap();
    assert_eq!(all_a.len(), 2);
}

#[test]
fn test_inspector_comfy_api_multi_stage_and_c_ffi_roundtrip() {
    use std::ffi::{CStr, CString};
    use styleloom_core::{styleloom_free_buf, styleloom_inspect_bytes, styleloom_invoke_json};

    let api_json = json!({
        "1": { "class_type": "CheckpointLoaderSimple", "inputs": { "ckpt_name": "anima_turbo_v1.safetensors" } },
        "2": { "class_type": "CLIPTextEncode", "inputs": { "text": "@mika_pikazo, 1girl, glowing eyes", "clip": ["1", 1] } },
        "3": { "class_type": "CLIPTextEncode", "inputs": { "text": "3d, photorealistic", "clip": ["1", 1] } },
        "4": { "class_type": "KSamplerSelect", "inputs": { "sampler_name": "euler" } },
        "5": { "class_type": "BasicScheduler", "inputs": { "model": ["1", 0], "scheduler": "beta", "steps": 10, "denoise": 1.0 } },
        "6": { "class_type": "CFGGuider", "inputs": { "model": ["1", 0], "positive": ["2", 0], "negative": ["3", 0], "cfg": 1.5 } },
        "7": { "class_type": "RandomNoise", "inputs": { "noise_seed": 314159 } },
        "8": { "class_type": "EmptyLatentImage", "inputs": { "width": 832, "height": 1216, "batch_size": 1 } },
        "9": {
            "class_type": "SamplerCustomAdvanced",
            "inputs": {
                "noise": ["7", 0],
                "guider": ["6", 0],
                "sampler": ["4", 0],
                "sigmas": ["5", 0],
                "latent_image": ["8", 0]
            }
        }
    })
    .to_string();

    // Test C ABI inspect_bytes
    let hint = CString::new("anima.json").unwrap();
    let ptr = unsafe { styleloom_inspect_bytes(api_json.as_ptr(), api_json.len(), hint.as_ptr()) };
    let resp_str = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
    unsafe { styleloom_free_buf(ptr) };
    let resp_val: serde_json::Value = serde_json::from_str(&resp_str).unwrap();
    assert_eq!(resp_val["ok"], true);
    assert_eq!(resp_val["data"]["suggested_schema_id"], "comfy_anima_turbo");
    assert_eq!(resp_val["data"]["stages"][0]["steps"], 10);
    assert_eq!(resp_val["data"]["stages"][0]["cfg"], 1.5);
    assert_eq!(resp_val["data"]["stages"][0]["sampler"], "euler");
    assert_eq!(resp_val["data"]["stages"][0]["scheduler"], "beta");

    // Test C ABI invoke_json
    let tv = TempVault::new("ffi");
    let req = json!({
        "op": "init_vault",
        "vault_dir": tv.path.to_string_lossy()
    })
    .to_string();
    let req_c = CString::new(req).unwrap();
    let res_ptr = unsafe { styleloom_invoke_json(req_c.as_ptr()) };
    let res_str = unsafe { CStr::from_ptr(res_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { styleloom_free_buf(res_ptr) };
    let v: serde_json::Value = serde_json::from_str(&res_str).unwrap();
    assert_eq!(v["ok"], true);
    assert_eq!(v["data"]["schemas"].as_array().unwrap().len(), 11);
}

fn regression_recipe(id: &str) -> StyleRecipe {
    serde_json::from_value(json!({"id": id, "title": "regression", "schema_id": "nai_v5"})).unwrap()
}

#[test]
fn test_rapid_edits_and_deletion_have_monotonic_versions() {
    let vault = TempVault::new("rapid_edits");
    let db = VaultDb::open(&vault.path).unwrap();
    let mut recipe = regression_recipe("rapid");
    recipe.positive_raw = "cat".into();
    let first = db.save_recipe(recipe).unwrap();
    let mut changed = first.clone();
    changed.positive_nodes.clear();
    changed.positive_raw = "dog".into();
    let second = db.save_recipe(changed).unwrap();
    assert!(second.updated_at > first.updated_at);
    assert_eq!(
        db.render_recipe_prompt("rapid", "positive", TargetSyntax::AsIs)
            .unwrap(),
        "dog"
    );
    db.delete_recipe("rapid").unwrap();
    assert!(db.get_recipe("rapid").unwrap().unwrap().updated_at > second.updated_at);
}

#[test]
fn test_deleted_snippet_keeps_fallback_after_raw_roundtrip() {
    let vault = TempVault::new("deleted_snippet");
    let db = VaultDb::open(&vault.path).unwrap();
    let snippet: PromptSnippet = serde_json::from_value(json!({
        "id": "snippet", "name": "snippet", "raw_text": "cat, dog"
    }))
    .unwrap();
    db.save_snippet(snippet).unwrap();
    let nodes = parse_raw_to_nodes("[[preset:snippet|snippet]]", &|q| db.lookup_snippet_meta(q));
    db.delete_snippet("snippet").unwrap();
    let raw = nodes_to_editable_raw(&nodes, PromptSyntax::SdParens);
    let restored = parse_raw_to_nodes(&raw, &|q| db.lookup_snippet_meta(q));
    let rendered = styleloom_core::prompt_ast::render_for_copy(
        &restored,
        PromptSyntax::SdParens,
        TargetSyntax::AsIs,
        &|id| db.resolve_snippet_nodes(id),
    );
    assert_eq!(rendered, "cat, dog");
}

#[test]
fn test_nested_prompt_weights_escaped_commas_and_muted_groups() {
    let nodes = parse_raw_to_nodes(
        r"((cat:1.2), dog), /*off: {bird, fish} */, artist:name\,suffix, [a:b:0.5]",
        &|_| None,
    );
    let rendered = styleloom_core::prompt_ast::render_for_copy(
        &nodes,
        PromptSyntax::SdParens,
        TargetSyntax::SdParens,
        &|_| None,
    );
    assert_eq!(
        rendered,
        r"(cat:1.32), (dog:1.1), artist:name\,suffix, [a:b:0.5]"
    );
    let raw = nodes_to_editable_raw(&nodes, PromptSyntax::SdParens);
    let roundtrip = parse_raw_to_nodes(&raw, &|_| None);
    assert_eq!(roundtrip.len(), nodes.len());
    assert!(!roundtrip[2].is_enabled());
    assert!(!roundtrip[3].is_enabled());
    for raw in ["NaN::cat::", "inf::cat::", "(cat:NaN)"] {
        assert!(serde_json::to_string(&parse_raw_to_nodes(raw, &|_| None))
            .unwrap()
            .find("null")
            .is_none());
    }
}

#[test]
fn test_inspector_cyclic_scalar_nodes_and_png_workflow_fallback() {
    let workflow = json!({
        "1": {"class_type": "Primitive", "inputs": {"value": ["2", 0]}},
        "2": {"class_type": "Primitive", "inputs": {"value": ["1", 0]}},
        "3": {"class_type": "KSampler", "inputs": {"steps": ["1", 0], "cfg": 5, "seed": 1}}
    })
    .to_string();
    let result = inspect_media_or_json(workflow.as_bytes(), "cyclic.json").unwrap();
    assert_eq!(result.stages[0].steps, None);
    let png = make_png_with_text(&[("prompt", "{}"), ("workflow", &workflow)], 8, 8);
    assert!(inspect_media_or_json(&png, "fallback.png").is_ok());
}

fn write_regression_pack(
    path: &std::path::Path,
    manifest: serde_json::Value,
    blob: Option<(&str, &[u8])>,
) {
    let mut writer = zip::ZipWriter::new(std::fs::File::create(path).unwrap());
    let options = zip::write::SimpleFileOptions::default();
    writer.start_file("manifest.json", options).unwrap();
    writer.write_all(manifest.to_string().as_bytes()).unwrap();
    if let Some((name, bytes)) = blob {
        writer.start_file(name, options).unwrap();
        writer.write_all(bytes).unwrap();
    }
    writer.finish().unwrap();
}

#[test]
fn test_slpack_rejects_invalid_version_paths_missing_and_corrupt_images() {
    let vault = TempVault::new("bad_packs");
    let db = VaultDb::open(&vault.path).unwrap();
    let bytes = make_png_with_text(&[], 8, 8);
    let sha = media::sha256_hex(&bytes);
    let image = json!({"sha256": sha, "ext": "png", "width": 8, "height": 8,
        "blob_rel_path": format!("blobs/{}/{sha}.png", &sha[..2]),
        "thumb_rel_path": format!("thumbs/{}/{sha}.jpg", &sha[..2])});
    let manifest = json!({"format_version": 1, "exported_at": 0, "schemas": [], "snippets": [], "assets": [],
        "recipes": [{"id": "bad", "title": "bad", "schema_id": "nai_v5", "images": [image]}]});
    let pack = vault.path.join("bad.slpack");
    let mut version = manifest.clone();
    version["format_version"] = json!(99);
    write_regression_pack(&pack, version, None);
    assert!(sync::import_slpack(&db, &pack)
        .unwrap_err()
        .to_string()
        .contains("版本"));
    let mut paths = manifest.clone();
    paths["recipes"][0]["images"][0]["blob_rel_path"] = json!("../private.png");
    write_regression_pack(&pack, paths, None);
    assert!(sync::import_slpack(&db, &pack)
        .unwrap_err()
        .to_string()
        .contains("路径"));
    write_regression_pack(&pack, manifest.clone(), None);
    assert!(sync::import_slpack(&db, &pack)
        .unwrap_err()
        .to_string()
        .contains("缺少"));
    let filename = format!("blobs/{sha}.png");
    write_regression_pack(&pack, manifest, Some((&filename, b"corrupt")));
    assert!(sync::import_slpack(&db, &pack)
        .unwrap_err()
        .to_string()
        .contains("校验"));
    assert!(db.get_recipe("bad").unwrap().is_none());
    assert!(db.list_image_assets().unwrap().is_empty());
}

#[test]
fn test_webdav_missing_corrupt_images_and_concurrent_snapshot_changes_fail() {
    use base64::Engine;
    let auth = format!(
        "Basic {}",
        base64::engine::general_purpose::STANDARD.encode("user:pass")
    );
    let (endpoint, state) = spawn_mock_webdav(auth);
    let cfg = WebDavConfig {
        preset: "custom".into(),
        endpoint_url: endpoint,
        username: "user".into(),
        password: "pass".into(),
        remote_dir: "Nested/My Vault".into(),
    };
    let a = TempVault::new("failure_a");
    let db_a = VaultDb::open(&a.path).unwrap();
    let original = make_png_with_text(&[], 8, 8);
    let asset = media::import_image_bytes(&a.path, &original).unwrap();
    let mut recipe = regression_recipe("images");
    recipe.images.push(RecipeImageRef {
        sha256: asset.sha256.clone(),
        ext: asset.ext.clone(),
        width: asset.width,
        height: asset.height,
        blob_rel_path: asset.blob_rel_path.clone(),
        thumb_rel_path: asset.thumb_rel_path.clone(),
        caption: String::new(),
    });
    db_a.save_recipe(recipe).unwrap();
    sync::sync_webdav(&db_a, &cfg).unwrap();
    let root = "/dav/Koofr/Nested/My%20Vault";
    let blob_path = format!("{root}/blobs/{}.png", asset.sha256);
    let snapshot_path = format!("{root}/records/snapshot.json.gz");
    let b = TempVault::new("failure_b");
    let db_b = VaultDb::open(&b.path).unwrap();
    state.lock().unwrap().files.remove(&blob_path);
    assert!(sync::sync_webdav(&db_b, &cfg)
        .unwrap_err()
        .to_string()
        .contains("404"));
    assert!(db_b.get_recipe("images").unwrap().is_none());
    assert!(db_b
        .get_setting(&format!(
            "webdav_last_sync:{}{root}",
            cfg.endpoint_url.trim_end_matches("/dav/Koofr")
        ))
        .unwrap()
        .is_none());
    state
        .lock()
        .unwrap()
        .files
        .insert(blob_path.clone(), b"corrupt".to_vec());
    assert!(sync::sync_webdav(&db_b, &cfg)
        .unwrap_err()
        .to_string()
        .contains("校验"));
    assert!(db_b.get_recipe("images").unwrap().is_none());
    state.lock().unwrap().files.remove(&blob_path);
    assert_eq!(sync::sync_webdav(&db_a, &cfg).unwrap().uploaded_blobs, 1);
    assert_eq!(sync::sync_webdav(&db_b, &cfg).unwrap().downloaded_blobs, 1);
    let received = db_b.get_recipe("images").unwrap().unwrap();
    let image = &received.images[0];
    let blob = b.path.join(&image.blob_rel_path);
    let thumb = b.path.join(&image.thumb_rel_path);
    assert_eq!(std::fs::read(&blob).unwrap(), original);
    assert!(image::open(&thumb).is_ok());
    std::fs::write(&thumb, []).unwrap();
    assert_eq!(sync::sync_webdav(&db_b, &cfg).unwrap().downloaded_blobs, 0);
    assert!(image::open(&thumb).is_ok());
    std::fs::write(&blob, b"partial").unwrap();
    assert_eq!(sync::sync_webdav(&db_b, &cfg).unwrap().downloaded_blobs, 1);
    assert_eq!(std::fs::read(&blob).unwrap(), original);
    let snapshot = state.lock().unwrap().files[&snapshot_path].clone();
    state.lock().unwrap().reject_snapshot_put = true;
    assert!(sync::sync_webdav(&db_a, &cfg)
        .unwrap_err()
        .to_string()
        .contains("412"));
    assert_eq!(state.lock().unwrap().files[&snapshot_path], snapshot);
}

#[test]
fn test_webdav_roundtrip_jpg_png_and_webp_in_both_directions() {
    let (endpoint, _) = spawn_mock_webdav("Basic dXNlcjpwYXNz".into());
    let cfg = WebDavConfig {
        preset: "custom".into(),
        endpoint_url: endpoint,
        username: "user".into(),
        password: "pass".into(),
        remote_dir: "/StyleLoom".into(),
    };
    let a = TempVault::new("formats_a");
    let b = TempVault::new("formats_b");
    let db_a = VaultDb::open(&a.path).unwrap();
    let db_b = VaultDb::open(&b.path).unwrap();
    for (sender, receiver, color) in [(&db_a, &db_b, 25), (&db_b, &db_a, 75)] {
        let mut recipe = regression_recipe(&format!("formats_{color}"));
        let mut images = Vec::new();
        for (format, ext) in [
            (image::ImageFormat::Jpeg, "jpg"),
            (image::ImageFormat::Png, "png"),
            (image::ImageFormat::WebP, "webp"),
        ] {
            let mut bytes = std::io::Cursor::new(Vec::new());
            image::RgbImage::from_pixel(16, 12, image::Rgb([color, 60, 100]))
                .write_to(&mut bytes, format)
                .unwrap();
            let bytes = bytes.into_inner();
            let asset = media::import_image_bytes(&sender.vault_dir, &bytes).unwrap();
            sender.upsert_image_asset(&asset).unwrap();
            assert_eq!(asset.ext, ext);
            recipe.images.push(RecipeImageRef {
                sha256: asset.sha256,
                ext: asset.ext,
                width: asset.width,
                height: asset.height,
                blob_rel_path: asset.blob_rel_path,
                thumb_rel_path: asset.thumb_rel_path,
                caption: String::new(),
            });
            images.push(bytes);
        }
        let saved = sender.save_recipe(recipe).unwrap();
        assert_eq!(sync::sync_webdav(sender, &cfg).unwrap().uploaded_blobs, 3);
        assert_eq!(
            sync::sync_webdav(receiver, &cfg).unwrap().downloaded_blobs,
            3
        );
        let received = receiver.get_recipe(&saved.id).unwrap().unwrap();
        for (image, original) in received.images.iter().zip(images) {
            assert_eq!(
                std::fs::read(receiver.vault_dir.join(&image.blob_rel_path)).unwrap(),
                original
            );
            assert!(image::open(receiver.vault_dir.join(&image.thumb_rel_path)).is_ok());
        }
    }
}
