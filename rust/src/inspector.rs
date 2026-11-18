use crate::models::{CoreError, CoreResult, InspectedLora, InspectedStage, InspectionResult};
use flate2::read::GzDecoder;
use flate2::read::ZlibDecoder;
use image::{GenericImageView, ImageFormat};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::Read;

#[derive(Debug, Clone)]
struct PngTextEntry {
    keyword: String,
    text: String,
}

fn read_png_chunks(bytes: &[u8]) -> Option<(u32, u32, Vec<PngTextEntry>)> {
    if bytes.len() < 8 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" {
        return None;
    }
    let mut pos = 8usize;
    let mut width = 0u32;
    let mut height = 0u32;
    let mut entries = Vec::new();

    while pos + 12 <= bytes.len() {
        let len = u32::from_be_bytes([bytes[pos], bytes[pos + 1], bytes[pos + 2], bytes[pos + 3]])
            as usize;
        let chunk_type = &bytes[pos + 4..pos + 8];
        let data_start = pos + 8;
        let data_end = data_start.checked_add(len)?;
        if data_end + 4 > bytes.len() {
            break;
        }
        let data = &bytes[data_start..data_end];

        match chunk_type {
            b"IHDR" if data.len() >= 8 => {
                width = u32::from_be_bytes([data[0], data[1], data[2], data[3]]);
                height = u32::from_be_bytes([data[4], data[5], data[6], data[7]]);
            }
            b"tEXt" => {
                if let Some(nul) = data.iter().position(|&b| b == 0) {
                    let kw = String::from_utf8_lossy(&data[..nul]).to_string();
                    let text = String::from_utf8_lossy(&data[nul + 1..]).to_string();
                    entries.push(PngTextEntry { keyword: kw, text });
                }
            }
            b"zTXt" => {
                if let Some(nul) = data.iter().position(|&b| b == 0) {
                    let kw = String::from_utf8_lossy(&data[..nul]).to_string();
                    if data.len() > nul + 2 && data[nul + 1] == 0 {
                        let mut dec = ZlibDecoder::new(&data[nul + 2..]);
                        let mut out = String::new();
                        if dec.read_to_string(&mut out).is_ok() {
                            entries.push(PngTextEntry {
                                keyword: kw,
                                text: out,
                            });
                        }
                    }
                }
            }
            b"iTXt" => {
                if let Some(nul1) = data.iter().position(|&b| b == 0) {
                    let kw = String::from_utf8_lossy(&data[..nul1]).to_string();
                    if data.len() > nul1 + 3 {
                        let comp_flag = data[nul1 + 1];
                        let comp_method = data[nul1 + 2];
                        let rest = &data[nul1 + 3..];
                        if let Some(nul2) = rest.iter().position(|&b| b == 0) {
                            let rest2 = &rest[nul2 + 1..];
                            if let Some(nul3) = rest2.iter().position(|&b| b == 0) {
                                let text_bytes = &rest2[nul3 + 1..];
                                let decoded = if comp_flag == 1 && comp_method == 0 {
                                    let mut dec = ZlibDecoder::new(text_bytes);
                                    let mut out = String::new();
                                    if dec.read_to_string(&mut out).is_ok() {
                                        Some(out)
                                    } else {
                                        None
                                    }
                                } else {
                                    Some(String::from_utf8_lossy(text_bytes).to_string())
                                };
                                if let Some(text) = decoded {
                                    entries.push(PngTextEntry { keyword: kw, text });
                                }
                            }
                        }
                    }
                }
            }
            b"IEND" => break,
            _ => {}
        }
        pos = data_end + 4;
    }

    Some((width, height, entries))
}

struct BitStreamReader {
    bits: Vec<u8>,
    cursor: usize,
}

impl BitStreamReader {
    fn from_alpha(rgba: &image::RgbaImage) -> Self {
        let (w, h) = rgba.dimensions();
        let mut bits = Vec::with_capacity((w * h) as usize);
        for x in 0..w {
            for y in 0..h {
                bits.push(rgba.get_pixel(x, y).0[3] & 1);
            }
        }
        Self { bits, cursor: 0 }
    }

    fn from_rgb(rgb: &image::RgbImage) -> Self {
        let (w, h) = rgb.dimensions();
        let mut bits = Vec::with_capacity((w * h * 3) as usize);
        for x in 0..w {
            for y in 0..h {
                let p = rgb.get_pixel(x, y).0;
                bits.push(p[0] & 1);
                bits.push(p[1] & 1);
                bits.push(p[2] & 1);
            }
        }
        Self { bits, cursor: 0 }
    }

    fn remaining(&self) -> usize {
        self.bits.len().saturating_sub(self.cursor)
    }

    fn read_bytes(&mut self, count: usize) -> Option<Vec<u8>> {
        let needed = count.checked_mul(8)?;
        if self.remaining() < needed {
            return None;
        }
        let mut out = Vec::with_capacity(count);
        for _ in 0..count {
            let mut b = 0u8;
            for bit_i in 0..8 {
                b = (b << 1) | self.bits[self.cursor + bit_i];
            }
            self.cursor += 8;
            out.push(b);
        }
        Some(out)
    }

    fn read_u32_be(&mut self) -> Option<u32> {
        let bytes = self.read_bytes(4)?;
        Some(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }
}

fn try_decode_stealth_reader(
    mut reader: BitStreamReader,
    compressed_sigs: (&[u8], &[u8]),
) -> Option<String> {
    let sig_len = compressed_sigs.0.len();
    let sig = reader.read_bytes(sig_len)?;
    let is_comp = if sig.as_slice() == compressed_sigs.1 {
        true
    } else if sig.as_slice() == compressed_sigs.0 {
        false
    } else {
        return None;
    };

    let bit_len = reader.read_u32_be()? as usize;
    if bit_len == 0 || bit_len > reader.remaining() || bit_len % 8 != 0 {
        return None;
    }
    let payload_bytes = reader.read_bytes(bit_len / 8)?;
    if is_comp {
        let mut dec = GzDecoder::new(payload_bytes.as_slice());
        let mut out = String::new();
        dec.read_to_string(&mut out).ok()?;
        Some(out)
    } else {
        String::from_utf8(payload_bytes).ok()
    }
}

fn decode_stealth_pnginfo(bytes: &[u8]) -> Option<String> {
    let img = image::load_from_memory_with_format(bytes, ImageFormat::Png).ok()?;
    let rgba = img.to_rgba8();
    if let Some(found) = try_decode_stealth_reader(
        BitStreamReader::from_alpha(&rgba),
        (b"stealth_pnginfo", b"stealth_pngcomp"),
    ) {
        return Some(found);
    }
    let rgb = img.to_rgb8();
    try_decode_stealth_reader(
        BitStreamReader::from_rgb(&rgb),
        (b"stealth_rgbinfo", b"stealth_rgbcomp"),
    )
}

fn guess_schema_from_model_name(model_name: &str, is_novelai: bool, has_v4_prompt: bool) -> String {
    let lower = model_name.to_ascii_lowercase();
    if is_novelai {
        if lower.contains("v5") || lower.contains("novelai diffusion v5") {
            return "nai_v5".into();
        }
        if lower.contains("v4.5") || lower.contains("4.5") {
            return "nai_v4_5".into();
        }
        if has_v4_prompt {
            return "nai_v5".into();
        }
        return "nai_v3".into();
    }
    if lower.contains("anima") {
        if lower.contains("turbo") {
            return "comfy_anima_turbo".into();
        }
        return "comfy_anima_base".into();
    }
    if lower.contains("moss") {
        return "comfy_moss".into();
    }
    if lower.contains("noob") {
        return "comfy_noobai_vpred".into();
    }
    if lower.contains("illustrious") {
        return "comfy_illustrious".into();
    }
    if lower.contains("lumina") {
        return "comfy_lumina2".into();
    }
    if lower.contains("chroma") {
        return "comfy_chroma".into();
    }
    "webui_forge".into()
}

fn parse_a1111_parameters(
    raw: &str,
    width: Option<u32>,
    height: Option<u32>,
    kind: &str,
) -> Option<InspectionResult> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    let (pos_and_neg, param_line) = if let Some(idx) = trimmed.rfind("\nSteps:") {
        (&trimmed[..idx], Some(&trimmed[idx + 1..]))
    } else if trimmed.starts_with("Steps:") {
        ("", Some(trimmed))
    } else if trimmed.contains("Negative prompt:") {
        (trimmed, None)
    } else {
        return None;
    };

    let (positive, negative) = if let Some(neg_idx) = pos_and_neg.find("Negative prompt:") {
        (
            pos_and_neg[..neg_idx].trim().to_string(),
            pos_and_neg[neg_idx + "Negative prompt:".len()..]
                .trim()
                .to_string(),
        )
    } else {
        (pos_and_neg.trim().to_string(), String::new())
    };

    let mut sampler = None;
    let mut scheduler = None;
    let mut steps = None;
    let mut cfg = None;
    let mut seed = None;
    let mut size = None;
    let mut model = None;
    let mut extra = Vec::new();

    if let Some(line) = param_line {
        for kv in line.split(',') {
            if let Some((k, v)) = kv.split_once(':') {
                let key = k.trim();
                let val = v.trim();
                match key {
                    "Steps" => steps = val.parse::<i64>().ok(),
                    "Sampler" => sampler = Some(val.to_string()),
                    "Schedule type" | "Scheduler" => scheduler = Some(val.to_string()),
                    "CFG scale" => cfg = val.parse::<f64>().ok(),
                    "Seed" => seed = Some(val.to_string()),
                    "Size" => size = Some(val.to_string()),
                    "Model" => model = Some(val.to_string()),
                    other => extra.push((other.to_string(), val.to_string())),
                }
            }
        }
    }

    let suggested = model
        .as_deref()
        .map(|m| guess_schema_from_model_name(m, false, false))
        .unwrap_or_else(|| "webui_forge".into());

    Some(InspectionResult {
        source_kind: kind.to_string(),
        suggested_schema_id: Some(suggested),
        width,
        height,
        stages: vec![InspectedStage {
            stage_name: "WebUI / A1111 生成参数".into(),
            positive_prompt: positive,
            negative_prompt: negative,
            model,
            sampler,
            scheduler,
            steps,
            cfg,
            seed,
            size,
            shift: None,
            loras: Vec::new(),
            extra_fields: extra,
        }],
        raw_metadata: raw.to_string(),
    })
}

fn parse_novelai_comment(
    comment_json: &str,
    description: Option<&str>,
    source_tag: Option<&str>,
    width: Option<u32>,
    height: Option<u32>,
    kind: &str,
) -> Option<InspectionResult> {
    let val: Value = serde_json::from_str(comment_json).ok()?;
    let obj = val.as_object()?;

    let mut has_v4 = false;
    let positive = if let Some(v4_cap) = obj
        .get("v4_prompt")
        .and_then(|v| v.get("caption"))
        .and_then(|v| v.get("base_caption"))
        .and_then(|v| v.as_str())
    {
        has_v4 = true;
        let mut parts = vec![v4_cap.trim().to_string()];
        if let Some(chars) = obj
            .get("v4_prompt")
            .and_then(|v| v.get("caption"))
            .and_then(|v| v.get("char_captions"))
            .and_then(|v| v.as_array())
        {
            for (idx, c) in chars.iter().enumerate() {
                if let Some(cc) = c.get("char_caption").and_then(|x| x.as_str()) {
                    if !cc.trim().is_empty() {
                        parts.push(format!("/*char{}*/ {}", idx + 1, cc.trim()));
                    }
                }
            }
        }
        parts.join(", ")
    } else {
        obj.get("prompt")
            .and_then(|v| v.as_str())
            .or(description)
            .unwrap_or("")
            .trim()
            .to_string()
    };

    let negative = if let Some(v4_uc) = obj
        .get("v4_negative_prompt")
        .and_then(|v| v.get("caption"))
        .and_then(|v| v.get("base_caption"))
        .and_then(|v| v.as_str())
    {
        has_v4 = true;
        v4_uc.trim().to_string()
    } else {
        obj.get("uc")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string()
    };

    let steps = obj.get("steps").and_then(|v| v.as_i64());
    let cfg = obj.get("scale").and_then(|v| v.as_f64());
    let seed = obj.get("seed").and_then(|v| {
        v.as_i64()
            .map(|n| n.to_string())
            .or_else(|| v.as_str().map(str::to_string))
    });
    let sampler = obj
        .get("sampler")
        .and_then(|v| v.as_str())
        .map(str::to_string);
    let scheduler = obj
        .get("noise_schedule")
        .and_then(|v| v.as_str())
        .map(str::to_string);

    let size = match (
        obj.get("width")
            .and_then(|v| v.as_u64())
            .or(width.map(u64::from)),
        obj.get("height")
            .and_then(|v| v.as_u64())
            .or(height.map(u64::from)),
    ) {
        (Some(w), Some(h)) => Some(format!("{w}x{h}")),
        _ => None,
    };

    let mut extra = Vec::new();
    for (k, label) in [
        ("cfg_rescale", "Prompt Guidance Rescale"),
        ("sm", "SMEA"),
        ("sm_dyn", "SMEA DYN"),
        ("smea", "SMEA"),
        ("smea_dyn", "SMEA DYN"),
        ("dynamic_thresholding", "Decrisper"),
        ("qualityToggle", "Built-in Quality Tags"),
    ] {
        if let Some(v) = obj.get(k) {
            extra.push((label.to_string(), v.to_string()));
        }
    }
    if let Some(src) = source_tag {
        extra.push(("Source".to_string(), src.to_string()));
    }

    let model_str = source_tag.map(str::to_string).unwrap_or_else(|| {
        if has_v4 {
            "NovelAI Diffusion V4.5/V5".into()
        } else {
            "NovelAI Diffusion V3".into()
        }
    });
    let suggested = guess_schema_from_model_name(&model_str, true, has_v4);

    Some(InspectionResult {
        source_kind: kind.to_string(),
        suggested_schema_id: Some(suggested),
        width,
        height,
        stages: vec![InspectedStage {
            stage_name: "NovelAI 生成参数".into(),
            positive_prompt: positive,
            negative_prompt: negative,
            model: Some(model_str),
            sampler,
            scheduler,
            steps,
            cfg,
            seed,
            size,
            shift: None,
            loras: Vec::new(),
            extra_fields: extra,
        }],
        raw_metadata: comment_json.to_string(),
    })
}

#[derive(Debug, Clone)]
struct UnifiedNode {
    class_type: String,
    inputs: HashMap<String, Value>,
}

fn widget_names_for_type(class_type: &str) -> &'static [&'static str] {
    match class_type {
        "KSampler" => &[
            "seed",
            "control_after_generate",
            "steps",
            "cfg",
            "sampler_name",
            "scheduler",
            "denoise",
        ],
        "KSamplerAdvanced" => &[
            "add_noise",
            "noise_seed",
            "control_after_generate",
            "steps",
            "cfg",
            "sampler_name",
            "scheduler",
            "start_at_step",
            "end_at_step",
            "return_with_leftover_noise",
        ],
        "CheckpointLoaderSimple" => &["ckpt_name"],
        "UNETLoader" => &["unet_name", "weight_dtype"],
        "LoraLoader" => &["lora_name", "strength_model", "strength_clip"],
        "LoraLoaderModelOnly" => &["lora_name", "strength_model"],
        "CLIPTextEncode" => &["text"],
        "CLIPTextEncodeLumina2" => &["system_prompt", "user_prompt"],
        "ModelSamplingAuraFlow" | "ModelSamplingSD3" => &["shift"],
        "EmptyLatentImage" | "EmptySD3LatentImage" => &["width", "height", "batch_size"],
        "BasicScheduler" => &["scheduler", "steps", "denoise"],
        "KSamplerSelect" => &["sampler_name"],
        "RandomNoise" => &["noise_seed"],
        "CFGGuider" => &["cfg"],
        "PrimitiveNode" => &["value"],
        _ => &[],
    }
}

fn build_comfy_graph(val: &Value) -> Option<HashMap<String, UnifiedNode>> {
    let obj = val.as_object()?;
    if let (Some(nodes_arr), Some(links_arr)) = (
        obj.get("nodes").and_then(|v| v.as_array()),
        obj.get("links").and_then(|v| v.as_array()),
    ) {
        // UI Workflow JSON format
        let mut link_map: HashMap<i64, (String, i64)> = HashMap::new();
        for lk in links_arr {
            if let Some(arr) = lk.as_array() {
                if arr.len() >= 3 {
                    if let (Some(lid), Some(orig_id), Some(orig_slot)) =
                        (arr[0].as_i64(), arr[1].as_i64(), arr[2].as_i64())
                    {
                        link_map.insert(lid, (orig_id.to_string(), orig_slot));
                    }
                }
            }
        }

        let mut graph = HashMap::new();
        for node_val in nodes_arr {
            let Some(nobj) = node_val.as_object() else {
                continue;
            };
            let id = match nobj.get("id").and_then(|v| v.as_i64()) {
                Some(i) => i.to_string(),
                None => continue,
            };
            let class_type = nobj
                .get("type")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let mut inputs = HashMap::new();

            let mut linked_names = HashSet::new();
            if let Some(inp_arr) = nobj.get("inputs").and_then(|v| v.as_array()) {
                for inp in inp_arr {
                    if let Some(iobj) = inp.as_object() {
                        if let (Some(name), Some(lid)) = (
                            iobj.get("name").and_then(|v| v.as_str()),
                            iobj.get("link").and_then(|v| v.as_i64()),
                        ) {
                            linked_names.insert(name.to_string());
                            if let Some((orig, slot)) = link_map.get(&lid) {
                                inputs.insert(name.to_string(), serde_json::json!([orig, slot]));
                            }
                        }
                    }
                }
            }

            if let Some(w_arr) = nobj.get("widgets_values").and_then(|v| v.as_array()) {
                let widget_names = widget_names_for_type(&class_type);
                for (idx, wname) in widget_names.iter().enumerate() {
                    if !linked_names.contains(*wname) {
                        if let Some(wval) = w_arr.get(idx) {
                            inputs.insert((*wname).to_string(), wval.clone());
                        }
                    }
                }
            }

            graph.insert(id, UnifiedNode { class_type, inputs });
        }
        if !graph.is_empty() {
            return Some(graph);
        }
    }

    // API Prompt JSON format: { "3": { "class_type": "KSampler", "inputs": { ... } }, ... }
    let mut graph = HashMap::new();
    for (id, node_val) in obj {
        if let Some(nobj) = node_val.as_object() {
            if let (Some(ct), Some(inps)) = (
                nobj.get("class_type").and_then(|v| v.as_str()),
                nobj.get("inputs").and_then(|v| v.as_object()),
            ) {
                let mut inputs = HashMap::new();
                for (k, v) in inps {
                    inputs.insert(k.clone(), v.clone());
                }
                graph.insert(
                    id.clone(),
                    UnifiedNode {
                        class_type: ct.to_string(),
                        inputs,
                    },
                );
            }
        }
    }
    if graph.is_empty() {
        None
    } else {
        Some(graph)
    }
}

fn linked_target(val: &Value) -> Option<&str> {
    val.as_array()
        .and_then(|a| a.first())
        .and_then(|v| v.as_str())
        .or_else(|| val.as_array().and_then(|a| a.first()).and_then(|_| None))
}

fn resolve_linked_id(graph: &HashMap<String, UnifiedNode>, val: &Value) -> Option<String> {
    let mut cur = linked_target(val)?.to_string();
    for _ in 0..8 {
        if let Some(node) = graph.get(&cur) {
            if node.class_type == "Reroute" {
                if let Some(next_v) = node.inputs.values().next() {
                    if let Some(nid) = linked_target(next_v) {
                        cur = nid.to_string();
                        continue;
                    }
                }
            }
        }
        return Some(cur);
    }
    Some(cur)
}

fn resolve_text_input(
    graph: &HashMap<String, UnifiedNode>,
    val: &Value,
    visited: &mut HashSet<String>,
) -> Option<String> {
    if let Some(s) = val.as_str() {
        return Some(s.to_string());
    }
    let nid = resolve_linked_id(graph, val)?;
    if !visited.insert(nid.clone()) || visited.len() > 128 {
        return None;
    }
    let node = graph.get(&nid)?;
    for key in ["text", "user_prompt", "value", "string", "prompt"] {
        if let Some(v) = node.inputs.get(key) {
            if let Some(s) = resolve_text_input(graph, v, visited) {
                return Some(s);
            }
        }
    }
    None
}

fn resolve_scalar_str(graph: &HashMap<String, UnifiedNode>, val: &Value) -> Option<String> {
    let mut current = val;
    let mut visited = HashSet::new();
    loop {
        if let Some(s) = current.as_str() {
            return Some(s.to_string());
        }
        if current.is_number() {
            return Some(current.to_string());
        }
        let nid = resolve_linked_id(graph, current)?;
        if !visited.insert(nid.clone()) || visited.len() > 128 {
            return None;
        }
        current = graph.get(&nid)?.inputs.get("value")?;
    }
}

fn resolve_scalar_i64(graph: &HashMap<String, UnifiedNode>, val: &Value) -> Option<i64> {
    val.as_i64()
        .or_else(|| val.as_f64().map(|f| f.round() as i64))
        .or_else(|| resolve_scalar_str(graph, val).and_then(|s| s.parse::<i64>().ok()))
}

fn resolve_scalar_f64(graph: &HashMap<String, UnifiedNode>, val: &Value) -> Option<f64> {
    val.as_f64()
        .or_else(|| val.as_i64().map(|n| n as f64))
        .or_else(|| resolve_scalar_str(graph, val).and_then(|s| s.parse::<f64>().ok()))
}

#[derive(Default)]
struct ModelTrace {
    model: Option<String>,
    shift: Option<f64>,
    loras: Vec<InspectedLora>,
}

fn trace_model_chain(
    graph: &HashMap<String, UnifiedNode>,
    val: &Value,
    visited: &mut HashSet<String>,
    out: &mut ModelTrace,
) {
    let Some(nid) = resolve_linked_id(graph, val) else {
        return;
    };
    if !visited.insert(nid.clone()) || visited.len() > 128 {
        return;
    }
    let Some(node) = graph.get(&nid) else {
        return;
    };

    match node.class_type.as_str() {
        "CheckpointLoaderSimple" | "CheckpointLoader" => {
            if out.model.is_none() {
                out.model = node
                    .inputs
                    .get("ckpt_name")
                    .and_then(|v| resolve_scalar_str(graph, v));
            }
        }
        "UNETLoader" => {
            if out.model.is_none() {
                out.model = node
                    .inputs
                    .get("unet_name")
                    .and_then(|v| resolve_scalar_str(graph, v));
            }
        }
        "LoraLoader" | "LoraLoaderModelOnly" => {
            if let Some(name) = node
                .inputs
                .get("lora_name")
                .and_then(|v| resolve_scalar_str(graph, v))
            {
                let weight = node
                    .inputs
                    .get("strength_model")
                    .and_then(|v| resolve_scalar_f64(graph, v))
                    .unwrap_or(1.0);
                out.loras.push(InspectedLora { name, weight });
            }
        }
        "ModelSamplingAuraFlow" | "ModelSamplingSD3" | "ModelSamplingFlux" => {
            if out.shift.is_none() {
                out.shift = node
                    .inputs
                    .get("shift")
                    .and_then(|v| resolve_scalar_f64(graph, v));
            }
        }
        _ => {}
    }

    if let Some(next_model) = node.inputs.get("model") {
        trace_model_chain(graph, next_model, visited, out);
    }
}

fn trace_conditioning_texts(
    graph: &HashMap<String, UnifiedNode>,
    val: &Value,
    visited: &mut HashSet<String>,
    texts: &mut Vec<String>,
    system_prompts: &mut Vec<String>,
) {
    let Some(nid) = resolve_linked_id(graph, val) else {
        return;
    };
    if !visited.insert(nid.clone()) || visited.len() > 128 {
        return;
    }
    let Some(node) = graph.get(&nid) else {
        return;
    };

    if node.class_type == "CLIPTextEncodeLumina2" {
        if let Some(sp) = node
            .inputs
            .get("system_prompt")
            .and_then(|v| resolve_scalar_str(graph, v))
        {
            system_prompts.push(sp);
        }
        if let Some(up) = node
            .inputs
            .get("user_prompt")
            .and_then(|v| resolve_text_input(graph, v, &mut HashSet::new()))
        {
            if !up.trim().is_empty() {
                texts.push(up.trim().to_string());
            }
        }
        return;
    }

    if node.class_type.contains("TextEncode") || node.class_type.contains("CLIPText") {
        for key in ["text", "prompt", "positive", "string"] {
            if let Some(v) = node.inputs.get(key) {
                if let Some(t) = resolve_text_input(graph, v, &mut HashSet::new()) {
                    if !t.trim().is_empty() {
                        texts.push(t.trim().to_string());
                    }
                    return;
                }
            }
        }
    }

    for (_, iv) in &node.inputs {
        if iv.is_array() {
            trace_conditioning_texts(graph, iv, visited, texts, system_prompts);
        }
    }
}

fn parse_comfy_graph(
    graph: &HashMap<String, UnifiedNode>,
    raw_json: &str,
    width: Option<u32>,
    height: Option<u32>,
    kind: &str,
) -> Option<InspectionResult> {
    let mut sampler_ids: Vec<String> = graph
        .iter()
        .filter(|(_, n)| {
            matches!(
                n.class_type.as_str(),
                "KSampler" | "KSamplerAdvanced" | "SamplerCustom" | "SamplerCustomAdvanced"
            )
        })
        .map(|(id, _)| id.clone())
        .collect();
    sampler_ids.sort_by_key(|id| id.parse::<i64>().unwrap_or(i64::MAX));

    if sampler_ids.is_empty() {
        return None;
    }

    let mut stages = Vec::new();
    for sid in sampler_ids {
        let snode = &graph[&sid];
        let mut model_trace = ModelTrace::default();
        if let Some(mval) = snode.inputs.get("model") {
            trace_model_chain(graph, mval, &mut HashSet::new(), &mut model_trace);
        }

        let mut pos_texts = Vec::new();
        let mut sys_prompts = Vec::new();
        if let Some(pval) = snode.inputs.get("positive") {
            trace_conditioning_texts(
                graph,
                pval,
                &mut HashSet::new(),
                &mut pos_texts,
                &mut sys_prompts,
            );
        }
        let mut neg_texts = Vec::new();
        if let Some(nval) = snode.inputs.get("negative") {
            trace_conditioning_texts(
                graph,
                nval,
                &mut HashSet::new(),
                &mut neg_texts,
                &mut Vec::new(),
            );
        }

        let mut sampler = snode
            .inputs
            .get("sampler_name")
            .and_then(|v| resolve_scalar_str(graph, v));
        let mut scheduler = snode
            .inputs
            .get("scheduler")
            .and_then(|v| resolve_scalar_str(graph, v));
        let mut steps = snode
            .inputs
            .get("steps")
            .and_then(|v| resolve_scalar_i64(graph, v));
        let mut cfg = snode
            .inputs
            .get("cfg")
            .and_then(|v| resolve_scalar_f64(graph, v));
        let mut seed = snode
            .inputs
            .get("seed")
            .or_else(|| snode.inputs.get("noise_seed"))
            .and_then(|v| resolve_scalar_str(graph, v));

        // Handle SamplerCustomAdvanced linked guider / noise / scheduler / sampler
        if snode.class_type == "SamplerCustomAdvanced" || snode.class_type == "SamplerCustom" {
            if let Some(g_id) = snode
                .inputs
                .get("guider")
                .and_then(|v| resolve_linked_id(graph, v))
            {
                if let Some(gnode) = graph.get(&g_id) {
                    if cfg.is_none() {
                        cfg = gnode
                            .inputs
                            .get("cfg")
                            .and_then(|v| resolve_scalar_f64(graph, v));
                    }
                    if let Some(mval) = gnode.inputs.get("model") {
                        trace_model_chain(graph, mval, &mut HashSet::new(), &mut model_trace);
                    }
                    if let Some(pval) = gnode
                        .inputs
                        .get("positive")
                        .or_else(|| gnode.inputs.get("conditioning"))
                    {
                        trace_conditioning_texts(
                            graph,
                            pval,
                            &mut HashSet::new(),
                            &mut pos_texts,
                            &mut sys_prompts,
                        );
                    }
                    if let Some(nval) = gnode.inputs.get("negative") {
                        trace_conditioning_texts(
                            graph,
                            nval,
                            &mut HashSet::new(),
                            &mut neg_texts,
                            &mut Vec::new(),
                        );
                    }
                }
            }
            if let Some(sig_id) = snode
                .inputs
                .get("sigmas")
                .and_then(|v| resolve_linked_id(graph, v))
            {
                if let Some(signode) = graph.get(&sig_id) {
                    scheduler = scheduler.or_else(|| {
                        signode
                            .inputs
                            .get("scheduler")
                            .and_then(|v| resolve_scalar_str(graph, v))
                    });
                    steps = steps.or_else(|| {
                        signode
                            .inputs
                            .get("steps")
                            .and_then(|v| resolve_scalar_i64(graph, v))
                    });
                    if let Some(mval) = signode.inputs.get("model") {
                        trace_model_chain(graph, mval, &mut HashSet::new(), &mut model_trace);
                    }
                }
            }
            if let Some(samp_id) = snode
                .inputs
                .get("sampler")
                .and_then(|v| resolve_linked_id(graph, v))
            {
                if let Some(sampnode) = graph.get(&samp_id) {
                    sampler = sampler.or_else(|| {
                        sampnode
                            .inputs
                            .get("sampler_name")
                            .and_then(|v| resolve_scalar_str(graph, v))
                    });
                }
            }
            if let Some(noise_id) = snode
                .inputs
                .get("noise")
                .and_then(|v| resolve_linked_id(graph, v))
            {
                if let Some(nnode) = graph.get(&noise_id) {
                    seed = seed.or_else(|| {
                        nnode
                            .inputs
                            .get("noise_seed")
                            .and_then(|v| resolve_scalar_str(graph, v))
                    });
                }
            }
        }

        // Latent size trace
        let mut size = width.zip(height).map(|(w, h)| format!("{w}x{h}"));
        if let Some(lid) = snode
            .inputs
            .get("latent_image")
            .and_then(|v| resolve_linked_id(graph, v))
        {
            if let Some(lnode) = graph.get(&lid) {
                if let (Some(lw), Some(lh)) = (
                    lnode
                        .inputs
                        .get("width")
                        .and_then(|v| resolve_scalar_i64(graph, v)),
                    lnode
                        .inputs
                        .get("height")
                        .and_then(|v| resolve_scalar_i64(graph, v)),
                ) {
                    size = Some(format!("{lw}x{lh}"));
                }
            }
        }

        let mut extra = Vec::new();
        for sp in sys_prompts {
            extra.push(("System Prompt".into(), sp));
        }
        model_trace.loras.reverse();

        stages.push(InspectedStage {
            stage_name: format!("{} (#{})", snode.class_type, sid),
            positive_prompt: pos_texts.join(", "),
            negative_prompt: neg_texts.join(", "),
            model: model_trace.model,
            sampler,
            scheduler,
            steps,
            cfg,
            seed,
            size,
            shift: model_trace.shift,
            loras: model_trace.loras,
            extra_fields: extra,
        });
    }

    let first_model = stages
        .first()
        .and_then(|s| s.model.as_deref())
        .unwrap_or("");
    let suggested = Some(guess_schema_from_model_name(first_model, false, false));

    Some(InspectionResult {
        source_kind: kind.to_string(),
        suggested_schema_id: suggested,
        width,
        height,
        stages,
        raw_metadata: raw_json.to_string(),
    })
}

fn scan_exif_user_comment(bytes: &[u8]) -> Option<String> {
    if let Some(pos) = bytes.windows(8).position(|w| w == b"UNICODE\0") {
        let start = pos + 8;
        let slice = &bytes[start..bytes.len().min(start + 16384)];
        let end = slice
            .chunks_exact(2)
            .position(|c| c == [0, 0])
            .map(|i| i * 2)
            .unwrap_or(slice.len() - (slice.len() % 2));
        let u16s: Vec<u16> = slice[..end]
            .chunks_exact(2)
            .map(|c| u16::from_be_bytes([c[0], c[1]]))
            .collect();
        if let Ok(decoded) = String::from_utf16(&u16s) {
            if decoded.contains("Steps:") || decoded.contains("Negative prompt:") {
                return Some(decoded);
            }
        }
    }
    if let Some(pos) = bytes.windows(8).position(|w| w == b"ASCII\0\0\0") {
        let start = pos + 8;
        let end = bytes[start..]
            .iter()
            .position(|&b| b == 0)
            .map(|i| start + i)
            .unwrap_or(bytes.len());
        let decoded = String::from_utf8_lossy(&bytes[start..end]).to_string();
        if decoded.contains("Steps:") || decoded.contains("Negative prompt:") {
            return Some(decoded);
        }
    }
    None
}

pub fn inspect_media_or_json(bytes: &[u8], filename_hint: &str) -> CoreResult<InspectionResult> {
    if bytes.is_empty() {
        return Err(CoreError::InvalidInput("Empty file".into()));
    }

    let hint_lower = filename_hint.to_ascii_lowercase();
    let trimmed_text = std::str::from_utf8(bytes).ok().map(str::trim);

    // 1. Direct JSON (ComfyUI workflow/API or NovelAI JSON)
    if hint_lower.ends_with(".json") || trimmed_text.map(|s| s.starts_with('{')).unwrap_or(false) {
        let raw = trimmed_text.ok_or_else(|| CoreError::Parse("Invalid UTF-8 JSON".into()))?;
        let val: Value = serde_json::from_str(raw)?;
        if let Some(graph) = build_comfy_graph(&val) {
            if let Some(res) = parse_comfy_graph(&graph, raw, None, None, "ComfyUI 工作流 JSON")
            {
                return Ok(res);
            }
        }
        if let Some(res) = parse_novelai_comment(raw, None, None, None, None, "NovelAI JSON") {
            return Ok(res);
        }
        return Err(CoreError::Parse(
            "未能从 JSON 中识别出 ComfyUI 采样节点或 NovelAI 参数".into(),
        ));
    }

    // 2. PNG Chunks -> Stealth PNGInfo LSB fallback
    if let Some((w, h, entries)) = read_png_chunks(bytes) {
        let mut by_key: HashMap<String, String> = HashMap::new();
        for e in &entries {
            by_key.insert(e.keyword.clone(), e.text.clone());
        }

        // NovelAI standard PNG chunk
        if let Some(comment) = by_key.get("Comment") {
            if let Some(res) = parse_novelai_comment(
                comment,
                by_key.get("Description").map(String::as_str),
                by_key.get("Source").map(String::as_str),
                Some(w),
                Some(h),
                "NovelAI PNG (标准文本块)",
            ) {
                return Ok(res);
            }
        }

        // ComfyUI PNG chunk (prompt preferred, workflow fallback)
        for prompt_json in [by_key.get("prompt"), by_key.get("workflow")]
            .into_iter()
            .flatten()
        {
            if let Ok(val) = serde_json::from_str::<Value>(prompt_json) {
                if let Some(graph) = build_comfy_graph(&val) {
                    if let Some(res) = parse_comfy_graph(
                        &graph,
                        prompt_json,
                        Some(w),
                        Some(h),
                        "ComfyUI PNG (内嵌节点图)",
                    ) {
                        return Ok(res);
                    }
                }
            }
        }

        // A1111 / Forge `parameters`
        if let Some(params) = by_key.get("parameters") {
            if let Some(res) = parse_a1111_parameters(params, Some(w), Some(h), "WebUI / Forge PNG")
            {
                return Ok(res);
            }
        }

        // Fallback: Stealth PNGInfo LSB steganography
        if let Some(stealth_payload) = decode_stealth_pnginfo(bytes) {
            if let Some(res) = parse_novelai_comment(
                &stealth_payload,
                None,
                None,
                Some(w),
                Some(h),
                "NovelAI Stealth PNGInfo (LSB 隐写还原)",
            ) {
                return Ok(res);
            }
            if let Some(res) = parse_a1111_parameters(
                &stealth_payload,
                Some(w),
                Some(h),
                "Stealth PNGInfo (WebUI LSB 隐写还原)",
            ) {
                return Ok(res);
            }
            return Ok(InspectionResult {
                source_kind: "Stealth PNGInfo (原始文本)".into(),
                suggested_schema_id: None,
                width: Some(w),
                height: Some(h),
                stages: vec![InspectedStage {
                    stage_name: "Stealth 载荷".into(),
                    positive_prompt: stealth_payload.clone(),
                    negative_prompt: String::new(),
                    model: None,
                    sampler: None,
                    scheduler: None,
                    steps: None,
                    cfg: None,
                    seed: None,
                    size: Some(format!("{w}x{h}")),
                    shift: None,
                    loras: Vec::new(),
                    extra_fields: Vec::new(),
                }],
                raw_metadata: stealth_payload,
            });
        }

        let summary = entries
            .iter()
            .map(|e| format!("{}: {}", e.keyword, e.text))
            .collect::<Vec<_>>()
            .join("\n");
        return Err(CoreError::Parse(if summary.is_empty() {
            "该 PNG 图片未包含标准 AI 生成块或 Stealth PNGInfo 隐写数据".into()
        } else {
            format!("未识别出标准生图参数（发现文本块：{}）", summary)
        }));
    }

    // 3. JPEG / WebP EXIF UserComment fallback
    if let Some(comment) = scan_exif_user_comment(bytes) {
        let dims = image::load_from_memory(bytes)
            .ok()
            .map(|img| img.dimensions());
        if let Some(res) = parse_a1111_parameters(
            &comment,
            dims.map(|d| d.0),
            dims.map(|d| d.1),
            "JPEG / WebP EXIF 参数",
        ) {
            return Ok(res);
        }
    }

    Err(CoreError::Parse(
        "未在该文件中检测到 AI 生图元数据（可能已被社交软件重压缩抹除）".into(),
    ))
}

/// Test / encoding helper: embeds a stealth_pngcomp payload into an RGBA PNG byte vector.
pub fn encode_stealth_pngcomp_for_test(
    rgba: &mut image::RgbaImage,
    json_payload: &str,
) -> CoreResult<Vec<u8>> {
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::Write;

    let mut enc = GzEncoder::new(Vec::new(), Compression::default());
    enc.write_all(json_payload.as_bytes())?;
    let gz = enc.finish()?;

    let mut stream = Vec::new();
    stream.extend_from_slice(b"stealth_pngcomp");
    let bit_len = (gz.len() * 8) as u32;
    stream.extend_from_slice(&bit_len.to_be_bytes());
    stream.extend_from_slice(&gz);

    let (w, h) = rgba.dimensions();
    if stream.len() * 8 > (w * h) as usize {
        return Err(CoreError::InvalidInput(
            "Image too small for stealth payload".into(),
        ));
    }

    let mut bit_idx = 0usize;
    'outer: for x in 0..w {
        for y in 0..h {
            let byte_idx = bit_idx / 8;
            if byte_idx >= stream.len() {
                break 'outer;
            }
            let bit_in_byte = 7 - (bit_idx % 8);
            let bit = (stream[byte_idx] >> bit_in_byte) & 1;
            let px = rgba.get_pixel_mut(x, y);
            px.0[3] = (px.0[3] & 0xFE) | bit;
            bit_idx += 1;
        }
    }

    let mut out = Vec::new();
    let dyn_img = image::DynamicImage::ImageRgba8(rgba.clone());
    dyn_img
        .write_to(&mut std::io::Cursor::new(&mut out), ImageFormat::Png)
        .map_err(|e| CoreError::Io(std::io::Error::other(e.to_string())))?;
    Ok(out)
}
