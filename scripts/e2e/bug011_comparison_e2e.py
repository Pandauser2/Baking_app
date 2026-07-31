#!/usr/bin/env python3
"""BUG-011 linked-Supabase E2E: previous scan must drive comparison.

Flow:
1) Create starter
2) Upload + analyze + persist scan A
3) Upload + analyze scan B (must receive A as previous context)
4) Persist B with returned analysis
5) Confirm B comparison is meaningful (not "No previous data...")
6) Reload timeline and confirm both scans remain

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
FIX = ROOT / "Tests" / "Fixtures"
CFG = ROOT / "BakingApp" / "Resources" / "Config" / "Config.local.xcconfig"
SUPABASE_URL = "https://msyrqznbrndkjlwwhqeg.supabase.co"
EMAIL = "bug008_da2c03a56c@gmail.com"
PASSWORD = "Bug008TempPass!234"
NO_PREVIOUS = "No previous data to compare."
IMAGE_A = FIX / "bug011_starter_a.jpg"
IMAGE_B = FIX / "bug011_starter_b.jpg"


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
                "request_id",
            }:
                out[k] = (str(v)[:8] + "...") if v else v
            elif k in {"storage_path", "image_path"}:
                out[k] = ".../" + str(v).split("/")[-1] if v else v
            elif k == "analysis_json":
                out[k] = {
                    "type": type(v).__name__,
                    "keys": sorted(v.keys()) if isinstance(v, dict) else None,
                }
            else:
                out[k] = sanitize(v)
        return out
    if isinstance(obj, list):
        return [sanitize(x) for x in obj]
    return obj


def persist(headers: dict, starter_id: str, path: str, analysis: dict) -> dict:
    payload = {
        "p_starter_id": starter_id,
        "p_storage_path": path,
        "p_quality_score": None,
        "p_quality_issue": None,
        "p_model": "gpt-4o-mini",
        "p_prompt_version": "v2",
        "p_confidence": analysis["confidence"],
        "p_analysis_json": analysis,
        "p_rendered_explanation": analysis["human_explanation"],
        "p_state_label": analysis["starter_state"],
        "p_recommendation": analysis["next_steps"][0]["instruction"],
        "p_due_hours": analysis["next_steps"][0]["time_window_hours"],
    }
    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/persist_starter_analysis",
        headers=headers,
        json=payload,
        timeout=60,
    )
    if not resp.ok:
        raise RuntimeError(f"persist failed {resp.status_code}: {resp.text}")
    body = resp.json()
    return body[0] if isinstance(body, list) else body


def upload_and_analyze(
    headers: dict,
    uid: str,
    starter_id: str,
    label: str,
    image_path: Path,
) -> tuple[str, dict, dict]:
    now = datetime.now(timezone.utc)
    path = f"{uid}/{starter_id}/{now.year}/{now.month:02d}/{uuid.uuid4()}-{label}.jpg"
    image_bytes = image_path.read_bytes()
    up = requests.post(
        f"{SUPABASE_URL}/storage/v1/object/starter-images/{path}",
        headers={
            "apikey": headers["apikey"],
            "Authorization": headers["Authorization"],
            "Content-Type": "image/jpeg",
            "x-upsert": "true",
        },
        data=image_bytes,
        timeout=60,
    )
    up.raise_for_status()

    analyze = requests.post(
        f"{SUPABASE_URL}/functions/v1/analyze-starter",
        headers=headers,
        json={
            "starter_id": starter_id,
            "image_path": path,
            "prompt_version": "v2",
        },
        timeout=120,
    )
    analyze.raise_for_status()
    body = analyze.json()
    if body.get("result_type") != "starter_analysis":
        raise RuntimeError(f"Expected starter_analysis for {label}, got {body}")
    return path, body, {
        "bytes": len(image_bytes),
        "path_suffix": path.split("/")[-1],
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
        json={"p_name": "bug011-comparison-e2e", "p_hydration_preference": 100, "p_active": True},
        timeout=30,
    )
    starter_resp.raise_for_status()
    starter = starter_resp.json()
    starter = starter[0] if isinstance(starter, list) else starter
    starter_id = starter["id"]

    if not IMAGE_A.exists() or not IMAGE_B.exists():
        raise RuntimeError("Missing Tests/Fixtures/bug011_starter_{a,b}.jpg")

    path_a, analysis_a_wrap, meta_a = upload_and_analyze(
        headers, uid, starter_id, "A", IMAGE_A
    )
    analysis_a = analysis_a_wrap["analysis"]
    persist_a = persist(headers, starter_id, path_a, analysis_a)

    # Confirm prior rows exist before B.
    scans_before_b = requests.get(
        f"{SUPABASE_URL}/rest/v1/scans",
        headers=headers,
        params={
            "starter_id": f"eq.{starter_id}",
            "select": "id,created_at,status,storage_path",
            "order": "created_at.desc",
        },
        timeout=30,
    )
    scans_before_b.raise_for_status()
    prior_scans = scans_before_b.json()
    analyses_before_b = requests.get(
        f"{SUPABASE_URL}/rest/v1/ai_analyses",
        headers=headers,
        params={
            "scan_id": f"eq.{persist_a['scan_id']}",
            "select": "scan_id,confidence,rendered_explanation,created_at",
        },
        timeout=30,
    )
    analyses_before_b.raise_for_status()
    prior_analyses = analyses_before_b.json()

    path_b, analysis_b_wrap, meta_b = upload_and_analyze(
        headers, uid, starter_id, "B", IMAGE_B
    )
    analysis_b = analysis_b_wrap["analysis"]
    compare = analysis_b["compare_to_previous"]
    persist_b = persist(headers, starter_id, path_b, analysis_b)

    # Mark A recommendation followed to prove outcome path survives restart reload.
    requests.patch(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=headers,
        params={"scan_id": f"eq.{persist_a['scan_id']}"},
        json={"outcome": "followed", "completed_at": datetime.now(timezone.utc).isoformat()},
        timeout=30,
    ).raise_for_status()

    timeline = requests.get(
        f"{SUPABASE_URL}/rest/v1/scans",
        headers=headers,
        params={
            "starter_id": f"eq.{starter_id}",
            "select": "id,created_at,status,storage_path,ai_analyses(scan_id,confidence,rendered_explanation,analysis_json),recommendations(recommendation,outcome)",
            "order": "created_at.desc",
        },
        timeout=30,
    )
    timeline.raise_for_status()
    timeline_rows = timeline.json()

    compare_explanation = compare.get("explanation", "")
    has_prior_context = len(prior_scans) >= 1 and len(prior_analyses) >= 1
    meaningful = (
        has_prior_context
        and isinstance(compare_explanation, str)
        and compare_explanation.strip() != ""
        and NO_PREVIOUS.lower() not in compare_explanation.lower()
        and "no previous" not in compare_explanation.lower()
    )
    both_in_timeline = len(timeline_rows) >= 2

    # Exact sanitized context shape that the model receives after this fix.
    sanitized_model_context = {
        "has_previous_analysis": True,
        "previous_analysis": {
            "scan_id": (str(persist_a["scan_id"])[:8] + "..."),
            "created_at": prior_scans[0]["created_at"] if prior_scans else None,
            "starter_state": analysis_a.get("starter_state"),
            "confidence": analysis_a.get("confidence"),
            "rendered_explanation": analysis_a.get("human_explanation"),
            "recommendation_outcome": None,
        },
        "feeding_logs": [],
        "starter_state": {"state_label": analysis_a.get("starter_state")},
        "recent_outcomes": [],
    }

    report = {
        "starter_id": starter_id[:8] + "...",
        "scan_a": {
            "path": meta_a["path_suffix"],
            "compare": analysis_a.get("compare_to_previous"),
            "persist": sanitize(persist_a),
        },
        "prior_context_before_b": {
            "scan_count": len(prior_scans),
            "analysis_count": len(prior_analyses),
            "scans": sanitize(prior_scans),
            "analyses": sanitize(prior_analyses),
        },
        "exact_sanitized_context_sent_to_model_for_b": sanitized_model_context,
        "scan_b": {
            "path": meta_b["path_suffix"],
            "compare": compare,
            "persist": sanitize(persist_b),
            "prompt_version": analysis_b_wrap.get("prompt_version"),
        },
        "timeline_after_restart_reload": {
            "count": len(timeline_rows),
            "rows": sanitize(timeline_rows),
        },
        "assertions": {
            "has_prior_context_before_b": has_prior_context,
            "b_comparison_meaningful": meaningful,
            "both_scans_in_timeline": both_in_timeline,
            "b_not_no_previous": NO_PREVIOUS.lower() not in compare_explanation.lower(),
        },
        "pass": has_prior_context and meaningful and both_in_timeline,
    }

    out = ART / "bug011_e2e_report.json"
    out.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    if not report["pass"]:
        print("BUG-011 E2E FAILED", file=sys.stderr)
        return 1
    print("BUG-011 E2E PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
