#!/usr/bin/env python3
"""BUG-010 production-like E2E validation against linked Supabase.

Validates the complete save transaction:
persist RPC -> committed rows -> recommendation/state/timeline decode ->
idempotent retry -> restart reload proof.

Writes sanitized artifacts under artifacts/e2e/.
"""

from __future__ import annotations

import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "artifacts" / "e2e"
CFG = ROOT / "BakingApp" / "Resources" / "Config" / "Config.local.xcconfig"
SUPABASE_URL = "https://msyrqznbrndkjlwwhqeg.supabase.co"
EMAIL = "bug008_da2c03a56c@gmail.com"
PASSWORD = "Bug008TempPass!234"


def anon_key() -> str:
    for line in CFG.read_text().splitlines():
        if line.strip().startswith("SUPABASE_ANON_KEY"):
            return line.split("=", 1)[1].strip()
    raise RuntimeError("SUPABASE_ANON_KEY missing")


def sanitize(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k in {
                "id",
                "user_id",
                "starter_id",
                "scan_id",
                "analysis_id",
                "recommendation_id",
                "updated_from_scan_id",
                "bake_id",
            }:
                out[k] = (str(v)[:8] + "...") if v else v
            elif k == "storage_path":
                out[k] = ".../" + str(v).split("/")[-1] if v else v
            elif k == "analysis_json":
                out[k] = {"type": type(v).__name__, "keys": sorted(v.keys()) if isinstance(v, dict) else None}
            else:
                out[k] = sanitize(v)
        return out
    if isinstance(obj, list):
        return [sanitize(x) for x in obj]
    return obj


def decode_timeline_shape(row: dict) -> dict:
    analyses = row.get("ai_analyses")
    recommendations = row.get("recommendations")
    return {
        "ai_analyses_type": type(analyses).__name__,
        "recommendations_type": type(recommendations).__name__,
        "has_fractional_created_at": "." in str(row.get("created_at", "")).split("T")[-1],
    }


def main() -> int:
    ART.mkdir(parents=True, exist_ok=True)
    anon = anon_key()
    signin = requests.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={"apikey": anon, "Content-Type": "application/json"},
        json={"email": EMAIL, "password": PASSWORD},
        timeout=30,
    )
    signin.raise_for_status()
    session = signin.json()
    token = session["access_token"]
    uid = session["user"]["id"]
    headers = {
        "apikey": anon,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }

    starter_resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/create_starter_profile",
        headers=headers,
        json={"p_name": "bug010-e2e-final", "p_hydration_preference": 100, "p_active": True},
        timeout=30,
    )
    starter_resp.raise_for_status()
    starter = starter_resp.json()
    starter = starter[0] if isinstance(starter, list) else starter
    starter_id = starter["id"]

    now = datetime.now(timezone.utc)
    path = f"{uid}/{starter_id}/{now.year}/{now.month:02d}/{uuid.uuid4()}.jpg"
    analysis = {
        "scan_type": "starter",
        "observations": ["Visible bubbles"],
        "diagnosis": ["active"],
        "confidence": 0.84,
        "next_steps": [{"instruction": "Feed now", "time_window_hours": 12}],
        "human_explanation": "Starter looks active.",
        "risk_flags": [],
        "compare_to_previous": {"changed": True, "explanation": "More bubbles"},
        "starter_state": "active",
    }
    payload = {
        "p_starter_id": starter_id,
        "p_storage_path": path,
        "p_quality_score": None,
        "p_quality_issue": None,
        "p_model": "gpt-4o-mini",
        "p_prompt_version": "v1",
        "p_confidence": analysis["confidence"],
        "p_analysis_json": analysis,
        "p_rendered_explanation": analysis["human_explanation"],
        "p_state_label": analysis["starter_state"],
        "p_recommendation": analysis["next_steps"][0]["instruction"],
        "p_due_hours": analysis["next_steps"][0]["time_window_hours"],
    }

    rpc1 = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/persist_starter_analysis",
        headers=headers,
        json=payload,
        timeout=30,
    )
    rpc2 = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/persist_starter_analysis",
        headers=headers,
        json=payload,
        timeout=30,
    )
    body1 = rpc1.json()
    body2 = rpc2.json()
    ids1 = body1[0] if isinstance(body1, list) else body1
    ids2 = body2[0] if isinstance(body2, list) else body2

    state = requests.get(
        f"{SUPABASE_URL}/rest/v1/starter_states?select=*&starter_id=eq.{starter_id}&limit=1",
        headers={"apikey": anon, "Authorization": f"Bearer {token}"},
        timeout=30,
    ).json()
    recommendation = requests.get(
        f"{SUPABASE_URL}/rest/v1/recommendations?select=*&id=eq.{ids1['recommendation_id']}",
        headers={"apikey": anon, "Authorization": f"Bearer {token}"},
        timeout=30,
    ).json()
    timeline = requests.get(
        f"{SUPABASE_URL}/rest/v1/scans?select=*,ai_analyses(*),recommendations(*)&starter_id=eq.{starter_id}&scan_type=eq.starter&order=created_at.desc",
        headers={"apikey": anon, "Authorization": f"Bearer {token}"},
        timeout=30,
    ).json()

    def count(table: str, query: str) -> int:
        rows = requests.get(
            f"{SUPABASE_URL}/rest/v1/{table}?{query}&select=id",
            headers={"apikey": anon, "Authorization": f"Bearer {token}"},
            timeout=30,
        ).json()
        return len(rows)

    scan_count = count("scans", f"starter_id=eq.{starter_id}&storage_path=eq.{path}")
    analysis_count = count("ai_analyses", f"scan_id=eq.{ids1['scan_id']}")
    recommendation_count = count("recommendations", f"scan_id=eq.{ids1['scan_id']}")
    state_count = len(state)

    # Restart/reload proof: re-query by returned IDs after a second auth session.
    signin2 = requests.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={"apikey": anon, "Content-Type": "application/json"},
        json={"email": EMAIL, "password": PASSWORD},
        timeout=30,
    )
    signin2.raise_for_status()
    token2 = signin2.json()["access_token"]
    reload_headers = {"apikey": anon, "Authorization": f"Bearer {token2}"}
    reload_state = requests.get(
        f"{SUPABASE_URL}/rest/v1/starter_states?select=*&starter_id=eq.{starter_id}&limit=1",
        headers=reload_headers,
        timeout=30,
    ).json()
    reload_rec = requests.get(
        f"{SUPABASE_URL}/rest/v1/recommendations?select=*&id=eq.{ids1['recommendation_id']}",
        headers=reload_headers,
        timeout=30,
    ).json()
    reload_timeline = requests.get(
        f"{SUPABASE_URL}/rest/v1/scans?select=*,ai_analyses(*),recommendations(*)&starter_id=eq.{starter_id}&scan_type=eq.starter&order=created_at.desc",
        headers=reload_headers,
        timeout=30,
    ).json()

    report = {
        "rpc1_status": rpc1.status_code,
        "rpc2_status": rpc2.status_code,
        "rpc1_shape": "array" if isinstance(body1, list) else "object",
        "rpc2_shape": "array" if isinstance(body2, list) else "object",
        "same_ids_on_retry": ids1 == ids2,
        "row_counts": {
            "scans_for_path": scan_count,
            "ai_analyses_for_scan": analysis_count,
            "recommendations_for_scan": recommendation_count,
            "starter_states": state_count,
        },
        "recommendation_present": bool(recommendation),
        "starter_state_present": bool(state),
        "timeline_shape": decode_timeline_shape(timeline[0]) if timeline else None,
        "restart_reload": {
            "state_present": bool(reload_state),
            "recommendation_present": bool(reload_rec),
            "timeline_count": len(reload_timeline),
            "timeline_shape": decode_timeline_shape(reload_timeline[0]) if reload_timeline else None,
        },
        "sanitized": {
            "rpc_ids": sanitize(ids1),
            "state": sanitize(state),
            "recommendation": sanitize(recommendation),
            "timeline_first": sanitize(timeline[0]) if timeline else None,
        },
    }

    (ART / "bug010_e2e_report.json").write_text(json.dumps(report, indent=2))
    (ART / "bug010_timeline_fixture.json").write_text(json.dumps(sanitize(timeline), indent=2))
    (ART / "bug010_e2e.log").write_text(
        "\n".join(
            [
                f"rpc1_status={report['rpc1_status']}",
                f"rpc2_status={report['rpc2_status']}",
                f"same_ids_on_retry={report['same_ids_on_retry']}",
                f"row_counts={json.dumps(report['row_counts'])}",
                f"recommendation_present={report['recommendation_present']}",
                f"restart_reload={json.dumps(report['restart_reload'])}",
            ]
        )
        + "\n"
    )

    ok = (
        rpc1.status_code == 200
        and rpc2.status_code == 200
        and report["same_ids_on_retry"] is True
        and scan_count == 1
        and analysis_count == 1
        and recommendation_count == 1
        and state_count == 1
        and report["recommendation_present"]
        and report["starter_state_present"]
        and report["restart_reload"]["state_present"]
        and report["restart_reload"]["recommendation_present"]
        and report["restart_reload"]["timeline_count"] >= 1
    )
    print(json.dumps({"ok": ok, "artifact": str(ART / "bug010_e2e_report.json"), "summary": report}, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
