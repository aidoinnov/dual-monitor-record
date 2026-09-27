# 빌드, 테스트 및 릴리스

## 빌드

```bash
swift build
./build-app.sh
```

배포 생성물은 `dist/DualMonitorRecorder.app`과 `dist/bin/dualrec`입니다.

빌드 스크립트는 `DUAL_RECORDER_SIGNING_IDENTITY`로 지정한 인증서를 사용하며, 지정하지 않으면 키체인에서 사용 가능한 첫 코드서명 인증서를 선택합니다. 인증서가 없으면 임시 서명을 쓰지만 재빌드 시 화면 기록 권한이 무효화될 수 있습니다.

## 단위 테스트

```bash
swift test
```

현재 모니터 배치 모델 JSON 직렬화, 기본 저장 폴더, 사용자 지정 폴더 반영을 검사합니다.

## 전체 품질 게이트

```bash
scripts/quality-check.sh
```

검사 항목:

1. Swift 단위 테스트
2. Debug 빌드
3. Release 앱 번들
4. Info.plist
5. 엄격한 코드서명
6. 헤드리스 실행
7. HTTP API
8. CLI
9. MCP initialize/tools
10. WebSocket 상태
11. URL Scheme
12. 실제 화면 녹화
13. HEVC 코덱, 재생 시간과 프레임 수
14. 설정 배치와 실제 영상 캔버스 좌표 일치
15. 모든 모니터 배치 영역의 실제 픽셀 신호

실제 녹화를 의도적으로 제외할 때만 다음을 사용합니다.

```bash
DUALREC_SKIP_RECORDING=1 scripts/quality-check.sh
```

이 경우 `SKIP`이 남아 완전한 배포 준비를 증명하지 못합니다.

## 보고서

```text
test-reports/YYYYMMDD-HHMMSS/
├── QUALITY_REPORT.md
├── results.json
├── results.tsv
├── unit-swift-tests.log
├── http-status.json
├── websocket.json
├── mcp.jsonl
├── video-metadata.json
└── 단계별 로그
```

- `FAIL`이 하나라도 있으면 배포 불가
- 환경상 미수행은 `SKIP`
- `FAIL 0 / SKIP 0`일 때 완전한 배포 후보
- 이전 보고서는 현재 소스의 검증으로 재사용하지 않음

## 품질유지 스킬

저장소의 `skills/dual-monitor-recorder-quality/`를 Codex skills 디렉터리에 설치하면 앱 변경, 회귀 조사, 릴리스 준비와 보고서 생성 절차를 재사용할 수 있습니다.

현재 기준선은 PASS 15 / FAIL 0 / SKIP 0입니다. 앱 아이콘 번들, CLI 시작, HTTP 중지, WebSocket 상태 변화, MCP 도구 호출과 설정 배치 그대로의 HEVC/MOV 녹화까지 통과했습니다. 최신 보고서는 로컬 `test-reports/`에 생성됩니다.
