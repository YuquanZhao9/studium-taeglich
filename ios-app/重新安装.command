#!/bin/bash
# 重新装「看课」App（免费签名每 7 天过期一次）：iPhone 用线连上这台 Mac 并解锁，然后双击这个文件。
# 第一次要先在 Xcode 里选好 Team（见 README.md）。重装不会丢下载的课和进度。
set -e
cd "$(dirname "$0")"
echo "正在打包看课 App…"
xcodebuild -project Kanke.xcodeproj -scheme Kanke -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates -quiet build
xcrun devicectl list devices --json-output "${TMPDIR:-/tmp}/kanke-devices.json" >/dev/null
DEV=$(/usr/bin/python3 - "${TMPDIR:-/tmp}/kanke-devices.json" <<'PY'
import json, sys
devs = json.load(open(sys.argv[1]))["result"]["devices"]
ios = [d for d in devs if d.get("hardwareProperties", {}).get("platform") == "iOS"]
ok = [d for d in ios if d.get("connectionProperties", {}).get("tunnelState") == "connected"] or ios
print(ok[0]["identifier"] if ok else "")
PY
)
if [ -z "$DEV" ]; then echo "没找到 iPhone：用线连上并解锁，再双击一次。"; read -r -p "按回车关闭"; exit 1; fi
echo "正在装到 iPhone…"
xcrun devicectl device install app --device "$DEV" build/Build/Products/Release-iphoneos/Kanke.app
echo "装好了。7 天后再双击一次这个文件。"
read -r -p "按回车关闭"
