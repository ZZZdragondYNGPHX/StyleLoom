# StyleLoom（画风织机）

**StyleLoom** 是一款跨 **Windows 桌面端** 与 **Android 移动端/平板端** 的 AI 绘画「**画师串预设 + 提示词预设片段 + 多平台可交互参数**」纯图极简瀑布流资产管理工作台。

> **技术内核**：`Flutter`（跨端自适应 UI 与 120Hz 瀑布流画廊） + `Rust`（零代码生成 `dart:ffi` + 后台 Isolate C-ABI 桥接、SQLite FTS5 全文库、原图与 Stealth 隐写解析、提示词 AST 转换及原生 HTTPS WebDAV 增量同步）  
> **详细方案书**：[`docs/01-proposal.md`](./docs/01-proposal.md)（`v1.0` 定稿版）

---

## 核心功能特性

1. **纯图极简画师串瀑布流**：
   - **一卡一模型**：每张画师串卡片直接存储自身的正面提示词、负面提示词、所属平台与底模、可交互参数及多张预览对比图；同配方不同模型拆为独立卡片直接并排对比（支持一键克隆到其他模型并转写语法）。
   - **极简视觉 + 表面快捷复制**：桌面端鼠标悬停 / 移动端长按卡片即可一键**复制正面提示词**、**复制负面提示词**或**转换目标权重语法后复制**。
2. **Schema 驱动的可交互动态参数面板**：
   - 开箱内置 **11 套主流模型模板**：`NovelAI Diffusion V5 / V4.5 / V3`、`ComfyUI · Anima (Base / Turbo)`、`MOSS-Image`（含 `Flow Shift`、`SLG` 与二次元媒介触发词）、`Illustrious XL`、`NoobAI-XL (V-Pred / Eps)`、`Lumina-Image 2.0`、`Chroma` 及通用 `WebUI / Forge`。
   - 支持滑块推荐安全区间高亮提示，并允许在 UI 内自由克隆或新建自定义平台与参数控件。
3. **独立「提示词预设」片段积木库（方案 B：预设胶囊块 + 一键打散）**：
   - 提示词预设作为中性可复用片段保存（支持自定义分类标签），在画师串正/负面词中可多选导入拼装为 **`[🧩 预设名]` 胶囊块**；
   - 支持可视化胶囊（拖拽排序、`±0.05` 调权、临时屏蔽单个词条或整块预设，**一键“打散”为独立词条**）↔ 纯文本源码双向切换，支持 5 种权重方言转换复制。
4. **独立原图与工作流解析查看器（Spell Inspector）**：
   - 对标 `looyun/spell` 与 `Akegarasu/stable-diffusion-inspector`，纯本地离线读取 PNG（标准 `tEXt`/`iTXt`/`zTXt` 与 **`stealth_pnginfo` / `stealth_pngcomp` / `stealth_rgbinfo` / `stealth_rgbcomp` LSB 隐写**）、WebUI EXIF 与 ComfyUI UI/API `.json` 节点图；
   - 专注清晰分栏展示与分项一键复制（支持 Android 系统分享菜单直接分享图片到 StyleLoom 与桌面端拖入解析）。
5. **双端数据同步**：
   - 离线 **`.slpack`** 归档包全库/选卡导出与按 `SHA-256` 去重导入；
   - 原生 HTTPS **WebDAV 内容寻址增量同步**（开箱内置 **Koofr** 快捷预设 `https://app.koofr.net/dav/Koofr` + 应用专用密码提示，以及通用 WebDAV 支持）。

---

## 目录结构

```text
StyleLoom/
├── docs/01-proposal.md            # v1.0 调研与技术方案书
├── rust/                          # styleloom_core Rust 核心引擎 (Cargo + SQLite FTS5)
│   ├── src/
│   │   ├── models.rs              # 核心数据模型与 FFI DTO
│   │   ├── builtin_schemas.rs     # 11 套内置平台/模型 Schema 模板
│   │   ├── prompt_ast.rs          # 胶囊 AST、SnippetRef 拼装/打散与 5 种语法互转
│   │   ├── inspector.rs           # PNG / Stealth LSB / EXIF / ComfyUI JSON 解析器
│   │   ├── media.rs               # SHA-256 去重归档与缩略图生成
│   │   ├── db.rs                  # SQLite + FTS5 持久化层
│   │   ├── sync.rs                # .slpack 离线包 & 原生 HTTPS WebDAV 增量同步
│   │   └── lib.rs                 # C-ABI FFI 导出入口
│   └── tests/core_tests.rs        # Rust 核心集成测试
├── app/                           # Flutter 跨端 UI (Windows / Android / Linux)
│   ├── lib/                       # Dart 状态、FFI Isolate 桥接与响应式 UI 页面
│   ├── android/                   # Android NDK 绑定与系统 Share Sheet 原生接收
│   ├── windows/                   # Windows CMake (自动构建并打包 styleloom_core.dll)
│   └── linux/                     # Linux 桌面构建配置
└── scripts/
    ├── build-android.sh           # 编译 Android arm64/x86_64 Rust 库并输出 Release APK
    ├── build-windows.ps1          # Windows 本机一键编译打包脚本
    └── check-windows-env.ps1      # Windows 工具链检查脚本
```

---

## 编译与运行指南

使用 Flutter 3.50.0 / Dart 3.14、Rust stable、JDK 21 和 Android NDK 28.2.13676358。依赖版本由 `app/pubspec.lock` 与 `rust/Cargo.lock` 固定。

### 1. Android 打包（Linux 开发机）
```bash
bash scripts/build-android.sh
```
构建产物位于 `dist/StyleLoom-android-release.apk`（内含 `arm64-v8a` 与 `x86_64` 双架构 `libstyleloom_core.so`）。

工具通过 `PATH` 查找；Android SDK 使用 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT`，也可设置 `FLUTTER_HOME`、`JAVA_HOME` 和 `ANDROID_NDK_HOME`。Linux 开发时将 Android 构建和模拟器放在独立、受内存限制的 systemd 服务中，并顺序运行。

正式签名可通过环境变量 `STYLELOOM_KEYSTORE_PATH`、`STYLELOOM_KEYSTORE_PASSWORD`、`STYLELOOM_KEY_ALIAS`、`STYLELOOM_KEY_PASSWORD` 提供。未设置签名文件时使用调试签名；本项目发布的 APK 使用独立发布签名。密钥保存在项目外。

### 2. Windows 编译与运行（在你的 Windows 设备上）
**前置环境**：
1. 安装 **Rust (MSVC 工具链)**：https://rustup.rs
2. 安装 **Visual Studio**（勾选「使用 C++ 的桌面开发」）
3. 安装 **Flutter Windows SDK** 并加入 `PATH`

**一键打包为便携绿色目录**：
```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
```
编译完成后运行 `dist\StyleLoom-windows-x64\styleloom_app.exe` 即可（也可直接在 `app` 目录运行 `flutter run -d windows` 进行热重载调试；CMake 会自动编译并复制 `styleloom_core.dll`）。

脚本同时生成 `dist\StyleLoom-windows-x64.zip`。GitHub Actions 的 `Windows Release` 工作流可按已有 tag 构建并上传便携包。

### 3. 验证

```bash
cargo test --locked --manifest-path rust/Cargo.toml
cargo build --locked --release --manifest-path rust/Cargo.toml
cd app
flutter analyze
flutter test
```

Flutter FFI 测试在 Linux 上运行，使用上一条命令构建的 Rust 动态库。回归测试覆盖异步编辑、手机端创建与返回、输入焦点和 IME、嵌套提示词权重、循环工作流节点、备份完整性及模拟 WebDAV 服务的异常与冲突。

### 4. 下载

源码与安装包见 [GitHub 私有仓库](https://github.com/ZZZdragondYNGPHX/StyleLoom) 和 [Releases](https://github.com/ZZZdragondYNGPHX/StyleLoom/releases)。Android 包包含 arm64 / x86_64；Windows 包解压后运行 `styleloom_app.exe`。每个包附带 SHA-256 校验文件。
