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
#
# 参考: s-age/ccmeter (MIT) — 基本構造を借用．
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

if ! ${NO_SIGN}; then
    info "Code signing ${APP_BUNDLE}..."
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E '"Apple Development|Developer ID' | head -1 | sed -E 's/.*"(.*)"/\1/')
    if [[ -n "${IDENTITY}" ]]; then
        codesign --force --sign "${IDENTITY}" \
            --entitlements "${ENTITLEMENTS}" \
            --options runtime \
            "${APP_BUNDLE}"
        info "Signed with: ${IDENTITY}"
    else
        warn "No signing identity found; using ad-hoc signature"
        codesign --force --sign - \
            --entitlements "${ENTITLEMENTS}" \
            "${APP_BUNDLE}"
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
