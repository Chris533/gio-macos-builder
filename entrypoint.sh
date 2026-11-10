#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-macos [options]

Zero-config macOS Universal Binary (.app / .zip / .dmg) builder for Go / Gio / CGO projects.
When options are omitted, defaults are auto-detected from store.config.json or project layout.

Options:
  --name <AppName>           Application & .app bundle name (e.g. PhotoEasy)
  --display-name <Title>     CFBundleDisplayName (defaults to --name)
  --id <BundleID>            macOS CFBundleIdentifier (e.g. cc.atomo.photoeasy)
  --entry <GoPkg>            Go main package path (e.g. ./cmd/studio or .)
  --icon <PngPath>           Source PNG icon (>=256x256 recommended; auto-detected if omitted)
  --version <SemVer>         CFBundleShortVersionString (e.g. 2.0.9)
  --build-number <Int>       CFBundleVersion integer/build string (auto-derived if omitted)
  --out <RelOrAbsDir>        Output directory (default: dist/macos)
  --arch <universal|arm64|amd64>  Target architecture (default: universal)
  --min-macos <Ver>          Minimum macOS deployment target (default: 11.0)
  --ldflags <Flags>          Extra Go -ldflags appended to "-s -w"
  --cgo-ldflags <Flags>      Extra CGO_LDFLAGS appended to "-framework UniformTypeIdentifiers"
  --locales <CSV>            Comma-separated CFBundleLocalizations (default: zh_CN,en)
  -h, --help                 Show this help message
EOF
}

APP_NAME="${APP_NAME:-}"
DISPLAY_NAME="${DISPLAY_NAME:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
ENTRY_PKG="${ENTRY_PKG:-}"
ICON_PATH="${ICON_PATH:-}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
OUT_DIR="${OUT_DIR:-dist/macos}"
TARGET_ARCH="${TARGET_ARCH:-universal}"
MIN_MACOS="${MIN_MACOS:-11.0}"
EXTRA_LDFLAGS="${EXTRA_LDFLAGS:-}"
EXTRA_CGO_LDFLAGS="${EXTRA_CGO_LDFLAGS:-}"
LOCALES_CSV="${LOCALES_CSV:-zh_CN,en,fr,de,es,pt_BR,ru,vi}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)         APP_NAME="$2"; shift 2 ;;
    --display-name) DISPLAY_NAME="$2"; shift 2 ;;
    --id)           BUNDLE_ID="$2"; shift 2 ;;
    --entry)        ENTRY_PKG="$2"; shift 2 ;;
    --icon)         ICON_PATH="$2"; shift 2 ;;
    --version)      APP_VERSION="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    --out)          OUT_DIR="$2"; shift 2 ;;
    --arch)         TARGET_ARCH="$2"; shift 2 ;;
    --min-macos)    MIN_MACOS="$2"; shift 2 ;;
    --ldflags)      EXTRA_LDFLAGS="$2"; shift 2 ;;
    --cgo-ldflags)  EXTRA_CGO_LDFLAGS="$2"; shift 2 ;;
    --locales)      LOCALES_CSV="$2"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# 1. Auto-detect metadata from store.config.json if present
if [[ -f "store.config.json" ]]; then
  eval "$(python3 - <<'PY'
import json, shlex
try:
    cfg = json.load(open("store.config.json", "r", encoding="utf-8"))
    pname = cfg.get("productName", "")
    mver = cfg.get("package", {}).get("msixVersion", "")
    if mver.endswith(".0") and mver.count(".") == 3:
        mver = mver[:-2]
    mac = cfg.get("macos", {})
    print(f'_CFG_NAME={shlex.quote(str(mac.get("appName") or pname))}')
    print(f'_CFG_ID={shlex.quote(str(mac.get("bundleId") or ""))}')
    print(f'_CFG_ENTRY={shlex.quote(str(mac.get("entry") or ""))}')
    print(f'_CFG_ICON={shlex.quote(str(mac.get("icon") or ""))}')
    print(f'_CFG_VER={shlex.quote(str(mac.get("version") or mver))}')
except Exception:
    pass
PY
)"
  [[ -z "${APP_NAME}" && -n "${_CFG_NAME:-}" ]] && APP_NAME="${_CFG_NAME}"
  [[ -z "${BUNDLE_ID}" && -n "${_CFG_ID:-}" ]] && BUNDLE_ID="${_CFG_ID}"
  [[ -z "${ENTRY_PKG}" && -n "${_CFG_ENTRY:-}" ]] && ENTRY_PKG="${_CFG_ENTRY}"
  [[ -z "${ICON_PATH}" && -n "${_CFG_ICON:-}" ]] && ICON_PATH="${_CFG_ICON}"
  [[ -z "${APP_VERSION}" && -n "${_CFG_VER:-}" ]] && APP_VERSION="${_CFG_VER}"
fi

# 2. Fallback defaults from workspace structure
if [[ -z "${APP_NAME}" ]]; then
  if [[ -f "go.mod" ]]; then
    MOD_LAST="$(awk '/^module /{sub(/.*\//,"",$2); print $2; exit}' go.mod)"
    APP_NAME="${MOD_LAST:-App}"
  else
    APP_NAME="$(basename "$(pwd)")"
  fi
fi
[[ -z "${DISPLAY_NAME}" ]] && DISPLAY_NAME="${APP_NAME}"

SLUG="$(echo "${APP_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
[[ -z "${SLUG}" ]] && SLUG="app"
[[ -z "${BUNDLE_ID}" ]] && BUNDLE_ID="cc.atomo.${SLUG}"

if [[ -z "${ENTRY_PKG}" ]]; then
  if [[ -f "main.go" ]]; then
    ENTRY_PKG="."
  elif [[ -d "cmd/studio" ]]; then
    ENTRY_PKG="./cmd/studio"
  elif [[ -d "cmd/${SLUG}" ]]; then
    ENTRY_PKG="./cmd/${SLUG}"
  elif [[ -d "cmd/app" ]]; then
    ENTRY_PKG="./cmd/app"
  else
    FIRST_CMD="$(find cmd -mindepth 1 -maxdepth 2 -name 'main.go' 2>/dev/null | head -n 1 || true)"
    if [[ -n "${FIRST_CMD}" ]]; then
      ENTRY_PKG="./$(dirname "${FIRST_CMD}")"
    else
      echo "Error: Could not auto-detect Go main package. Pass --entry ./cmd/<name>." >&2
      exit 1
    fi
  fi
fi

if [[ -z "${ICON_PATH}" ]]; then
  for candidate in \
    "store-assets/assets/logo/logo.png" \
    "store-assets/assets/logo/logo-1080.png" \
    "assets/icon.png" \
    "assets/logo.png" \
    "build/appicon.png" \
    "icon.png" \
    "logo.png"; do
    if [[ -f "${candidate}" ]]; then
      ICON_PATH="${candidate}"
      break
    fi
  done
fi

[[ -z "${APP_VERSION}" ]] && APP_VERSION="1.0.0"
if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="$(echo "${APP_VERSION}" | tr -cd '0-9')"
  [[ -z "${BUILD_NUMBER}" ]] && BUILD_NUMBER="100"
fi

export MACOSX_DEPLOYMENT_TARGET="${MIN_MACOS}"
mkdir -p "${GOCACHE}" "${GOMODCACHE}"

APP_BUNDLE="${OUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${OUT_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

GO_LDFLAGS="-s -w"
[[ -n "${EXTRA_LDFLAGS}" ]] && GO_LDFLAGS="${GO_LDFLAGS} ${EXTRA_LDFLAGS}"
CGO_LD="-framework UniformTypeIdentifiers"
[[ -n "${EXTRA_CGO_LDFLAGS}" ]] && CGO_LD="${CGO_LD} ${EXTRA_CGO_LDFLAGS}"

echo "=== macOS Cross-Build Configuration ==="
echo "  App Name    : ${APP_NAME} (${DISPLAY_NAME})"
echo "  Bundle ID   : ${BUNDLE_ID}"
echo "  Entry Pkg   : ${ENTRY_PKG}"
echo "  Version     : ${APP_VERSION} (${BUILD_NUMBER})"
echo "  Arch        : ${TARGET_ARCH} (min macOS ${MIN_MACOS})"
echo "  Icon Source : ${ICON_PATH:-<auto-generated fallback>}"
echo "  Output Dir  : ${OUT_DIR}"
echo "======================================="

if [[ "${TARGET_ARCH}" == "universal" || "${TARGET_ARCH}" == "arm64" ]]; then
  echo "[1/4] Compiling darwin/arm64 (Apple Silicon)..."
  CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 CC=/usr/local/bin/oa64-cc CGO_LDFLAGS="${CGO_LD}" \
    go build -buildvcs=false -trimpath -ldflags="${GO_LDFLAGS}" \
    -o "${OUT_DIR}/${APP_NAME}-darwin-arm64" "${ENTRY_PKG}"
fi

if [[ "${TARGET_ARCH}" == "universal" || "${TARGET_ARCH}" == "amd64" ]]; then
  echo "[2/4] Compiling darwin/amd64 (Intel Mac)..."
  CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 CC=/usr/local/bin/o64-cc CGO_LDFLAGS="${CGO_LD}" \
    go build -buildvcs=false -trimpath -ldflags="${GO_LDFLAGS}" \
    -o "${OUT_DIR}/${APP_NAME}-darwin-amd64" "${ENTRY_PKG}"
fi

echo "[3/4] Assembling ${APP_NAME}.app bundle, AppIcon.icns & Info.plist..."
if [[ "${TARGET_ARCH}" == "universal" ]]; then
  /osxcross/bin/lipo -create \
    "${OUT_DIR}/${APP_NAME}-darwin-arm64" \
    "${OUT_DIR}/${APP_NAME}-darwin-amd64" \
    -output "${MACOS_DIR}/${APP_NAME}"
elif [[ "${TARGET_ARCH}" == "arm64" ]]; then
  cp "${OUT_DIR}/${APP_NAME}-darwin-arm64" "${MACOS_DIR}/${APP_NAME}"
elif [[ "${TARGET_ARCH}" == "amd64" ]]; then
  cp "${OUT_DIR}/${APP_NAME}-darwin-amd64" "${MACOS_DIR}/${APP_NAME}"
else
  echo "Unsupported --arch: ${TARGET_ARCH}" >&2
  exit 1
fi
chmod 0755 "${MACOS_DIR}/${APP_NAME}"

ICON_TMP="$(mktemp -d)"
python3 - "${ICON_PATH}" "${ICON_TMP}" <<'PY'
import os, sys
from PIL import Image, ImageDraw

src_path, out_dir = sys.argv[1], sys.argv[2]
if src_path and os.path.isfile(src_path):
    img = Image.open(src_path).convert("RGBA")
else:
    img = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((64, 64, 960, 960), radius=200, fill=(37, 99, 235, 255))
    draw.rounded_rectangle((220, 220, 804, 804), radius=120, outline=(255, 255, 255, 230), width=48)

for size in (16, 32, 128, 256, 512, 1024):
    resized = img.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(os.path.join(out_dir, f"icon_{size}.png"), format="PNG")
PY

png2icns "${RESOURCES_DIR}/AppIcon.icns" \
  "${ICON_TMP}/icon_16.png" \
  "${ICON_TMP}/icon_32.png" \
  "${ICON_TMP}/icon_128.png" \
  "${ICON_TMP}/icon_256.png" \
  "${ICON_TMP}/icon_512.png" \
  "${ICON_TMP}/icon_1024.png" >/dev/null
rm -rf "${ICON_TMP}"

printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

LOCALES_XML=""
IFS=',' read -ra LOC_ARR <<< "${LOCALES_CSV}"
for loc in "${LOC_ARR[@]}"; do
  loc_trimmed="$(echo "${loc}" | xargs)"
  [[ -n "${loc_trimmed}" ]] && LOCALES_XML+="		<string>${loc_trimmed}</string>"$'\n'
done

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
${LOCALES_XML%$'\n'}
	</array>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${DISPLAY_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${APP_VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_MACOS}</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
EOF

ARCH_SUFFIX="$( [[ "${TARGET_ARCH}" == "universal" ]] && echo "Universal" || echo "${TARGET_ARCH}" )"
ZIP_NAME="${APP_NAME}-macOS-${ARCH_SUFFIX}.zip"
DMG_NAME="${APP_NAME}-macOS-${ARCH_SUFFIX}.dmg"

echo "[4/4] Packaging ${ZIP_NAME} (preserving 0755 permissions) & ${DMG_NAME}..."
(
  cd "${OUT_DIR}"
  python3 - "${APP_NAME}.app" "${ZIP_NAME}" <<'PY'
import os, sys, zipfile

app_dir, zip_name = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_name, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(app_dir):
        for file in files:
            full = os.path.join(root, file)
            info = zipfile.ZipInfo(full)
            st = os.stat(full)
            info.external_attr = (st.st_mode & 0xFFFF) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as f:
                zf.writestr(info, f.read())
PY
)

DMG_STAGE="$(mktemp -d)"
cp -a "${APP_BUNDLE}" "${DMG_STAGE}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGE}/Applications"
genisoimage -V "${APP_NAME}" -D -R -apple -no-pad -o "${OUT_DIR}/${DMG_NAME}" "${DMG_STAGE}" >/dev/null 2>&1
rm -rf "${DMG_STAGE}"

echo "=== macOS Build Complete ==="
file "${MACOS_DIR}/${APP_NAME}"
ls -lh "${OUT_DIR}/${ZIP_NAME}" "${OUT_DIR}/${DMG_NAME}" "${MACOS_DIR}/${APP_NAME}"
