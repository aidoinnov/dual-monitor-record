#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else os.getcwd()).resolve()
    script = root / "scripts" / "quality-check.sh"
    required = [root / "Package.swift", root / "build-app.sh", script]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        print("Not a DualMonitorRecorder repository; missing: " + ", ".join(missing), file=sys.stderr)
        return 2
    return subprocess.run([str(script)], cwd=root, env=os.environ.copy()).returncode


if __name__ == "__main__":
    raise SystemExit(main())
