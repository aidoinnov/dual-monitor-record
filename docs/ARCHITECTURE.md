# 아키텍처

## 전체 흐름

```text
GUI / Menu Bar / ⌘F2 / App Intents / URL Scheme
                         │
CLI ─ HTTP :17842 ───────┤
MCP ─ HTTP :17842 ───────┤
                         ▼
                DualDisplayRecorder
                  │             │
            SCStream × N    상태 및 설정
                  │             │
                  ▼             └── WebSocket :17843
          SideBySideCompositor
                  │
             AVAssetWriter
                  │
              HEVC / MOV
```

## 구성요소

### DualDisplayRecorder

모니터 조회, 스트림 시작/중지, 저장 상태, 경과 시간과 마지막 파일을 관리하는 중심 상태 객체입니다. 모든 UI와 자동화 명령은 이 객체로 수렴합니다.

### ScreenCaptureKit

선택된 각 `SCDisplay`마다 `SCStream`을 만들고 BGRA 픽셀 버퍼를 전용 직렬 캡처 큐로 전달합니다. 마우스 포인터도 포함합니다.

### 배치 계산과 합성

저장된 모니터 ID와 X/Y 좌표에서 전체 경계를 계산합니다. 화면별 가로 2560, 전체 7680×4320 제한 안에 들어오도록 모든 크기와 좌표를 같은 비율로 축소하고 인코더 호환을 위해 짝수 픽셀 크기를 사용합니다.

`SideBySideCompositor`는 각 화면의 최신 버퍼를 Core Image로 목적 프레임에 배치합니다. 빈 영역은 검은색입니다.

### 영상 기록

`AVAssetWriter`와 픽셀 버퍼 어댑터가 실시간 입력을 HEVC 비디오가 포함된 MOV로 기록합니다. 목표 프레임률은 30fps입니다.

### 설정

`UserDefaults`에 저장 위치 질문 여부, 기본 폴더, 디스플레이 ID/활성 상태/X/Y 배치를 보관합니다.

### 자동화

- `LocalControlServer`: loopback 17842 HTTP/JSON
- `StatusWebSocketServer`: loopback 17843 상태 스트림
- `dualrec`: HTTP API를 호출하는 Swift CLI
- `mcp-server.mjs`: HTTP API를 MCP tools로 변환하는 stdio 서버
- URL Scheme/App Intents: macOS 자동화 진입점

## 동시성

- UI와 녹화 상태 변경: MainActor
- 화면 샘플과 합성: 전용 직렬 큐
- HTTP와 WebSocket: 각각 별도 DispatchQueue
- 시작/중지 전환 중 `isBusy`로 중복 명령 방지

## 보안 경계

HTTP와 WebSocket은 loopback에서만 제공합니다. 토큰 인증은 없으므로 외부 프록시와 포트 포워딩은 지원하지 않습니다. 화면 접근은 macOS TCC와 앱 코드서명으로 보호됩니다.
