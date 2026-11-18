# StyleLoom（画风织机）

StyleLoom 是一款 AI 绘画素材管理工具。把参考图、画师串、正负提示词和模型参数放在同一张卡片里，在画册中查找、比较和复用。

## 下载

在 [Releases](https://github.com/ZZZdragondYNGPHX/StyleLoom/releases) 下载对应版本。安装包附有 SHA-256 校验文件。

- **Windows x64** · 解压 `StyleLoom-windows-x64.zip`，运行 `styleloom_app.exe`。
- **Android** · 安装 `StyleLoom-android-release.apk`，支持 `arm64-v8a` 和 `x86_64`。

## 功能

- **画册** · 按模型保存配方和预览图，快速复制提示词。支持 NovelAI、ComfyUI 和 WebUI / Forge 等内置模型模板，也可自定义参数。
- **底模参数** · 点击 NovelAI 的 `Prompt Guidance` 或 `Guidance Rescale` 数字即可输入精确值。拖动 `Guidance Rescale` 滑块时，每格调整 `0.1`。
- **提示词片段** · 将常用提示词保存为可复用片段，在卡片中组合、排序和调权，也可切换到纯文本编辑或按目标平台的语法复制。
- **原图解析** · 在本地查看图片里保存的生成参数。支持 PNG 文本及 Stealth 元数据、WebUI EXIF 和 ComfyUI 工作流 JSON。可在桌面拖入文件，或从 Android 的分享菜单打开图片。
- **备份与同步** · 用 `.slpack` 文件备份或迁移全部或选中的卡片，也可通过 WebDAV 在设备间增量同步。

## 从源码构建

界面位于 `app/`，Rust 核心位于 `rust/`。项目使用 Flutter 3.50.0 和 Rust stable。

### Windows

准备 Visual Studio 的「使用 C++ 的桌面开发」工作负载、Rust MSVC 工具链和 Flutter，然后在仓库根目录运行。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
```

便携包输出到 `dist/StyleLoom-windows-x64.zip`。本地调试可在 `app/` 下运行 `flutter run -d windows`。

### Android

在 Linux 上准备 Flutter、Rust、JDK 21、Android SDK 和 NDK 28.2.13676358，然后在仓库根目录运行。

```bash
bash scripts/build-android.sh
```

安装包输出到 `dist/StyleLoom-android-release.apk`。默认使用调试签名。使用自己的签名时，设置 `STYLELOOM_KEYSTORE_PATH`、`STYLELOOM_KEYSTORE_PASSWORD`、`STYLELOOM_KEY_ALIAS` 和 `STYLELOOM_KEY_PASSWORD`。

### 测试

```bash
cargo test --locked --manifest-path rust/Cargo.toml
```

在 Linux 上运行 Flutter 测试前，先构建 Rust 动态库。

```bash
cargo build --locked --release --manifest-path rust/Cargo.toml
cd app
flutter analyze
flutter test
```
