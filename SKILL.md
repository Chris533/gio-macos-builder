---
name: macos-cross-build
description: Cross-compile and package Go, Gio, and CGO desktop apps on Windows/WSL2 or Linux into macOS Universal Binaries (.app, .zip preserving Unix 0755 permissions, and .dmg with /Applications link) using the self-contained ghcr.io/chris533/gio-macos-builder:15.5 Docker image. Activate whenever the user asks to build, compile, or package a macOS / Mac / Darwin .app, .dmg, or Universal binary from Windows or Linux.
---

# macOS Universal Cross-Build (`gio-macos-builder`)

Cross-compile any Go / Gio / CGO desktop application (including Objective-C, AppKit, Metal, QuartzCore, and `UniformTypeIdentifiers`) into a **macOS Universal Binary (`arm64` + `x86_64`)** `.app` bundle, `.zip` (preserving Unix `0755` permissions), and `.dmg` installer — without needing a Mac or configuring host toolchains.

Canonical repository: `D:\workspace\gio-macos-builder` (`https://github.com/Chris533/gio-macos-builder`)

## 1. Quick Start (One-Line Build from Any Project)

### Option A: PowerShell Helper Script (Recommended on Windows + WSL Docker)

Run from any Go/Gio project directory (automatically converts Windows drive paths like `D:\workspace\app` to `/mnt/d/workspace/app` when using WSL Docker, and mounts the shared `gio-macos-cache` volume):

```powershell
# Zero-config auto-detect (reads store.config.json / go.mod / cmd/* / logo.png automatically)
powershell -ExecutionPolicy Bypass -File "D:\workspace\gio-macos-builder\scripts\build-macos.ps1" -ProjectDir .

# Explicit parameters for any custom project
powershell -ExecutionPolicy Bypass -File "D:\workspace\gio-macos-builder\scripts\build-macos.ps1" `
  -ProjectDir "D:\workspace\my-gio-app" `
  -Name "MyApp" `
  -BundleId "cc.atomo.myapp" `
  -Entry "./cmd/app" `
  -Icon "assets/logo.png" `
  -Version "1.2.0"
```

### Option B: Direct `docker run` (WSL2 / Linux / GitHub Actions)

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

---

## 2. Output Artifacts (`dist/macos/`)

Every run produces:
- `<Name>-darwin-arm64`: Apple Silicon (`M1/M2/M3/M4`) Mach-O 64-bit binary
- `<Name>-darwin-amd64`: Intel Mac (`x86_64`) Mach-O 64-bit binary
- `<Name>.app`: Standard macOS application bundle (`Universal Binary` via `lipo`, `Info.plist`, `PkgInfo`, and multi-size `AppIcon.icns`)
- `<Name>-macOS-Universal.zip`: Distributable archive with Unix `0755` executable bits explicitly preserved
- `<Name>-macOS-Universal.dmg`: Drag-to-Applications disk image with Apple Rock Ridge extensions

---

## 3. Supported CLI Flags & `store.config.json` Auto-Detection

If flags are omitted, `entrypoint.sh` auto-detects values from `store.config.json` (optional `"macos"` block or top-level `productName` / `package.msixVersion`), `go.mod`, and `cmd/*`:

| Flag | Description | Auto-Detection / Default |
| :--- | :--- | :--- |
| `--name <AppName>` | `.app` bundle & executable name | `store.config.json` -> `productName` -> `go.mod` module basename |
| `--display-name <Title>` | `CFBundleDisplayName` shown in Finder | Defaults to `--name` |
| `--id <BundleID>` | `CFBundleIdentifier` | `macos.bundleId` or `cc.atomo.<slug>` |
| `--entry <GoPkg>` | Go `main` package path | `macos.entry` -> `./main.go` -> `./cmd/studio` -> first `cmd/*/main.go` |
| `--icon <PngPath>` | Source PNG icon (auto-scaled to `16..1024` `.icns`) | Searches `store-assets/assets/logo/logo.png`, `assets/icon.png`, `assets/logo.png`, `icon.png`, or generates a fallback icon |
| `--version <SemVer>` | `CFBundleShortVersionString` | `macos.version` -> `msixVersion` (trimmed) -> `1.0.0` |
| `--build-number <Int>` | `CFBundleVersion` | Digits of `--version` (e.g., `2.0.9` -> `209`) |
| `--arch <universal\|arm64\|amd64>` | Target CPU architecture | `universal` |
| `--min-macos <Ver>` | `LSMinimumSystemVersion` & deployment target | `11.0` |
| `--ldflags <Flags>` | Extra Go `-ldflags` appended to `-s -w` | Empty |
| `--cgo-ldflags <Flags>` | Extra `CGO_LDFLAGS` appended to `-framework UniformTypeIdentifiers` | Empty |
| `--out <Dir>` | Output directory relative to `/workspace` | `dist/macos` |
