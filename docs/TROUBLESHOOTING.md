# 권한 및 문제 해결

## 권한이 켜져 있는데 팝업이 반복됨

코드서명이 바뀌면 macOS TCC가 다른 앱으로 판단할 수 있습니다. 정식 인증서로 다시 빌드하고 화면 기록 항목을 껐다 켠 뒤 앱을 완전히 재실행합니다.

필요하면 이 앱의 권한 기록만 초기화합니다.

```bash
tccutil reset ScreenCapture local.dual-monitor-recorder
```

이후 다시 권한을 허용해야 합니다.

## CLI 연결 실패

CLI는 실행 중인 앱의 API를 호출합니다.

```bash
open dist/DualMonitorRecorder.app
dist/bin/dualrec status
```

헤드리스 실행:

```bash
dist/DualMonitorRecorder.app/Contents/MacOS/DualMonitorRecorder --headless &
dist/bin/dualrec status
```

포트 확인:

```bash
lsof -nP -iTCP:17842 -sTCP:LISTEN
lsof -nP -iTCP:17843 -sTCP:LISTEN
```

## 시작 성공 후 파일이 없음

명령은 비동기입니다. 시작 후 `recording: true`, 중지 후 `busy: false`, 완료 후 `savedFile`이 null이 아닌지 확인합니다. `status` 메시지에 권한이나 모니터 선택 오류가 있는지도 봅니다.

## 녹화할 모니터가 없다는 오류

설정에서 최소 한 대를 체크합니다. 연결 상태가 바뀌었다면 **실제 배치 불러오기**를 누릅니다.

## 단축키가 동작하지 않음

기본은 `Command + F2`입니다. F2가 밝기 키라면 `Command + fn + F2`를 사용하고 다른 앱이 같은 전역 단축키를 선점했는지 확인합니다.

## 창을 닫아도 프로세스가 남음

메뉴 막대 상주가 의도된 동작입니다. 완전 종료는 메뉴 막대의 **DualMonitorRecorder 종료**를 사용합니다.

## 소리가 없음

현재 화면과 포인터만 녹화하며 시스템 오디오와 마이크는 미지원입니다.

## 영상 크기가 작아짐

화면별 2560픽셀과 전체 7680×4320 제한 안에 들어오도록 배치를 비례 축소합니다.

## 전체 진단

```bash
scripts/quality-check.sh
```

단계별 로그는 `test-reports/<실행시각>/`에 남습니다.
