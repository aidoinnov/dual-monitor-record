# CLI 및 자동화 API

## 공통 전제와 헤드리스 실행

자동화 인터페이스는 실행 중인 앱을 제어합니다. 앱이 꺼져 있으면 CLI, HTTP와 WebSocket은 연결할 수 없습니다.

```bash
dist/DualMonitorRecorder.app/Contents/MacOS/DualMonitorRecorder --headless
```

`--headless`는 창 없이 API와 녹화 엔진을 실행합니다. 최초 화면 기록 권한 승인은 macOS 시스템 설정에서 사람이 수행해야 합니다.

## CLI

실행 파일은 `dist/bin/dualrec`입니다.

| 명령 | 설명 |
|---|---|
| `status` | 현재 상태를 JSON으로 출력 |
| `start` | 녹화 시작 요청 |
| `stop` | 녹화 중지 및 파일 마무리 요청 |
| `toggle` | 현재 상태에 따라 시작 또는 중지 |
| `open` | 마지막 영상을 기본 플레이어로 열기 |
| `reveal` | 마지막 영상을 Finder에서 선택 |
| `convert` | 마지막 MOV를 Windows용 H.264 MP4로 변환 |

```bash
dist/bin/dualrec status
dist/bin/dualrec start
sleep 10
dist/bin/dualrec stop
```

`start`, `stop`, `toggle`은 비동기입니다. 응답 성공이 영상 저장 완료를 뜻하지 않으므로 `status`의 `busy`, `recording`, `savedFile`을 확인합니다.

종료 코드는 성공 `0`, 앱 연결/HTTP 오류 `1`, 잘못된 명령 `2`입니다.

## 상태 JSON

```json
{
  "recording": false,
  "busy": false,
  "status": "저장 완료: dual-monitor-20260927-155508.mov",
  "elapsed": "00:00:00",
  "savedFile": "/Users/user/Movies/DualMonitorRecorder/dual-monitor-20260927-155508.mov",
  "shortcut": "Command+F2"
}
```

| 필드 | 의미 |
|---|---|
| `recording` | 프레임 캡처 중인지 여부 |
| `busy` | 시작 또는 저장 마무리 작업 중인지 여부 |
| `status` | 현재 상태 설명 또는 오류 |
| `elapsed` | 녹화 경과 시간 `HH:mm:ss` |
| `savedFile` | 마지막 저장 파일 절대 경로 또는 null |
| `shortcut` | 등록된 전역 단축키 |

## HTTP API

기본 주소는 `http://127.0.0.1:17842`이며 외부 네트워크에는 바인딩하지 않습니다.

| Method | Path | 응답 | 설명 |
|---|---|---:|---|
| GET | `/v1/status` | 200 | 상태 조회 |
| POST | `/v1/recording/start` | 202 | 녹화 시작 요청 |
| POST | `/v1/recording/stop` | 202 | 녹화 중지 요청 |
| POST | `/v1/recording/toggle` | 202 | 상태 전환 |
| POST | `/v1/latest/open` | 200 | 마지막 영상 열기 |
| POST | `/v1/latest/reveal` | 200 | Finder에서 마지막 영상 표시 |
| POST | `/v1/latest/convert-windows` | 202 | 마지막 MOV의 H.264 MP4 변환 요청 |

```bash
curl -sS http://127.0.0.1:17842/v1/status
curl -sS -X POST http://127.0.0.1:17842/v1/recording/start
curl -sS -X POST http://127.0.0.1:17842/v1/recording/stop
```

현재 별도 토큰 인증은 없습니다. 로컬 포트를 외부 인터페이스로 프록시하거나 공개하면 안 됩니다.

## WebSocket

`ws://127.0.0.1:17843`에 연결하면 약 1초마다 상태 JSON을 텍스트 프레임으로 받습니다.

```js
const socket = new WebSocket("ws://127.0.0.1:17843");
socket.onmessage = ({ data }) => console.log(JSON.parse(data));
```

WebSocket은 상태 구독 전용이며 명령은 HTTP, CLI 또는 MCP로 전송합니다.

## URL Scheme

| URL | 동작 |
|---|---|
| `dualrecorder://start` | 녹화 시작 |
| `dualrecorder://stop` | 녹화 중지 |
| `dualrecorder://toggle` | 상태 전환 |
| `dualrecorder://settings` | 설정 창 열기 |
| `dualrecorder://latest` | 마지막 영상 열기 |
| `dualrecorder://identify` | 선택된 녹화 모니터 번호 표시 |

```bash
open 'dualrecorder://start'
```

## AppleScript

```applescript
open location "dualrecorder://start"
delay 10
open location "dualrecorder://stop"
```

상태가 필요하면 CLI를 호출합니다.

```applescript
set recorderStatus to do shell script "/absolute/path/dist/bin/dualrec status"
```

## macOS 단축어와 Siri

앱에는 **듀얼 모니터 녹화 시작**과 **듀얼 모니터 녹화 중지** App Intent가 포함됩니다. 앱을 한 번 실행한 후 단축어 앱에서 검색해 추가할 수 있습니다.
