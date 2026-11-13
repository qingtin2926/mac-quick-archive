# 轻压 QuickArchive (`mac-quick-archive`)

> **Native macOS Finder Toolbar Archive Utility** — 固定在 macOS 访达（Finder）窗口右上角工具栏的原生轻量解压缩软件。

![Platform](https://img.shields.io/badge/macOS-13.0%2B-0A84FF?style=flat-square&logo=apple)
![Language](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift)
![Architecture](https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-34C759?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

**轻压 QuickArchive** 基于 macOS 原生 `FIFinderSync` 工具栏扩展打造，平时零常驻内存占用、不占 Dock 栏、不抢访达焦点。在访达中选中文件或文件夹，点击右上角图标即可选择压缩格式一键打包至当前目录；选中压缩包时自动切换为解压选项，支持解压到同名文件夹或直接释放到当前目录。

---

## 核心特性

### 1. 访达右上角极简一级交互
- **固定工具栏**：`16×16 pt` 青蓝拉链徽章图标配合弹性工具栏布局，稳定嵌入访达窗口右上角搜索框左侧，无闪烁、无冗余二级子菜单，点击直接弹出一级下拉列表。
- **智能场景识别**：
  - **选中文件 / 文件夹时**：直接展示压缩格式选项（`ZIP` / `7Z` / `TAR.GZ` / `TAR.XZ` / `TAR.ZST`），一键打包输出到当前目录。
  - **选中压缩包时**：自动切换为解压选项——**「解压到同名文件夹 “XXX/”」** 或 **「直接解压到当前目录」**。

### 2. 主流压缩与全格式解压支持
| 操作 | 支持格式 |
| :--- | :--- |
| **创建压缩包** | `ZIP (.zip)`、`7Z (.7z)`、`TAR.GZ (.tar.gz)`、`TAR.XZ (.tar.xz)`、`TAR.ZST (.tar.zst)` |
| **解压压缩包** | `ZIP`、`RAR`（含 RAR5 与分卷包 `.part1.rar`）、`7Z`、`TAR.GZ / TGZ`、`TAR.XZ / TXZ`、`TAR.BZ2 / TBZ2`、`TAR.ZST / TZST`、`TAR`、`GZ`、`BZ2`、`XZ`、`ZST`、`CAB`、`ISO`、`ARJ`、`LZH`、`XAR`、`CPIO`、`CBZ`、`CBR` |

### 3. 数据安全与体验细节
- **防覆盖保护**：无论压缩还是解压，遇到当前目录已有同名文件或文件夹时自动递增序号（例如 `报告 2.zip`），绝不静默覆盖原有数据。
- **智能防套娃**：选择「解压到同名文件夹」时，若压缩包内部原本只有单层根文件夹，自动直接提升该文件夹并命名，避免生成 `A/A/` 双层重复目录。
- **防中文乱码 & 加密包支持**：底层结合 `unar` 与 `7zz` 双引擎，自动识别 Windows GBK / Shift-JIS 文件名编码避免乱码；遇到加密压缩包自动弹出原生安全密码输入框。
- **跨平台干净打包**：默认自动剔除 `.DS_Store`、`__MACOSX` 与 `._*` 等 macOS 隐藏元数据文件（可在设置窗口随时开关）。
- **零打扰悬浮反馈**：执行任务时屏幕右上角显示毛玻璃 HUD 进度胶囊，完成后自动在访达高亮选中生成结果；空闲 8 秒后宿主进程自动退出释放内存。

---

## 快速安装与一键构建

无需安装庞大的完整版 Xcode，仅需系统自带 Command Line Tools 与 Homebrew 即可一键编译并完成安装：

```bash
# 1. 安装命令行压缩/解压引擎依赖（首次使用）
brew install unar sevenzip xz zstd

# 2. 克隆仓库并一键编译、签名、安装至 /Applications 及固定到访达右上角
git clone https://github.com/qingtin2926/mac-quick-archive.git
cd mac-quick-archive
chmod +x build_and_install.sh
./build_and_install.sh
```

安装脚本会自动完成以下步骤：
1. 动态生成应用 `.icns` 图标与访达工具栏矢量模板图标；
2. 使用 `swiftc` 编译访达扩展（`QuickArchiveFinderSync.appex`）与主程序（`QuickArchive.app`）；
3. 完成本地签名并安装至 `/Applications/QuickArchive.app`；
4. 注册 `quickarchive://` URL 协议、通过 `pluginkit` 启用访达扩展并将按钮固定到访达工具栏右上角。

---

## 使用方法

1. **压缩文件/文件夹**：在访达中选中一个或多个目标文件/文件夹，点击窗口右上角的「轻压」图标，选择目标格式（如 `压缩为 ZIP (.zip)`）即可在当前目录生成压缩包。
2. **解压文件**：在访达中选中一个或多个压缩包，点击右上角「轻压」图标，选择 **「解压到同名文件夹」** 或 **「直接解压到当前目录」**。
3. **打开偏好设置**：点击下拉菜单底部的 **「轻压设置…」**，或直接双击打开 `/Applications/QuickArchive.app`，可管理扩展状态、工具栏固定以及过滤 `.DS_Store` / 智能防套娃 / 自动高亮开关。

---

## 项目架构

```text
mac-quick-archive/
├── Shared/
│   └── ArchiveTypes.swift            # 压缩/解压格式枚举、双后缀识别 (.tar.gz 等)、URL Scheme 编解码
├── FinderExtension/
│   ├── FinderSync.swift              # FIFinderSync 访达工具栏按钮与纯一级动态下拉菜单
│   ├── FinderExtension.entitlements  # 扩展沙盒与用户选中文件读写权限配置
│   └── Info.plist                    # FinderSync 扩展元数据
├── HostApp/
│   ├── AppDelegate.swift             # URL 任务分发、加密密码弹窗与 8 秒空闲自动释放生命周期
│   ├── ArchiveEngine.swift           # 压缩/解压双引擎调度、防覆盖重命名、防套娃与访达高亮桥接
│   ├── HUDPanelController.swift      # 右上角毛玻璃悬浮进度/成功提示胶囊
│   ├── MainWindowController.swift    # 图形化偏好设置与工具栏集成状态面板
│   ├── IconGenerator.swift           # 编译期自动绘制应用 .icns 与 16pt 工具栏图标
│   └── Info.plist                    # 主程序配置与文件夹访问权限说明
├── build_and_install.sh              # 一键编译、签名、安装与访达工具栏固定脚本
├── LICENSE                           # MIT 开源许可证
└── README.md                         # 项目文档
```

---

## 常见问题

- **首次在「文稿 / 桌面 / 下载」目录操作时弹出权限提示？**
  macOS TCC 安全机制会在应用首次访问受保护目录时弹出确认框，点击 **「好 / 允许」** 即可，后续不会再重复提示。
- **如何手动调整工具栏按钮位置？**
  在任意访达窗口顶部工具栏空白处 **右键 → 自定义工具栏…**（或按住 `⌘ Command` 键直接拖动「轻压」图标）即可自由调整位置。
- **如何彻底卸载？**
  ```bash
  pluginkit -r /Applications/QuickArchive.app/Contents/PlugIns/QuickArchiveFinderSync.appex
  rm -rf /Applications/QuickArchive.app
  killall Finder
  ```
