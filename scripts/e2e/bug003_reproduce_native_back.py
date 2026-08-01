#!/usr/bin/env python3
"""BUG-003 pre-fix evidence index (committed under Tests/Fixtures)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "Tests" / "Fixtures" / "bug003_pre_fix"


def main() -> int:
    report = ART / "native_back_repro.json"
    if not report.exists():
        raise SystemExit(f"Missing {report}")
    payload = json.loads(report.read_text())
    print(json.dumps(payload, indent=2))
    assert payload.get("native_back_failed") is True
    assert payload.get("commit") == "f029b09"
    assert (ART / "before_native_back.png").exists()
    assert (ART / "after_native_back.png").exists()
    print("Pre-fix native back failure evidence OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
