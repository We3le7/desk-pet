#!/bin/bash
# 组装 dist/DeskPet.app。本机只有 CLT，没有 xcodebuild，故手工拼 bundle。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DeskPet"
BUILD_DIR="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> 清理旧产物"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 拷贝可执行文件"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

echo "==> 写入 Info.plist"
cp "$ROOT/Sources/DeskPet/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" > /dev/null

echo "==> 拷贝图标（若已生成）"
if [ -f "$ROOT/Sources/DeskPet/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Sources/DeskPet/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "    (跳过：AppIcon.icns 尚未生成，M4 处理)"
fi

echo "==> 断言：包内不含宠物素材"
if find "$APP" -name "*.webp" | grep -q .; then
  echo "ERROR: .app 里出现了 webp 素材，宠物应运行时从磁盘读取" >&2
  exit 1
fi

echo "✅ $APP"
du -sh "$APP"
