# DualMonitorRecorder

여러 macOS 디스플레이를 동시에 캡처하고, 사용자가 설정한 배치대로 하나의 HEVC/MOV 영상으로 저장하는 메뉴 막대 앱입니다. GUI뿐 아니라 CLI, HTTP, WebSocket, URL Scheme, AppleScript, macOS 단축어와 MCP를 통해 제어할 수 있습니다.

앱 아이콘 원본은 `App/Assets/AppIcon.png`, macOS 번들 리소스는 `App/AppIcon.icns`에 있습니다.

## 현재 지원 범위

- 연결된 모니터 1대 이상 동시 녹화
- 설정 화면에서 녹화 대상 선택 및 드래그 배치
- 최대 7680×4320 캔버스로 자동 축소
- 메뉴 막대 상주 및 `⌘F2` 전역 시작/중지
- 기본 저장 위치 자동 저장 또는 녹화마다 위치 선택
- CLI, HTTP API, WebSocket, URL Scheme, AppleScript, App Intents, MCP
- 창 없는 `--headless` 실행
- 단위·통합·실제 녹화 E2E 테스트와 Markdown/JSON 보고서

현재 오디오는 녹음하지 않습니다. 화면과 마우스 포인터만 영상에 포함됩니다.

## 빠른 시작

요구 환경은 macOS 13 이상과 Xcode 15 이상입니다.

```bash
chmod +x build-app.sh scripts/quality-check.sh
./build-app.sh
open dist/DualMonitorRecorder.app
```

처음 녹화를 시작할 때 **시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음**에서 `DualMonitorRecorder`를 허용하고 앱을 재실행해야 합니다.

기본 저장 위치는 `~/Movies/DualMonitorRecorder/dual-monitor-YYYYMMDD-HHMMSS.mov`입니다.

## CLI 빠른 확인

앱이 실행 중이어야 합니다.

```bash
dist/bin/dualrec status
dist/bin/dualrec start
dist/bin/dualrec stop
dist/bin/dualrec toggle
dist/bin/dualrec open
dist/bin/dualrec reveal
```

## 문서

- [사용자 안내](docs/USER_GUIDE.md)
- [CLI와 자동화 API](docs/AUTOMATION_API.md)
- [MCP와 AI 연동](docs/AI_INTEGRATION.md)
- [아키텍처](docs/ARCHITECTURE.md)
- [빌드·테스트·릴리스](docs/QUALITY_AND_RELEASE.md)
- [권한 및 문제 해결](docs/TROUBLESHOOTING.md)
- [남은 작업](TODO.md)

## 전체 품질 점검

```bash
scripts/quality-check.sh
```

앱을 헤드리스로 실행한 뒤 단위 테스트, 빌드, 서명, CLI/API/MCP/WebSocket, 실제 녹화와 MOV 무결성까지 검사합니다. 결과는 `test-reports/<실행시각>/`에 Markdown과 JSON으로 저장됩니다.

현재 품질 기준은 **PASS 16 / FAIL 0 / SKIP 0**입니다. 실행할 때마다 `test-reports/<실행시각>/QUALITY_REPORT.md`가 새로 생성됩니다.
