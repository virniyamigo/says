#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Збірка застосунку потребує macOS 14+ та Xcode 16+.' >&2
    exit 1
fi
swift build -c release --product MyProgress
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/.build/MyProgress.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/MyProgress" "$app_dir/Contents/MacOS/MyProgress"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MyProgress</string>
<key>CFBundleDisplayName</key><string>MyProgress</string>
<key>CFBundleIdentifier</key><string>com.virniyamigo.MyProgress</string>
<key>CFBundleExecutable</key><string>MyProgress</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
echo "Зібрано: $app_dir"
