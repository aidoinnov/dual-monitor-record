# AI 및 MCP 연동

## 환경별 권장 인터페이스

| AI 실행 환경 | 권장 방식 |
|---|---|
| 셸 실행 가능 에이전트 | CLI |
| 로컬 앱/서비스 | HTTP + WebSocket |
| MCP 클라이언트 | MCP 서버 |
| macOS 자동화 | App Intents 또는 URL Scheme |

모든 인터페이스는 하나의 앱 상태를 공유하므로 별도 녹화 세션을 만들지 않습니다.

## MCP 설정

MCP 서버는 `integrations/mcp-server.mjs`이며 외부 npm 패키지가 필요 없습니다.

```json
{
  "mcpServers": {
    "dual-monitor-recorder": {
      "command": "node",
      "args": [
        "/absolute/path/to/dual-monitor-record/integrations/mcp-server.mjs"
      ]
    }
  }
}
```

다른 API 주소를 사용할 경우 `DUALREC_URL` 환경 변수로 지정합니다.

## MCP 도구

| 도구 | 설명 |
|---|---|
| `get_status` | 현재 상태 JSON 조회 |
| `start_recording` | 녹화 시작 요청 |
| `stop_recording` | 녹화 중지 요청 |
| `toggle_recording` | 시작/중지 전환 |
| `open_latest` | 마지막 영상 열기 |
| `reveal_latest` | Finder에서 마지막 영상 선택 |
| `convert_latest_for_windows` | 마지막 MOV를 Windows용 H.264 MP4로 변환 |

모든 도구는 현재 인자를 받지 않습니다.

## AI의 권장 녹화 순서

1. `get_status`로 앱 연결과 현재 상태를 확인합니다.
2. 이미 녹화 중이면 중복 시작하지 않습니다.
3. `start_recording`을 호출합니다.
4. `recording: true`가 될 때까지 상태를 확인합니다.
5. 작업 완료 후 `stop_recording`을 호출합니다.
6. `busy: false`, `recording: false`, `savedFile != null`이 될 때까지 기다립니다.
7. 필요하면 생성 파일을 검사하거나 `reveal_latest`를 호출합니다.

## 보안과 제한

- 최초 화면 기록 권한 승인은 AI가 우회할 수 없습니다.
- API는 로컬 전용이지만 같은 사용자 계정의 프로세스는 호출할 수 있습니다.
- MCP 서버는 앱을 실행하지 않으므로 앱 또는 `--headless` 프로세스를 먼저 실행합니다.
- 모니터 배치 변경, 시스템 오디오, 마이크는 아직 MCP API에 없습니다.

## 프로토콜 확인

```bash
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | node integrations/mcp-server.mjs
```

이 검증은 전체 품질 스크립트에도 포함됩니다.
