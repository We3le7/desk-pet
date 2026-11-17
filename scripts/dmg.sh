#!/bin/bash
# 产出 dist/DeskPet.dmg：盘内含 app + Applications 软链，拖进去即可安装。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DeskPet"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
STAGE="$DIST/dmg-stage"
DMG="$DIST/$APP_NAME.dmg"
VOLUME_NAME="DeskPet"

if [ ! -d "$APP" ]; then
  echo "ERROR: 缺少 $APP，先跑 make app" >&2
  exit 1
fi

echo "==> 准备镜像目录"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 可选背景图与图标布局（M4 补齐）
if [ -f "$ROOT/scripts/dmg-layout.applescript" ]; then
  echo "    (发现 dmg-layout.applescript，将在可写镜像阶段执行)"
fi

echo "==> 生成 UDZO 镜像"
# hdiutil 在 macOS 27 已标记 deprecated，故先试新 API，失败回退
if diskutil image create from "$STAGE" --volumeName "$VOLUME_NAME" --format UDZO "$DMG" >/dev/null 2>&1; then
  echo "    (diskutil 新 API)"
else
  hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
  echo "    (hdiutil 回退)"
fi

rm -rf "$STAGE"

echo "==> 校验镜像"
hdiutil verify "$DMG" > /dev/null
echo "✅ $DMG"
ls -lh "$DMG" | awk '{print "   大小：" $5}'
