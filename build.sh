#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

for tool in xcodegen xcodebuild; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing $tool. Install Xcode and run: brew install xcodegen" >&2
        exit 1
    fi
done

xcodegen generate
xcodebuild test \
    -project SwiftSSH.xcodeproj \
    -scheme SwiftSSH \
    -destination "${DESTINATION:-platform=iOS Simulator,name=iPhone 16}" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=""
