#!/bin/zsh
set -uo pipefail

project_dir="${0:A:h:h}"
timestamp="$(date +%Y%m%d-%H%M%S)"
report_dir="$project_dir/test-reports/$timestamp"
report_md="$report_dir/QUALITY_REPORT.md"
report_json="$report_dir/results.json"
results_tsv="$report_dir/results.tsv"
mkdir -p "$report_dir"
: > "$results_tsv"

pass_count=0
fail_count=0
skip_count=0

record_result() {
    local category="$1" name="$2" result="$3" detail="$4"
    detail="${detail//$'\n'/ }"
    detail="${detail//$'\t'/ }"
    printf '%s\t%s\t%s\t%s\n' "$category" "$name" "$result" "$detail" >> "$results_tsv"
    case "$result" in
        PASS) ((pass_count++)) ;;
        FAIL) ((fail_count++)) ;;
        SKIP) ((skip_count++)) ;;
    esac
    print "[$result] $category — $name"
}

run_check() {
    local category="$1" name="$2"
    shift 2
    local slug="${category:l}-${name:l}"
    slug="${slug// /-}"
    local log="$report_dir/$slug.log"
    if "$@" > "$log" 2>&1; then
        local detail="$(tail -1 "$log")"
        if [[ "$category" == "Unit" ]]; then
            detail="$(rg 'Executed [0-9]+ tests' "$log" | tail -1)"
        fi
        record_result "$category" "$name" PASS "$detail"
    else
        record_result "$category" "$name" FAIL "$(tail -3 "$log")"
    fi
}

cd "$project_dir"

run_check Unit "Swift tests" swift test
run_check Build "Debug build" swift build
run_check Build "Release app bundle" ./build-app.sh
run_check Package "Info plist" plutil -lint dist/DualMonitorRecorder.app/Contents/Info.plist
if codesign --verify --deep --strict dist/DualMonitorRecorder.app > "$report_dir/code-signature.log" 2>&1 \
    && codesign -dvv dist/DualMonitorRecorder.app >> "$report_dir/code-signature.log" 2>&1 \
    && rg -q '^Authority=' "$report_dir/code-signature.log" \
    && rg -q '^TeamIdentifier=.+$' "$report_dir/code-signature.log" \
    && ! rg -q 'Signature=adhoc' "$report_dir/code-signature.log"; then
    record_result Security "Certificate signature" PASS "Trusted authority, TeamIdentifier present, non-ad-hoc"
else
    record_result Security "Certificate signature" FAIL "Signature is invalid, ad-hoc, or has the wrong TeamIdentifier"
fi

pkill -x DualMonitorRecorder >/dev/null 2>&1 || true
dist/DualMonitorRecorder.app/Contents/MacOS/DualMonitorRecorder --headless > "$report_dir/headless-app.log" 2>&1 &
app_pid=$!
cleanup() {
    kill "$app_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 3

if pgrep -x DualMonitorRecorder >/dev/null; then
    record_result Runtime "Application launch" PASS "DualMonitorRecorder process is running"
else
    record_result Runtime "Application launch" FAIL "Process was not found"
fi

if curl -fsS --max-time 3 http://127.0.0.1:17842/v1/status > "$report_dir/http-status.json" \
    && python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["headless"] is True; assert s["hotKeyRegistered"] is True; assert s["menuBarEnabled"] is True' "$report_dir/http-status.json"; then
    record_result Runtime "Headless, menu bar, hotkey" PASS "Headless mode active; menu bar declared; Command+F2 registered with Carbon"
else
    record_result Runtime "Headless, menu bar, hotkey" FAIL "Runtime capability state is missing or hotkey registration failed"
fi

run_check Integration "CLI status" dist/bin/dualrec status

if printf '%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    | node integrations/mcp-server.mjs > "$report_dir/mcp.jsonl" 2>&1 \
    && rg -q 'start_recording' "$report_dir/mcp.jsonl" \
    && rg -q 'get_status' "$report_dir/mcp.jsonl"; then
    record_result Integration "MCP initialize and tools" PASS "MCP tools/list contains start_recording"
else
    record_result Integration "MCP initialize and tools" FAIL "MCP handshake or tools/list failed"
fi

if open 'dualrecorder://noop' >/dev/null 2>&1; then
    record_result Integration "URL scheme" PASS "dualrecorder:// URL accepted by LaunchServices without opening UI"
else
    record_result Integration "URL scheme" FAIL "URL scheme could not be opened"
fi

if [[ "${DUALREC_SKIP_RECORDING:-0}" == "1" ]]; then
    record_result E2E "Real screen recording" SKIP "DUALREC_SKIP_RECORDING=1"
else
    # Start through the CLI, observe the transition through WebSocket and MCP, then stop through HTTP.
    dist/bin/dualrec start > "$report_dir/cli-start.json" 2>&1 || true
    sleep 3
    if node -e 'const ws=new WebSocket("ws://127.0.0.1:17843");let t=setTimeout(()=>process.exit(1),5000);ws.onmessage=e=>{let s=JSON.parse(e.data);if(s.recording){console.log(e.data);clearTimeout(t);ws.close();process.exit(0)}};ws.onerror=()=>process.exit(1)' > "$report_dir/websocket-recording.json" 2>&1; then
        record_result Integration "WebSocket live transition" PASS "Observed recording=true"
    else
        record_result Integration "WebSocket live transition" FAIL "Did not observe recording=true"
    fi
    printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_status","arguments":{}}}' \
        | node integrations/mcp-server.mjs > "$report_dir/mcp-call-status.json" 2>&1
    if rg -q '\\"recording\\":true' "$report_dir/mcp-call-status.json"; then
        record_result Integration "MCP tool call" PASS "get_status observed active recording"
    else
        record_result Integration "MCP tool call" FAIL "get_status tool did not return active recording"
    fi
    recording_status="$(curl -fsS --max-time 3 http://127.0.0.1:17842/v1/status 2>&1)"
    curl -fsS -X POST --max-time 3 http://127.0.0.1:17842/v1/recording/stop > "$report_dir/stop.json" 2>&1 || true
    sleep 4
    final_status="$(curl -fsS --max-time 3 http://127.0.0.1:17842/v1/status 2>&1)"
    print -r -- "$recording_status" > "$report_dir/recording-status.json"
    print -r -- "$final_status" > "$report_dir/final-status.json"
    saved_file="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("savedFile") or "")' <<< "$final_status" 2>/dev/null)"
    if [[ -n "$saved_file" && -s "$saved_file" ]]; then
        record_result E2E "CLI start and HTTP stop" PASS "$saved_file ($(stat -f%z "$saved_file") bytes)"
        if command -v ffprobe >/dev/null 2>&1 && ffprobe -v error -show_streams -show_format -of json "$saved_file" > "$report_dir/video-metadata.json" 2>&1; then
            if python3 - "$report_dir/final-status.json" "$report_dir/video-metadata.json" <<'PY'
import json, sys
status=json.load(open(sys.argv[1])); meta=json.load(open(sys.argv[2]))
layout=status["layout"]; streams=[s for s in meta["streams"] if s.get("codec_type")=="video"]
assert len(layout["displays"]) >= 2, "fewer than two displays"
assert len(streams)==1, "expected one composited video stream"
s=streams[0]
assert s["codec_name"]=="hevc"
assert s["width"]==layout["outputWidth"] and s["height"]==layout["outputHeight"]
assert float(meta["format"]["duration"]) >= 2.0
assert int(s.get("nb_frames", 0)) >= 30
for p in layout["displays"]:
    assert p["x"] >= 0 and p["y"] >= 0
    assert p["x"] + p["width"] <= layout["outputWidth"]
    assert p["y"] + p["height"] <= layout["outputHeight"]
PY
            then
                record_result E2E "HEVC and layout geometry" PASS "Video dimensions match configured multi-monitor canvas; duration and frames valid"
            else
                record_result E2E "HEVC and layout geometry" FAIL "Codec, dimensions, duration, frames, or placement bounds mismatch"
            fi

            python3 - "$report_dir/final-status.json" <<'PY' > "$report_dir/layout-regions.tsv"
import json, sys
for i,p in enumerate(json.load(open(sys.argv[1]))["layout"]["displays"]):
    print(i,p["width"],p["height"],p["x"],p["y"],sep="\t")
PY
            signal_ok=1
            while IFS=$'\t' read -r index width height x y; do
                raw="$report_dir/display-$index.raw"
                ffmpeg -v error -ss 1 -i "$saved_file" -vf "crop=$width:$height:$x:$y,scale=16:16,format=gray" -frames:v 1 -f rawvideo "$raw" -y || signal_ok=0
                python3 - "$raw" <<'PY' || signal_ok=0
import pathlib,sys
d=pathlib.Path(sys.argv[1]).read_bytes()
assert len(d)==256 and sum(d)/len(d) > 1.0
PY
            done < "$report_dir/layout-regions.tsv"
            if (( signal_ok == 1 )); then
                record_result E2E "Display region pixels" PASS "Every configured display region contains non-black captured pixels"
            else
                record_result E2E "Display region pixels" FAIL "At least one configured display region is empty or black"
            fi
        elif mdls -name kMDItemDurationSeconds "$saved_file" > "$report_dir/video-metadata.txt" 2>&1; then
            record_result E2E "HEVC and layout geometry" SKIP "ffprobe unavailable; Spotlight metadata only"
        else
            record_result E2E "HEVC and layout geometry" FAIL "Video metadata could not be read"
        fi
    else
        record_result E2E "Real screen recording" FAIL "No non-empty saved file. final status: $final_status"
    fi
fi

python3 - "$results_tsv" "$report_json" <<'PY'
import csv, json, sys
source, target = sys.argv[1:]
rows = []
with open(source, encoding="utf-8") as f:
    for category, name, result, detail in csv.reader(f, delimiter="\t"):
        rows.append({"category": category, "name": name, "result": result, "detail": detail})
with open(target, "w", encoding="utf-8") as f:
    json.dump({"tests": rows}, f, ensure_ascii=False, indent=2)
PY

{
    print "# DualMonitorRecorder 품질 점검 보고서"
    print
    print -r -- "- 실행 시각: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    print -r -- "- 환경: $(sw_vers -productName) $(sw_vers -productVersion), $(uname -m)"
    print -r -- "- 결과: **PASS $pass_count / FAIL $fail_count / SKIP $skip_count**"
    print
    print -r -- "| 분류 | 점검 항목 | 결과 | 상세 |"
    print -r -- "|---|---|---:|---|"
    while IFS=$'\t' read -r category name result detail; do
        print -r -- "| $category | $name | $result | ${detail//|/\\|} |"
    done < "$results_tsv"
    print
    print "## 판정"
    print
    if (( fail_count == 0 )); then
        print "필수 점검을 모두 통과했습니다. 현재 빌드는 배포 후보로 판단할 수 있습니다."
    else
        print "실패 항목이 있습니다. 관련 로그를 확인하고 수정한 뒤 전체 점검을 다시 실행해야 합니다."
    fi
    print
    print "개별 로그와 JSON 결과는 이 보고서와 같은 디렉터리에 있습니다."
} > "$report_md"

print "REPORT=$report_md"
(( fail_count == 0 ))
