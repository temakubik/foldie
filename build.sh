#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Foldie"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
BUILD_DIR="${ROOT_DIR}/.build-foldie"
MODULE_CACHE="/tmp/foldie-module-cache-26"
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk" ]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
elif [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk" ]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk"
else
    SDK_PATH="$(xcrun --show-sdk-path)"
fi
ARCH="$(uname -m)"

echo "==> Building ${APP_NAME} (${ARCH})..."
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE}"

# Collect all Swift source files
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "${ROOT_DIR}/Sources/Foldie" -name '*.swift' | sort)

# Compile release binary
swiftc \
    -parse-as-library \
    -swift-version 6 \
    -target "${ARCH}-apple-macosx14.0" \
    -sdk "${SDK_PATH}" \
    -module-cache-path "${MODULE_CACHE}" \
    -Xcc "-fmodules-cache-path=${MODULE_CACHE}" \
    -O \
    -framework AppKit \
    -framework SwiftUI \
    -framework ApplicationServices \
    -framework ScreenCaptureKit \
    -framework ServiceManagement \
    -framework CoreGraphics \
    -o "${BUILD_DIR}/${APP_NAME}" \
    "${SOURCES[@]}"

if [ -f "${ROOT_DIR}/Resources/AppIcon.icns" ]; then
    echo "==> Using cached Resources/AppIcon.icns..."
    cp "${ROOT_DIR}/Resources/AppIcon.icns" "${BUILD_DIR}/AppIcon.icns"
else
    echo "==> Generating app icon..."
    ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
    rm -rf "${ICONSET_DIR}"
    swiftc \
        -target "${ARCH}-apple-macosx14.0" \
        -sdk "${SDK_PATH}" \
        -module-cache-path "${MODULE_CACHE}" \
        -Xcc "-fmodules-cache-path=${MODULE_CACHE}" \
        -framework AppKit \
        -o "${BUILD_DIR}/generate_icon" \
        "${ROOT_DIR}/Scripts/generate_icon.swift"
    "${BUILD_DIR}/generate_icon" "${ICONSET_DIR}"
    iconutil -c icns "${ICONSET_DIR}" -o "${BUILD_DIR}/AppIcon.icns"
fi

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "${BUILD_DIR}/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Foldie/{print $2; exit}')"
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Signing ${APP_BUNDLE} with certificate: ${SIGN_IDENTITY}..."
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
else
    echo "==> Ad-hoc code signing ${APP_BUNDLE}..."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "==> Done! App bundle ready at: ${APP_BUNDLE}"
echo "    Run with: open \"${APP_BUNDLE}\""
