use crate::models::{ParamFieldDef, ParamFieldType, PlatformSchema, PromptSyntax};
use serde_json::json;

fn slider(
    key: &str,
    label: &str,
    default: f64,
    min: f64,
    max: f64,
    step: f64,
    rec_min: Option<f64>,
    rec_max: Option<f64>,
    hint: Option<&str>,
) -> ParamFieldDef {
    ParamFieldDef {
        key: key.to_string(),
        label: label.to_string(),
        field_type: ParamFieldType::Slider,
        default_value: json!(default),
        min: Some(min),
        max: Some(max),
        step: Some(step),
        recommended_min: rec_min,
        recommended_max: rec_max,
        options: Vec::new(),
        resolution_presets: Vec::new(),
        hint: hint.map(str::to_string),
    }
}

fn stepper(
    key: &str,
    label: &str,
    default: i64,
    min: f64,
    max: f64,
    rec_min: Option<f64>,
    rec_max: Option<f64>,
    hint: Option<&str>,
) -> ParamFieldDef {
    ParamFieldDef {
        key: key.to_string(),
        label: label.to_string(),
        field_type: ParamFieldType::Stepper,
        default_value: json!(default),
        min: Some(min),
        max: Some(max),
        step: Some(1.0),
        recommended_min: rec_min,
        recommended_max: rec_max,
        options: Vec::new(),
        resolution_presets: Vec::new(),
        hint: hint.map(str::to_string),
    }
}

fn select_field(key: &str, label: &str, default: &str, options: &[&str], hint: Option<&str>) -> ParamFieldDef {
    ParamFieldDef {
        key: key.to_string(),
        label: label.to_string(),
        field_type: ParamFieldType::Select,
        default_value: json!(default),
        min: None,
        max: None,
        step: None,
        recommended_min: None,
        recommended_max: None,
        options: options.iter().map(|s| (*s).to_string()).collect(),
        resolution_presets: Vec::new(),
        hint: hint.map(str::to_string),
    }
}

fn toggle(key: &str, label: &str, default: bool, hint: Option<&str>) -> ParamFieldDef {
    ParamFieldDef {
        key: key.to_string(),
        label: label.to_string(),
        field_type: ParamFieldType::Toggle,
        default_value: json!(default),
        min: None,
        max: None,
        step: None,
        recommended_min: None,
        recommended_max: None,
        options: Vec::new(),
        resolution_presets: Vec::new(),
        hint: hint.map(str::to_string),
    }
}

fn resolution(default: &str, presets: &[&str]) -> ParamFieldDef {
    ParamFieldDef {
        key: "resolution".to_string(),
        label: "分辨率".to_string(),
        field_type: ParamFieldType::Resolution,
        default_value: json!(default),
        min: None,
        max: None,
        step: None,
        recommended_min: None,
        recommended_max: None,
        options: Vec::new(),
        resolution_presets: presets.iter().map(|s| (*s).to_string()).collect(),
        hint: None,
    }
}

fn text_field(key: &str, label: &str, default: &str, hint: Option<&str>) -> ParamFieldDef {
    ParamFieldDef {
        key: key.to_string(),
        label: label.to_string(),
        field_type: ParamFieldType::Text,
        default_value: json!(default),
        min: None,
        max: None,
        step: None,
        recommended_min: None,
        recommended_max: None,
        options: Vec::new(),
        resolution_presets: Vec::new(),
        hint: hint.map(str::to_string),
    }
}

fn lora_list(hint: Option<&str>) -> ParamFieldDef {
    ParamFieldDef {
        key: "loras".to_string(),
        label: "LoRA 栈".to_string(),
        field_type: ParamFieldType::LoraList,
        default_value: json!([]),
        min: Some(-2.0),
        max: Some(2.0),
        step: Some(0.05),
        recommended_min: None,
        recommended_max: None,
        options: Vec::new(),
        resolution_presets: Vec::new(),
        hint: hint.map(str::to_string),
    }
}

pub fn builtin_schemas() -> Vec<PlatformSchema> {
    let ts = 1_760_000_000_i64;
    let nai_updated_at = 1_794_960_000_000;
    let nai_res = &["832x1216", "1216x832", "1024x1024", "768x1280"];
    let xl_res = &["832x1216", "1216x832", "1024x1024", "768x1344"];
    let nai_samplers = &["DPM++ 2M", "Euler_a", "Euler", "DPM++ 2S Ancestral", "DPM++ SDE"];
    let nai_schedules = &["karras", "native", "exponential", "polyexponential"];

    vec![
        PlatformSchema {
            id: "nai_v5".into(),
            platform: "NovelAI".into(),
            model_name: "NovelAI Diffusion V5".into(),
            default_syntax: PromptSyntax::NaiColon,
            is_builtin: true,
            updated_at: nai_updated_at,
            deleted: false,
            fields: vec![
                select_field("sampler", "采样器 (Sampler)", "DPM++ 2M", nai_samplers, None),
                select_field("noise_schedule", "噪声调度器", "karras", nai_schedules, None),
                stepper("steps", "步数 (Steps)", 28, 1.0, 50.0, Some(28.0), Some(35.0), Some("Opus 档标准尺寸 ≤28 步免 Anlas")),
                slider("cfg", "Prompt Guidance", 5.5, 1.0, 10.0, 0.1, Some(5.0), Some(6.5), Some("V5 对高 Guidance 较敏感，推荐 5.0–6.5")),
                slider("cfg_rescale", "Guidance Rescale", 0.0, 0.0, 1.0, 0.1, Some(0.0), Some(0.4), Some("高引导时防过曝/颜色过饱和")),
                resolution("832x1216", nai_res),
                toggle("quality_toggle", "内置 Quality Tags", true, Some("开启时避免再堆砌重复 masterpiece")),
                toggle("decrisper", "Decrisper", false, None),
                toggle("smea", "SMEA", false, Some("高分辨率防多头防崩")),
                toggle("smea_dyn", "SMEA DYN", false, Some("复杂构图动态防崩")),
                text_field("char_positioning_note", "角色定位框备注", "", Some("V5 最高支持 22 个角色画布定位框")),
            ],
        },
        PlatformSchema {
            id: "nai_v4_5".into(),
            platform: "NovelAI".into(),
            model_name: "NovelAI Diffusion V4.5".into(),
            default_syntax: PromptSyntax::NaiColon,
            is_builtin: true,
            updated_at: nai_updated_at,
            deleted: false,
            fields: vec![
                select_field("variant", "数据集变体", "Full", &["Full", "Curated"], None),
                select_field("sampler", "采样器 (Sampler)", "DPM++ 2M", nai_samplers, None),
                select_field("noise_schedule", "噪声调度器", "karras", nai_schedules, None),
                stepper("steps", "步数 (Steps)", 28, 1.0, 50.0, Some(25.0), Some(32.0), Some("Opus 档标准尺寸 ≤28 步免 Anlas")),
                slider("cfg", "Prompt Guidance", 5.5, 1.0, 10.0, 0.1, Some(5.0), Some(6.5), None),
                slider("cfg_rescale", "Guidance Rescale", 0.0, 0.0, 1.0, 0.1, Some(0.0), Some(0.4), None),
                resolution("832x1216", nai_res),
                toggle("quality_toggle", "内置 Quality Tags", true, None),
                toggle("decrisper", "Decrisper", false, None),
                toggle("smea", "SMEA", false, None),
                toggle("smea_dyn", "SMEA DYN", false, None),
                text_field("vibe_transfer_note", "Vibe Transfer 备注", "", Some("记录参考图风格权重与信息提取度")),
            ],
        },
        PlatformSchema {
            id: "nai_v3".into(),
            platform: "NovelAI".into(),
            model_name: "NovelAI Diffusion V3".into(),
            default_syntax: PromptSyntax::NaiBraces,
            is_builtin: true,
            updated_at: nai_updated_at,
            deleted: false,
            fields: vec![
                select_field("sampler", "采样器 (Sampler)", "Euler_a", nai_samplers, None),
                select_field("noise_schedule", "噪声调度器", "native", nai_schedules, None),
                stepper("steps", "步数 (Steps)", 28, 1.0, 50.0, Some(23.0), Some(28.0), None),
                slider("cfg", "Prompt Guidance", 5.5, 1.0, 11.0, 0.1, Some(5.0), Some(7.0), None),
                slider("cfg_rescale", "Guidance Rescale", 0.0, 0.0, 1.0, 0.1, None, None, None),
                resolution("832x1216", nai_res),
                toggle("quality_toggle", "内置 Quality Tags", true, None),
                toggle("decrisper", "Decrisper", false, None),
                toggle("smea", "SMEA", true, None),
                toggle("smea_dyn", "SMEA DYN", false, None),
            ],
        },
        PlatformSchema {
            id: "comfy_anima_base".into(),
            platform: "ComfyUI".into(),
            model_name: "Anima (Base / Aesthetic)".into(),
            default_syntax: PromptSyntax::AnimaAt,
            is_builtin: true,
            updated_at: ts,
            deleted: false,
            fields: vec![
                select_field("sampler", "采样器 (Sampler)", "euler", &["euler", "dpmpp_2m", "dpmpp_2m_sde"], None),
                select_field("scheduler", "调度器 (Scheduler)", "normal", &["normal", "karras", "beta"], None),
                stepper("steps", "步数 (Steps)", 25, 1.0, 50.0, Some(20.0), Some(30.0), Some("Base / Aesthetic 推荐 20–30 步")),
                slider("cfg", "CFG Scale", 4.5, 1.0, 10.0, 0.1, Some(3.5), Some(6.5), Some("Qwen3 编码器在低 CFG 下响应强劲")),
                resolution("832x1216", &["832x1216", "1024x1024", "1216x832"]),
                lora_list(None),
            ],
        },
        PlatformSchema {
            id: "comfy_anima_turbo".into(),
            platform: "ComfyUI".into(),
            model_name: "Anima (Turbo)".into(),
            default_syntax: PromptSyntax::AnimaAt,
            is_builtin: true,
            updated_at: ts,
            deleted: false,
            fields: vec![
                select_field("sampler", "采样器 (Sampler)", "euler", &["euler", "dpmpp_2m"], None),
                select_field("scheduler", "调度器 (Scheduler)", "normal", &["normal", "karras", "beta"], None),
                stepper("steps", "步数 (Steps)", 10, 4.0, 20.0, Some(8.0), Some(12.0), Some("Turbo 蒸馏版推荐 8–12 步")),
                slider("cfg", "CFG Scale", 1.5, 1.0, 4.0, 0.1, Some(1.0), Some(2.0), Some("蒸馏版请保持低 CFG (1.0–2.0)")),
                resolution("832x1216", &["832x1216", "1024x1024", "1216x832"]),
                lora_list(None),
            ],
        },
        PlatformSchema {
            id: "comfy_moss".into(),
            platform: "ComfyUI".into(),
            model_name: "MOSS-Image".into(),
            default_syntax: PromptSyntax::MossSpace,
            is_builtin: true,
            updated_at: ts,
            deleted: false,
            fields: vec![
                select_field("sampler", "采样器 (Sampler)", "euler", &["euler", "heun"], None),
                slider("shift", "Flow Shift", 5.0, 0.5, 12.0, 0.5, Some(4.5), Some(5.5), Some("Flow-Matching 动漫推荐 Shift = 5")),
                stepper("steps", "步数 (Steps)", 30, 8.0, 60.0, Some(25.0), Some(50.0), None),
                slider("cfg", "CFG Scale", 2.8, 1.0, 6.0, 0.1, Some(2.5), Some(3.0), None),
                resolution("1024x1024", &["1024x1024", "832x1216", "1216x832"]),
                text_field("trigger_words", "媒介 / 触发词", "Anime-style digital illustration", Some("MOSS 默认偏写实，建议声明二次元媒介或 d3style 等触发词")),
                lora_list(Some("常搭动漫风格 LoRA（权重 0.8–1.0）")),
                toggle("slg", "SLG (Skip Layer Guidance)", false, Some("降低 3D/塑料油腻感")),
                toggle("prompt_enhancer", "Prompt Enhancer 自动扩写", false, None),
            ],
        },
        PlatformSchema {
            id: "comfy_illustrious".into(),
            platform: "ComfyUI".into(),
            model_name: "Illustrious XL".into(),
            default_syntax: PromptSyntax::SdParens,
            is_builtin: true,
            updated_at: ts,
            deleted: false,
            fields: vec![
                select_field("sampler", "采样器 (Sampler)", "euler_ancestral", &["euler_ancestral", "dpmpp_2m", "euler"], None),
                select_field("scheduler", "调度器 (Scheduler)", "karras", &["karras", "sgm_uniform", "normal"], None),
                stepper("steps", "步数 (Steps)", 24, 10.0, 45.0, Some(20.0), Some(28.0), None),
                slider("cfg", "CFG Scale", 4.5, 1.5, 8.0, 0.1, Some(3.0), Some(5.0), None),
                select_field("prediction_type", "Prediction Type", "epsilon", &["epsilon", "v_prediction"], None),
                resolution("832x1216", xl_res),
                lora_list(None),
            ],
        },
        PlatformSchema {
            id: "comfy_noobai_vpred".into(),
            platform: "ComfyUI".into(),
            model_name: "NoobAI-XL (V-Pred / Eps)".into(),
            default_syntax: PromptSyntax::SdParens,
            is_builtin: true,
            updated_at: ts,
            deleted: false,
            fields: vec![
                select_field("prediction_type", "Prediction Type", "v_prediction", &["v_prediction", "epsilon"], Some("V-Pred 底模务必选 v_prediction")),
                select_field("sampler", "采样器 (Sampler)", "euler", &["euler", "euler_ancestral", "dpmpp_2m"], None),
                select_field("scheduler", "调度器 (Scheduler)", "sgm_uniform", &["normal", "sgm_uniform", "karras"], None),
                stepper("steps", "步数 (Steps)", 26, 10.0, 45.0, Some(20.0), Some(28.0), None),
                slider("cfg", "CFG Scale", 4.0, 1.5, 7.0, 0.1, Some(3.0), Some(5.0), None),
                resolution("832x1216", xl_res),
                lora_list(None),
            ],
        },
        PlatformSchema {
            id: "comfy_lumina2".into(),
            platform: "ComfyUI".into(),
            model_name: "Lumina-Image 2.0".into(),
            default_syntax: PromptSyntax::SdParens,
            is_builtin: true,
            updated_at: ts,
            deleted: false,
            fields: vec![
                select_field("system_prompt", "System Prompt 预设", "superior", &["superior", "alignment", "custom"], None),
                select_field("sampler", "采样器 (Sampler)", "euler", &["euler", "res_multistep"], None),
                select_field("scheduler", "调度器 (Scheduler)", "simple", &["simple", "normal"], None),
                stepper("steps", "步数 (Steps)", 28, 10.0, 50.0, Some(20.0), Some(36.0), None),
                slider("cfg", "CFG Scale", 4.0, 1.0, 7.0, 0.1, Some(3.5), Some(5.0), None),
                slider("shift", "Shift", 6.0, 1.0, 10.0, 0.5, Some(4.0), Some(7.0), None),
                resolution("1024x1024", &["1024x1024", "832x1216", "1216x832"]),
                lora_list(None),
            ],
        },
        PlatformSchema {
            id: "comfy_chroma".into(),
            platform: "ComfyUI".into(),
            model_name: "Chroma".into(),
            default_syntax: PromptSyntax::SdParens,
            is_builtin: true,
            updated_at: ts,
            deleted: false,
            fields: vec![
                select_field("sampler", "采样器 (Sampler)", "euler", &["euler", "heun", "dpmpp_2m"], None),
                select_field("scheduler", "调度器 (Scheduler)", "simple", &["simple", "beta", "normal"], None),
                stepper("steps", "步数 (Steps)", 26, 10.0, 50.0, Some(22.0), Some(30.0), None),
                slider("cfg", "CFG Scale", 3.5, 1.0, 7.0, 0.1, Some(3.0), Some(4.5), None),
                slider("start_sigma", "Radiance Start Sigma", 1.0, 0.0, 1.0, 0.05, None, None, None),
                slider("end_sigma", "Radiance End Sigma", 0.0, 0.0, 1.0, 0.05, None, None, None),
                resolution("1024x1024", &["1024x1024", "832x1216", "1344x768"]),
                lora_list(None),
            ],
        },
        PlatformSchema {
            id: "webui_forge".into(),
            platform: "WebUI / Forge".into(),
            model_name: "通用 SD / SDXL".into(),
            default_syntax: PromptSyntax::SdParens,
            is_builtin: true,
            updated_at: ts,
            deleted: false,
            fields: vec![
                select_field("sampler", "采样器 (Sampler)", "Euler a", &["Euler a", "DPM++ 2M", "DPM++ 2M SDE", "UniPC"], None),
                select_field("scheduler", "调度器 (Scheduler)", "Karras", &["Automatic", "Karras", "Exponential", "SGM Uniform"], None),
                stepper("steps", "步数 (Steps)", 28, 1.0, 60.0, Some(20.0), Some(35.0), None),
                slider("cfg", "CFG Scale", 6.0, 1.0, 15.0, 0.5, Some(4.5), Some(7.5), None),
                resolution("832x1216", &["832x1216", "1024x1024", "512x768"]),
                toggle("hires_fix", "Hires. fix 高分修复", false, None),
                lora_list(None),
            ],
        },
    ]
}
