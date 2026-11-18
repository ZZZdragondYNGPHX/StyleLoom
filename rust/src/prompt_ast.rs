use crate::models::{PromptNode, PromptSyntax, TargetSyntax};
use std::collections::HashSet;
use uuid::Uuid;

fn new_id() -> String {
    Uuid::new_v4().to_string()
}

pub fn format_weight(w: f64) -> String {
    let rounded = (w * 100.0).round() / 100.0;
    let s = format!("{rounded:.2}");
    let trimmed = s.trim_end_matches('0').trim_end_matches('.');
    trimmed.to_string()
}

fn split_top_level_commas(input: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut buf = String::new();
    let mut paren_depth: i32 = 0;
    let mut brace_depth: i32 = 0;
    let mut bracket_depth: i32 = 0;
    let mut in_colons = false;
    let mut in_muted_comment = false;

    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let ch = chars[i];
        let next = chars.get(i + 1).copied();

        if ch == '\\' {
            buf.push(ch);
            if let Some(next) = next {
                buf.push(next);
                i += 1;
            }
            i += 1;
            continue;
        }

        if !in_muted_comment && ch == '/' && next == Some('*') {
            in_muted_comment = true;
            buf.push_str("/*");
            i += 2;
            continue;
        }
        if in_muted_comment && ch == '*' && next == Some('/') {
            in_muted_comment = false;
            buf.push_str("*/");
            i += 2;
            continue;
        }
        if in_muted_comment {
            buf.push(ch);
            i += 1;
            continue;
        }

        if ch == ':' && next == Some(':') {
            in_colons = !in_colons;
            buf.push_str("::");
            i += 2;
            continue;
        }

        match ch {
            '(' => paren_depth += 1,
            ')' => paren_depth = (paren_depth - 1).max(0),
            '{' => brace_depth += 1,
            '}' => brace_depth = (brace_depth - 1).max(0),
            '[' => bracket_depth += 1,
            ']' => bracket_depth = (bracket_depth - 1).max(0),
            ',' | '\n' | '，'
                if paren_depth == 0 && brace_depth == 0 && bracket_depth == 0 && !in_colons =>
            {
                let item = buf.trim().to_string();
                if !item.is_empty() {
                    parts.push(item);
                }
                buf.clear();
                i += 1;
                continue;
            }
            _ => {}
        }

        buf.push(ch);
        i += 1;
    }

    let tail = buf.trim().to_string();
    if !tail.is_empty() {
        parts.push(tail);
    }
    parts
}

fn parse_preset_marker(inner: &str) -> Option<(String, String, f64)> {
    // Format: [[preset:name|id]] or [[preset:name|id|w=1.15]] or [[preset:name]]
    let trimmed = inner.trim();
    if !(trimmed.starts_with("[[preset:") && trimmed.ends_with("]]")) {
        return None;
    }
    let body = &trimmed["[[preset:".len()..trimmed.len() - 2];
    let mut segs = body.split('|');
    let name = segs.next()?.trim().to_string();
    let snippet_id = segs
        .next()
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    let mut weight = 1.0_f64;
    if let Some(w_part) = segs.next() {
        if let Some(val) = w_part.trim().strip_prefix("w=") {
            if let Some(parsed) = val.parse::<f64>().ok().filter(|w| w.is_finite()) {
                weight = parsed;
            }
        }
    }
    Some((name, snippet_id, weight))
}

fn parse_single_segment<F>(
    raw_seg: &str,
    enabled: bool,
    lookup_snippet: &F,
    out: &mut Vec<PromptNode>,
    depth: usize,
) where
    F: Fn(&str) -> Option<(String, String, String)>,
{
    let s = raw_seg.trim();
    if s.is_empty() {
        return;
    }

    if depth >= 64 {
        out.push(PromptNode::Token {
            id: new_id(),
            text: s.to_string(),
            weight: 1.0,
            enabled,
        });
        return;
    }

    if let Some(rest) = s.strip_prefix("/*off:") {
        if let Some(inner) = rest.strip_suffix("*/") {
            parse_single_segment(inner.trim(), false, lookup_snippet, out, depth + 1);
            return;
        }
    }

    if let Some((name, sid, weight)) = parse_preset_marker(s) {
        let resolved = if !sid.is_empty() {
            lookup_snippet(&sid).or_else(|| lookup_snippet(&name))
        } else {
            lookup_snippet(&name)
        };
        let (final_id, final_name, final_raw) = match resolved {
            Some((id, rname, rraw)) => (id, rname, rraw),
            None => (sid, name, String::new()),
        };
        out.push(PromptNode::SnippetRef {
            id: new_id(),
            snippet_id: final_id,
            fallback_name: final_name,
            fallback_raw: final_raw,
            weight,
            enabled,
        });
        return;
    }

    // Check NovelAI :: syntax: e.g. `1.25::tag1, tag2::` or `{{tag::`
    if s.contains("::") {
        if let Some(colon_idx) = s.find("::") {
            let prefix = s[..colon_idx].trim();
            let rest = &s[colon_idx + 2..];
            let body = rest.strip_suffix("::").unwrap_or(rest).trim();

            if let Some(w) = prefix.parse::<f64>().ok().filter(|w| w.is_finite()) {
                parse_weighted_body(body, w, enabled, lookup_snippet, out, depth);
                return;
            } else if !prefix.is_empty()
                && (prefix.chars().all(|c| c == '{') || prefix.chars().all(|c| c == '['))
            {
                let count = prefix.chars().count() as i32;
                let w = if prefix.starts_with('{') {
                    1.05_f64.powi(count)
                } else {
                    1.05_f64.powi(-count)
                };
                parse_weighted_body(body, w, enabled, lookup_snippet, out, depth);
                return;
            }
        }
    }

    // Check curly braces `{...}`
    if s.starts_with('{') && s.ends_with('}') {
        let mut open = 0usize;
        let mut close = 0usize;
        for ch in s.chars() {
            if ch == '{' {
                open += 1;
            } else {
                break;
            }
        }
        for ch in s.chars().rev() {
            if ch == '}' {
                close += 1;
            } else {
                break;
            }
        }
        let wrapping = open.min(close);
        if wrapping > 0 && s.len() > wrapping * 2 {
            let inner = s[wrapping..s.len() - wrapping].trim();
            let w = (1.05_f64.powi(wrapping as i32) * 100.0).round() / 100.0;
            parse_weighted_body(inner, w, enabled, lookup_snippet, out, depth);
            return;
        }
    }

    // Check square brackets `[...]` (avoid matching [[preset:...]])
    if s.starts_with('[') && s.ends_with(']') && !s.starts_with("[[preset:") {
        let mut open = 0usize;
        let mut close = 0usize;
        for ch in s.chars() {
            if ch == '[' {
                open += 1;
            } else {
                break;
            }
        }
        for ch in s.chars().rev() {
            if ch == ']' {
                close += 1;
            } else {
                break;
            }
        }
        let wrapping = open.min(close);
        if wrapping > 0 && s.len() > wrapping * 2 {
            let inner = s[wrapping..s.len() - wrapping].trim();
            // Do not reinterpret A1111 alternation/scheduling `[a:b:0.5]` as weight
            if !inner.contains(':') {
                let w = (1.05_f64.powi(-(wrapping as i32)) * 100.0).round() / 100.0;
                parse_weighted_body(inner, w, enabled, lookup_snippet, out, depth);
                return;
            }
        }
    }

    // Check SD/ComfyUI parentheses `(...)` or `(tag:1.2)`
    if s.starts_with('(') && s.ends_with(')') {
        let mut open = 0usize;
        let mut close = 0usize;
        for ch in s.chars() {
            if ch == '(' {
                open += 1;
            } else {
                break;
            }
        }
        for ch in s.chars().rev() {
            if ch == ')' {
                close += 1;
            } else {
                break;
            }
        }
        let wrapping = open.min(close);
        if wrapping > 0 && s.len() > wrapping * 2 {
            let inner = s[wrapping..s.len() - wrapping].trim();
            if let Some(colon) = inner.rfind(':') {
                let maybe_num = inner[colon + 1..].trim();
                if let Some(w) = maybe_num.parse::<f64>().ok().filter(|w| w.is_finite()) {
                    let base = inner[..colon].trim();
                    let factor = 1.1_f64.powi((wrapping - 1) as i32);
                    let final_w = ((w * factor) * 100.0).round() / 100.0;
                    parse_weighted_body(base, final_w, enabled, lookup_snippet, out, depth);
                    return;
                }
            }
            let w = (1.1_f64.powi(wrapping as i32) * 100.0).round() / 100.0;
            parse_weighted_body(inner, w, enabled, lookup_snippet, out, depth);
            return;
        }
    }

    out.push(PromptNode::Token {
        id: new_id(),
        text: s.to_string(),
        weight: 1.0,
        enabled,
    });
}

fn parse_weighted_body<F>(
    body: &str,
    multiplier: f64,
    enabled: bool,
    lookup: &F,
    out: &mut Vec<PromptNode>,
    depth: usize,
) where
    F: Fn(&str) -> Option<(String, String, String)>,
{
    let start = out.len();
    for segment in split_top_level_commas(body) {
        parse_single_segment(&segment, enabled, lookup, out, depth + 1);
    }
    for node in &mut out[start..] {
        match node {
            PromptNode::Token { weight, .. } | PromptNode::SnippetRef { weight, .. } => {
                let combined = (*weight * multiplier * 100.0).round() / 100.0;
                if combined.is_finite() {
                    *weight = combined;
                }
            }
        }
    }
}

/// Parses a raw prompt string into `PromptNode`s (`Token` and `SnippetRef`).
/// `lookup_snippet` resolves either a snippet id or snippet name to `(id, name, raw_text)`.
pub fn parse_raw_to_nodes<F>(raw: &str, lookup_snippet: &F) -> Vec<PromptNode>
where
    F: Fn(&str) -> Option<(String, String, String)>,
{
    let mut out = Vec::new();
    for seg in split_top_level_commas(raw) {
        parse_single_segment(&seg, true, lookup_snippet, &mut out, 0);
    }
    out
}

fn transform_token_text(text: &str, syntax: PromptSyntax) -> String {
    let t = text.trim();
    match syntax {
        PromptSyntax::AnimaAt => {
            if let Some(artist) = t.strip_prefix("artist:") {
                let clean = artist.trim().replace(' ', "_");
                format!("@{clean}")
            } else {
                t.to_string()
            }
        }
        PromptSyntax::MossSpace => {
            let stripped = t
                .strip_prefix("artist:")
                .or_else(|| t.strip_prefix('@'))
                .unwrap_or(t);
            stripped.replace('_', " ").trim().to_string()
        }
        PromptSyntax::NaiColon | PromptSyntax::NaiBraces | PromptSyntax::SdParens => {
            if let Some(artist) = t.strip_prefix('@') {
                if !artist.is_empty() && !artist.contains(' ') {
                    return format!("artist:{artist}");
                }
            }
            t.to_string()
        }
    }
}

pub fn format_token(text: &str, weight: f64, syntax: PromptSyntax) -> String {
    let base = transform_token_text(text, syntax);
    if base.is_empty() {
        return String::new();
    }
    if (weight - 1.0).abs() < 0.005 {
        return base;
    }

    match syntax {
        PromptSyntax::NaiColon => {
            format!("{}::{}::", format_weight(weight), base)
        }
        PromptSyntax::NaiBraces => {
            let steps =
                ((weight.max(0.1).ln() / 1.05_f64.ln()).abs().round() as usize).clamp(1, 128);
            if weight > 1.0 {
                format!("{}{}{}", "{".repeat(steps), base, "}".repeat(steps))
            } else {
                format!("{}{}{}", "[".repeat(steps), base, "]".repeat(steps))
            }
        }
        PromptSyntax::SdParens | PromptSyntax::AnimaAt | PromptSyntax::MossSpace => {
            format!("({}:{})", base, format_weight(weight))
        }
    }
}

pub fn nodes_to_editable_raw(nodes: &[PromptNode], syntax: PromptSyntax) -> String {
    let mut parts = Vec::with_capacity(nodes.len());
    for node in nodes {
        match node {
            PromptNode::Token {
                text,
                weight,
                enabled,
                ..
            } => {
                let formatted = format_token(text, *weight, syntax);
                if formatted.is_empty() {
                    continue;
                }
                if *enabled {
                    parts.push(formatted);
                } else {
                    parts.push(format!("/*off: {formatted} */"));
                }
            }
            PromptNode::SnippetRef {
                snippet_id,
                fallback_name,
                weight,
                enabled,
                ..
            } => {
                let marker = if (*weight - 1.0).abs() < 0.005 {
                    format!("[[preset:{fallback_name}|{snippet_id}]]")
                } else {
                    format!(
                        "[[preset:{fallback_name}|{snippet_id}|w={}]]",
                        format_weight(*weight)
                    )
                };
                if *enabled {
                    parts.push(marker);
                } else {
                    parts.push(format!("/*off: {marker} */"));
                }
            }
        }
    }
    parts.join(", ")
}

fn expand_nodes_recursive<F>(
    nodes: &[PromptNode],
    parent_weight: f64,
    target: PromptSyntax,
    resolve_snippet: &F,
    visited: &mut HashSet<String>,
    depth: usize,
    out: &mut Vec<String>,
) where
    F: Fn(&str) -> Option<(Vec<PromptNode>, String)>,
{
    if depth > 4 {
        return;
    }
    for node in nodes {
        if !node.is_enabled() {
            continue;
        }
        match node {
            PromptNode::Token { text, weight, .. } => {
                let eff_w = ((weight * parent_weight) * 100.0).round() / 100.0;
                let formatted = format_token(text, eff_w, target);
                if !formatted.is_empty() {
                    out.push(formatted);
                }
            }
            PromptNode::SnippetRef {
                snippet_id,
                fallback_raw,
                weight,
                ..
            } => {
                if !snippet_id.is_empty() && !visited.insert(snippet_id.clone()) {
                    continue;
                }
                let eff_w = ((weight * parent_weight) * 100.0).round() / 100.0;
                if let Some((child_nodes, child_raw)) = resolve_snippet(snippet_id) {
                    if !child_nodes.is_empty() {
                        expand_nodes_recursive(
                            &child_nodes,
                            eff_w,
                            target,
                            resolve_snippet,
                            visited,
                            depth + 1,
                            out,
                        );
                    } else if !child_raw.trim().is_empty() {
                        let parsed = parse_raw_to_nodes(&child_raw, &|_| None);
                        expand_nodes_recursive(
                            &parsed,
                            eff_w,
                            target,
                            resolve_snippet,
                            visited,
                            depth + 1,
                            out,
                        );
                    }
                } else if !fallback_raw.trim().is_empty() {
                    let parsed = parse_raw_to_nodes(fallback_raw, &|_| None);
                    expand_nodes_recursive(
                        &parsed,
                        eff_w,
                        target,
                        resolve_snippet,
                        visited,
                        depth + 1,
                        out,
                    );
                }
                if !snippet_id.is_empty() {
                    visited.remove(snippet_id);
                }
            }
        }
    }
}

/// Renders nodes for clipboard copy (expanding active SnippetRefs, skipping muted items,
/// and converting every token to the requested TargetSyntax).
pub fn render_for_copy<F>(
    nodes: &[PromptNode],
    model_syntax: PromptSyntax,
    target: TargetSyntax,
    resolve_snippet: &F,
) -> String
where
    F: Fn(&str) -> Option<(Vec<PromptNode>, String)>,
{
    let effective_syntax = target.resolve(model_syntax);
    let mut visited = HashSet::new();
    let mut out = Vec::new();
    expand_nodes_recursive(
        nodes,
        1.0,
        effective_syntax,
        resolve_snippet,
        &mut visited,
        0,
        &mut out,
    );
    out.join(", ")
}

/// Implements Plan B ("一键打散"): explodes a `SnippetRef` capsule in place into standalone `Token` nodes.
pub fn ungroup_snippet_node<F>(
    nodes: &[PromptNode],
    node_id: &str,
    resolve_snippet: &F,
) -> Vec<PromptNode>
where
    F: Fn(&str) -> Option<(Vec<PromptNode>, String)>,
{
    let mut result = Vec::with_capacity(nodes.len() + 4);
    for node in nodes {
        match node {
            PromptNode::SnippetRef {
                id,
                snippet_id,
                fallback_raw,
                weight: ref_weight,
                enabled: ref_enabled,
                ..
            } if id == node_id => {
                let source_nodes = match resolve_snippet(snippet_id) {
                    Some((child_nodes, child_raw)) => {
                        if !child_nodes.is_empty() {
                            child_nodes
                        } else {
                            parse_raw_to_nodes(&child_raw, &|_| None)
                        }
                    }
                    None => parse_raw_to_nodes(fallback_raw, &|_| None),
                };
                for child in source_nodes {
                    match child {
                        PromptNode::Token {
                            text,
                            weight,
                            enabled,
                            ..
                        } => {
                            result.push(PromptNode::Token {
                                id: new_id(),
                                text,
                                weight: ((weight * ref_weight) * 100.0).round() / 100.0,
                                enabled: *ref_enabled && enabled,
                            });
                        }
                        PromptNode::SnippetRef {
                            snippet_id: cid,
                            fallback_name,
                            fallback_raw: craw,
                            weight,
                            enabled,
                            ..
                        } => {
                            result.push(PromptNode::SnippetRef {
                                id: new_id(),
                                snippet_id: cid,
                                fallback_name,
                                fallback_raw: craw,
                                weight: ((weight * ref_weight) * 100.0).round() / 100.0,
                                enabled: *ref_enabled && enabled,
                            });
                        }
                    }
                }
            }
            other => result.push(other.clone()),
        }
    }
    result
}
