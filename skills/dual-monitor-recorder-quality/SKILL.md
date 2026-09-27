---
name: dual-monitor-recorder-quality
description: Run and interpret repeatable quality checks for the DualMonitorRecorder macOS app, including unit tests, signed packaging, local integrations, MCP, WebSocket, and real screen-recording validation.
---

# Dual Monitor Recorder Quality

Use the repository's `scripts/quality-check.sh` as the authoritative test entrypoint. It creates timestamped Markdown and JSON evidence under `test-reports/`.

1. Resolve the repository containing `Package.swift`, `build-app.sh`, and `scripts/quality-check.sh`.
2. Read [references/quality-gates.md](references/quality-gates.md) before changing test scope or interpreting readiness.
3. Run `scripts/run_quality.py <repository-root>`.
4. Inspect the generated report and every failed or skipped check.
5. After fixes, rerun the entire suite so the final report represents one consistent build.

The default suite creates a short real MOV. Use `DUALREC_SKIP_RECORDING=1` only when capture is intentionally excluded; a skip is not a release-ready pass. Treat TCC permission denial as an environment blocker, preserve evidence, and do not delete generated reports or recordings without authorization.
