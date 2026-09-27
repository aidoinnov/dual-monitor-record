#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
app_dir="$project_dir/dist/DualMonitorRecorder.app"
cli_dir="$project_dir/dist/bin"

cd "$project_dir"
swift build -c release

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
mkdir -p "$cli_dir"
cp "$project_dir/.build/release/DualMonitorRecorder" "$app_dir/Contents/MacOS/DualMonitorRecorder"
cp "$project_dir/.build/release/dualrec" "$cli_dir/dualrec"
cp "$project_dir/App/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
chmod +x "$cli_dir/dualrec"
cp "$project_dir/App/Info.plist" "$app_dir/Contents/Info.plist"
signing_identity="${DUAL_RECORDER_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)"/\1/p' | head -1)"
fi
if [[ -n "$signing_identity" ]] && security find-identity -v -p codesigning | grep -Fq "$signing_identity"; then
    codesign --force --deep --options runtime --timestamp=none --sign "$signing_identity" "$app_dir"
else
    echo "경고: 코드서명 인증서를 찾지 못해 임시 서명을 사용합니다. DUAL_RECORDER_SIGNING_IDENTITY를 지정하면 정식 서명을 사용할 수 있습니다." >&2
    codesign --force --deep --sign - "$app_dir"
fi

echo "$app_dir"
