#!/bin/bash
# Builds EthernetWiFiSwitcher.app from main.swift and zips it for distribution.
set -e
cd "$(dirname "$0")"

APP="EthernetWiFiSwitcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# swift-version 5: avoids Swift 6 strict-concurrency noise; this app is single-threaded UI.
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/EthernetWiFiSwitcher" main.swift \
    -framework Cocoa -framework Network

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>EthernetWiFiSwitcher</string>
    <key>CFBundleDisplayName</key><string>Ethernet Wi-Fi Switcher</string>
    <key>CFBundleIdentifier</key><string>com.user.ethernetwifiswitcher</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>EthernetWiFiSwitcher</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Ad-hoc sign so Gatekeeper treats it as a stable, unmodified app.
codesign --force --deep -s - "$APP"

rm -f EthernetWiFiSwitcher.zip
ditto -c -k --keepParent "$APP" EthernetWiFiSwitcher.zip
echo "Built $APP and EthernetWiFiSwitcher.zip"
