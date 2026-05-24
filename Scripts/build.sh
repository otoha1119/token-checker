#!/bin/bash
# =============================================================================
# Scripts/build.sh
#
# token-checker を release ビルドして TokenChecker.app を組み立てる．
#
# 使い方:
#   ./Scripts/build.sh                  # ./TokenChecker.app を作成
#   ./Scripts/build.sh --install        # 上記＋ /Applications にコピー
#   ./Scripts/build.sh --user-install   # 上記＋ ~/Applications にコピー
#   ./Scripts/build.sh --clean          # 先にビルドキャッシュを掃除
#   ./Scripts/build.sh --no-sign        # 署名スキップ（推奨しない）
# =============================================================================
set -euo pipefail

PRODUCT="TokenChecker"
BUILD_DIR=".build/release"
APP_BUNDLE="${PRODUCT}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ENTITLEMENTS="Resources/${PRODUCT}.entitlements"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build ${PRODUCT}.app from this SwiftPM project.

Options:
  --clean          Clean .build/ before building
  --install        Copy ${PRODUCT}.app to /Applications after building
  --user-install   Copy ${PRODUCT}.app to ~/Applications after building
  --no-sign        Skip codesign (not recommended)
  -h, --help       Show this help
EOF
}

DO_CLEAN=false
DO_INSTALL=false
DO_USER_INSTALL=false
NO_SIGN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)        DO_CLEAN=true;        shift ;;
        --install)      DO_INSTALL=true;      shift ;;
        --user-install) DO_USER_INSTALL=true; shift ;;
        --no-sign)      NO_SIGN=true;         shift ;;
        -h|--help)      usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

cd "${PROJECT_DIR}"

if ${DO_CLEAN}; then
    info "Cleaning build artifacts..."
    swift package clean
    rm -rf "${APP_BUNDLE}"
fi

info "Building ${PRODUCT} (release)..."
swift build -c release

info "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}" "${RESOURCES}"
cp "${BUILD_DIR}/${PRODUCT}" "${MACOS}/"
cp Resources/Info.plist "${CONTENTS}/"
# Info.plist の CFBundleIconFile=AppIcon は無条件のため、.icns 不在を静かに通さない．
if [[ ! -f Resources/AppIcon.icns ]]; then
    error "Resources/AppIcon.icns が見つかりません。Info.plist の CFBundleIconFile=AppIcon と整合させるため必須です。"
    exit 1
fi
cp Resources/AppIcon.icns "${RESOURCES}/"

# MIT 帰属表示の同梱: 本ソフトウェアおよび ccmeter (MIT) 由来部分のライセンス本文と
# 著作権表示を配布バイナリ内に同梱する必要がある．
if [[ -f LICENSE ]]; then
    cp LICENSE "${RESOURCES}/"
else
    error "LICENSE が見つかりません。MIT 帰属表示のため必須です。"
    exit 1
fi

if ! ${NO_SIGN}; then
    info "Code signing ${APP_BUNDLE}..."
    # 注: || true を末尾に入れる必要がある．grep が一致無しで exit 1 を返すと
    # set -euo pipefail の pipefail と errexit が組み合わさってここで script が落ちる．
    #
    # identity の優先順位:
    #   1. Apple Development … ローカル実行用、Gatekeeper も通る、Notarization 不要
    #   2. Developer ID Application … 配布用だが Notarization 必須。未公証だと Gatekeeper
    #      にブロックされるため警告を出してから使う
    #   3. なし … ad-hoc 署名にフォールバック
    APPLE_DEV_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development' | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
    DEVID_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep '"Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/' || true)

    if [[ -n "${APPLE_DEV_IDENTITY}" ]]; then
        codesign --force --sign "${APPLE_DEV_IDENTITY}" \
            --entitlements "${ENTITLEMENTS}" \
            --options runtime \
            "${APP_BUNDLE}"
        info "Signed with: ${APPLE_DEV_IDENTITY}"
    elif [[ -n "${DEVID_IDENTITY}" ]]; then
        warn "Apple Development identity not found; falling back to Developer ID."
        warn "Notarization なしでは Gatekeeper にブロックされる場合があります."
        codesign --force --sign "${DEVID_IDENTITY}" \
            --entitlements "${ENTITLEMENTS}" \
            --options runtime \
            "${APP_BUNDLE}"
        info "Signed with: ${DEVID_IDENTITY}"
    else
        warn "No signing identity found; using ad-hoc signature."
        # ad-hoc 署名にはカーネルが entitlements も hardened runtime も信頼しないので
        # 渡さない（渡しても無意味で誤解を招く）．
        codesign --force --sign - "${APP_BUNDLE}"
        info "Signed with ad-hoc identity"
    fi
fi

if ${DO_INSTALL}; then
    info "Installing to /Applications..."
    rm -rf "/Applications/${APP_BUNDLE}"
    cp -R "${APP_BUNDLE}" "/Applications/"
    info "Installed to /Applications/${APP_BUNDLE}"
fi

if ${DO_USER_INSTALL}; then
    info "Installing to ~/Applications..."
    mkdir -p "${HOME}/Applications"
    rm -rf "${HOME}/Applications/${APP_BUNDLE}"
    cp -R "${APP_BUNDLE}" "${HOME}/Applications/"
    info "Installed to ${HOME}/Applications/${APP_BUNDLE}"
fi

info "Built ${APP_BUNDLE}"
