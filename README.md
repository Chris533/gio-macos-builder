# gio-macos-builder

**零配置 Go / Gio / CGO 桌面应用 macOS Universal Binary (`arm64` + `x86_64`) 交叉编译与打包镜像。**

无需物理 Mac、无需在宿主机手动配置 `osxcross` / Clang / Xcode SDK，在 Windows (WSL2)、任意 Linux 机器或 GitHub Actions 中一行命令直接编译输出：
- `<AppName>.app`（`lipo` 合并双架构 Universal Binary + `Info.plist` + 自动缩放生成的 `AppIcon.icns`）
- `<AppName>-macOS-Universal.zip`（显式保留 Unix `0755` 可执行位，解压双击即用）
- `<AppName>-macOS-Universal.dmg`（带 `/Applications` 拖拽安装软链的 Apple Rock Ridge 镜像）

---

## 1. 快速开始（任意项目一行命令出包）

### 方式 A：Windows + WSL Docker（推荐）

在任意 Go/Gio 项目目录下直接调用包装脚本（自动转换 Windows 盘符路径为 WSL `/mnt/...`，并挂载跨项目共享的 `gio-macos-cache` 缓存卷）：

```powershell
# 1. 零参数自动推断（自动读取 store.config.json / go.mod / cmd/* / logo.png）
powershell -ExecutionPolicy Bypass -File "D:\workspace\gio-macos-builder\scripts\build-macos.ps1" -ProjectDir .

# 2. 显式指定任意项目的参数
powershell -ExecutionPolicy Bypass -File "D:\workspace\gio-macos-builder\scripts\build-macos.ps1" `
  -ProjectDir "D:\workspace\my-gio-app" `
  -Name "MyApp" `
  -BundleId "cc.atomo.myapp" `
  -Entry "./cmd/app" `
  -Icon "assets/logo.png" `
  -Version "1.2.0"
```

### 方式 B：直接运行公开 Docker 镜像（Linux / WSL2 / CI 免登录拉取）

```bash
docker run --rm \
  -v "$(pwd):/workspace" \
  -v gio-macos-cache:/cache \
  ghcr.io/chris533/gio-macos-builder:15.5 \
  --name "MyApp" \
  --id "cc.atomo.myapp" \
  --entry "./cmd/app" \
  --icon "assets/logo.png" \
  --version "1.2.0"
```

> **增量编译加速**：挂载 `-v gio-macos-cache:/cache` 会持久化 `GOCACHE` 和 `GOMODCACHE`。首次拉取依赖与编译 Objective-C/Metal 约 45~60 秒，后续跨项目或增量打包仅需 **15~30 秒**。

---

## 2. 支持的 CLI 参数与 `store.config.json` 自动探测

| 参数 | 说明 | 缺省时的自动推断规则 |
| :--- | :--- | :--- |
| `--name <AppName>` | 应用与 `.app` 名称 | 读取 `store.config.json` 的 `macos.appName` 或 `productName`，否则取 `go.mod` 模块末段 |
| `--display-name <Title>` | Finder 显示名 (`CFBundleDisplayName`) | 默认同 `--name` |
| `--id <BundleID>` | `CFBundleIdentifier` | 读取 `macos.bundleId`，否则默认 `cc.atomo.<slug>` |
| `--entry <GoPkg>` | Go `main` 包路径 | 读取 `macos.entry`，否则按 `./main.go` -> `./cmd/studio` -> 首个 `./cmd/*/main.go` 探测 |
| `--icon <PngPath>` | PNG 图标源（Pillow `LANCZOS` 缩放为 `16..1024` `.icns`） | 依次查找 `store-assets/assets/logo/logo.png`、`assets/icon.png`、`assets/logo.png`、`icon.png`；若无则自动生成圆角默认图标 |
| `--version <SemVer>` | `CFBundleShortVersionString` | 读取 `macos.version` 或 `package.msixVersion`（去掉末尾 `.0`），否则 `1.0.0` |
| `--build-number <Int>` | `CFBundleVersion` | 提取 `--version` 数字部分（如 `2.0.9` -> `209`） |
| `--arch <universal\|arm64\|amd64>` | 目标架构 | `universal` |
| `--min-macos <Ver>` | 最低系统版本 (`MACOSX_DEPLOYMENT_TARGET`) | `11.0` |
| `--ldflags <Flags>` | 追加到 `-s -w` 后的 Go `-ldflags` | 空 |
| `--cgo-ldflags <Flags>` | 追加到 `-framework UniformTypeIdentifiers` 后的链接参数 | 空 |
| `--out <Dir>` | 相对于项目根目录的输出路径 | `dist/macos` |

如果项目已有 `store.config.json`，还可添加可选的 `"macos"` 配置块实现永久无参打包：

```json
{
  "macos": {
    "appName": "PhotoEasy",
    "bundleId": "cc.atomo.photoeasy",
    "entry": "./cmd/studio",
    "icon": "store-assets/assets/logo/logo.png"
  }
}
```

---

## 3. 镜像已内置解决的 6 个 Go/Gio 交叉编译踩坑点

在 Linux 下用 `osxcross` + `MacOSX15.5.sdk` 编译带 Objective-C (`AppKit` / `Metal` / `UniformTypeIdentifiers`) 的 Go/Gio 项目时，默认环境会触发 6 个经典报错，本镜像已在构建期全部固化修复：

1. **`crazymax/osxcross` 镜像不含 Clang 驱动**  
   多阶段合并 `ubuntu:24.04` + `clang-18` + `golang:1.26` + `crazymax/osxcross:15.5-ubuntu`，预置 `/usr/local/bin/oa64-cc` 与 `/usr/local/bin/o64-cc`。
2. **`module '_stddef' requires feature 'found_incompatible_headers__check_search_paths'`**  
   - 在 Wrapper 中通过 `-I/usr/lib/llvm-18/lib/clang/18/include`（而非会被重排的 `-isystem`）强制 Clang 内置 `stddef.h`/`stdint.h` 优先于 `MacOSX15.5.sdk/usr/include`；
   - 在 `"$@"` **之后**追加 `-fno-modules`，覆盖 `gioui.org/x/explorer` 等库硬编码的 `-fmodules`，规避跨平台 `.pcm` 模块缓存不兼容。
3. **`MacOSX15.5.sdk/usr/include/libxml/module.modulemap: redefinition of module 'libxml2'`**  
   镜像构建时自动清理被展开为双份实体目录的 `/usr/include/libxml` 并还原为指向 `libxml2/libxml` 的符号链接。
4. **`arm64-apple-darwin24.5-ld: error while loading shared libraries: libxar.so.1`**  
   预设 `LD_LIBRARY_PATH="/osxcross/lib"`。
5. **`Undefined symbols: "_OBJC_CLASS_$_UTType"`**  
   自动注入 `CGO_LDFLAGS="-framework UniformTypeIdentifiers"`（兼容 macOS 11+ 文件选择器 API）。
6. **Windows 压缩丢失可执行位导致 Mac 报“应用程序已损坏” & 图标依赖污染**  
   - 用容器内置 Python `Pillow` 生成多尺寸图标，不要求目标项目 `go.mod` 引入 `golang.org/x/image`；
   - 用 `zipfile.ZipInfo` 显式写入 `(st.st_mode & 0xFFFF) << 16` 保留 `0755` 权限位，并用 `genisoimage -apple` 生成带 `/Applications` 软链的标准 `.dmg`。

---

## 4. 注册为本地 AI Agent 全局 Skill

在新开发机克隆本仓库后，执行以下命令即可挂载为全局 Skill（供所有工作区的 Agent 自动发现调用）：

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path "$HOME\.gemini\skills\macos-cross-build" -Target "D:\workspace\gio-macos-builder"
```

```bash
# Linux / macOS
ln -sfn "$(pwd)" ~/.gemini/skills/macos-cross-build
```
