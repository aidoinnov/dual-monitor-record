# Quality gates

A build is a release candidate only when all applicable checks pass in one run:

- Swift unit tests
- Debug and release builds
- Info.plist and non-ad-hoc certificate signature
- Headless runtime and global hotkey registration
- CLI, HTTP, MCP and WebSocket integration
- Real ScreenCaptureKit recording
- HEVC codec, duration, frame count and configured display geometry
- Non-empty pixels in every configured display region

Any `FAIL` prevents readiness. A `SKIP` is intentionally unverified, not a pass.
