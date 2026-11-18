use crate::models::{CoreError, CoreResult, ImageAsset};
use chrono::Utc;
use image::imageops::FilterType;
use image::{ColorType, ImageFormat, ImageReader};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Cursor;
use std::path::Path;

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}

fn format_ext(fmt: ImageFormat) -> Option<&'static str> {
    match fmt {
        ImageFormat::Png => Some("png"),
        ImageFormat::Jpeg => Some("jpg"),
        ImageFormat::WebP => Some("webp"),
        _ => None,
    }
}

fn has_non_opaque_alpha(img: &image::DynamicImage) -> bool {
    match img.color() {
        ColorType::Rgba8 | ColorType::Rgba16 | ColorType::La8 | ColorType::La16 => {
            let rgba = img.to_rgba8();
            rgba.pixels().any(|p| p.0[3] < 255)
        }
        _ => false,
    }
}

pub fn import_image_bytes(vault_dir: &Path, bytes: &[u8]) -> CoreResult<ImageAsset> {
    if bytes.is_empty() {
        return Err(CoreError::InvalidInput("Empty image bytes".into()));
    }

    let reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|e| CoreError::Parse(format!("Unrecognized image header: {e}")))?;
    let fmt = reader
        .format()
        .ok_or_else(|| CoreError::Parse("Unsupported image format".into()))?;
    let ext = format_ext(fmt)
        .ok_or_else(|| CoreError::InvalidInput("预览图支持 JPG、PNG 和 WebP".into()))?
        .to_string();

    let decoded = reader
        .decode()
        .map_err(|e| CoreError::Parse(format!("Failed to decode image: {e}")))?;
    let width = decoded.width();
    let height = decoded.height();

    let sha = sha256_hex(bytes);
    let prefix = &sha[..2];
    let blob_rel = format!("blobs/{prefix}/{sha}.{ext}");
    let blob_abs = vault_dir.join(&blob_rel);

    if let Some(parent) = blob_abs.parent() {
        fs::create_dir_all(parent)?;
    }
    let replace_blob = fs::read(&blob_abs).ok().as_deref() != Some(bytes);
    if replace_blob {
        fs::write(&blob_abs, bytes)?;
    }

    let thumb_ext = if has_non_opaque_alpha(&decoded) {
        "png"
    } else {
        "jpg"
    };
    let thumb_rel = format!("thumbs/{prefix}/{sha}.{thumb_ext}");
    let thumb_abs = vault_dir.join(&thumb_rel);
    if replace_blob || !fs::metadata(&thumb_abs).is_ok_and(|m| m.is_file() && m.len() > 0) {
        if let Some(parent) = thumb_abs.parent() {
            fs::create_dir_all(parent)?;
        }
        let max_side = 640_u32;
        let thumb_img = if width > max_side || height > max_side {
            decoded.resize(max_side, max_side, FilterType::Triangle)
        } else {
            decoded
        };
        if thumb_ext == "png" {
            thumb_img
                .save_with_format(&thumb_abs, ImageFormat::Png)
                .map_err(|e| CoreError::Io(std::io::Error::other(e.to_string())))?;
        } else {
            let rgb = thumb_img.to_rgb8();
            let mut out = Vec::new();
            let mut enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 88);
            enc.encode_image(&rgb)
                .map_err(|e| CoreError::Io(std::io::Error::other(e.to_string())))?;
            fs::write(&thumb_abs, out)?;
        }
    }

    Ok(ImageAsset {
        sha256: sha,
        ext,
        width,
        height,
        byte_size: bytes.len() as u64,
        blob_rel_path: blob_rel,
        thumb_rel_path: thumb_rel,
        created_at: Utc::now().timestamp(),
    })
}

pub fn ensure_thumbnail_for_blob(
    vault_dir: &Path,
    sha256: &str,
    blob_rel_path: &str,
) -> CoreResult<ImageAsset> {
    let blob_abs = vault_dir.join(blob_rel_path);
    let bytes = fs::read(&blob_abs)?;
    let mut asset = import_image_bytes(vault_dir, &bytes)?;
    asset.sha256 = sha256.to_string();
    Ok(asset)
}
