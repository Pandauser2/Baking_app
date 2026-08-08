#!/usr/bin/env python3
"""Phase C1.5 loaf persistence E2E against linked Supabase.

Flow: bake -> upload loaf image -> analyze-loaf (no DB write) ->
persist_loaf_analysis -> reload -> idempotent retry -> unauthorized bake rejected.
"""

from __future__ import annotations

import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "artifacts" / "e2e" / "phase_c15_loaf_persist"
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
            if k in {"id", "user_id", "starter_id", "bake_id", "scan_id", "analysis_id"}:
                out[k] = (str(v)[:8] + "...") if v else v
            elif k == "storage_path":
                out[k] = ".../" + str(v).split("/")[-1] if v else v
            else:
                out[k] = sanitize(v)
        return out
    if isinstance(obj, list):
        return [sanitize(x) for x in obj]
    return obj


def auth_headers(anon: str, token: str) -> dict:
    return {
        "apikey": anon,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


FIXTURE_IMAGE = ROOT / "Tests" / "Fixtures" / "bug011_starter_a.jpg"


def loaf_image_bytes() -> bytes:
    if not FIXTURE_IMAGE.exists():
        raise RuntimeError(f"Missing fixture image: {FIXTURE_IMAGE}")
    data = FIXTURE_IMAGE.read_bytes()
    if len(data) < 8_000:
        raise RuntimeError("Fixture image too small for analyze-loaf")
    return data


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
    user_id = session["user"]["id"]
    headers = auth_headers(anon, token)

    starters = requests.get(
        f"{SUPABASE_URL}/rest/v1/starters?select=id&order=active.desc&limit=1",
        headers=headers,
        timeout=30,
    )
    starters.raise_for_status()
    starter_id = starters.json()[0]["id"]

    bake_payload = {
        "user_id": user_id,
        "starter_id": starter_id,
        "baked_at": datetime.now(timezone.utc).isoformat(),
        "name": f"C15 Loaf Persist {uuid.uuid4().hex[:8]}",
        "dough_hydration_percent": 75,
        "bulk_fermentation_minutes": 240,
        "final_proof_minutes": 120,
        "mixing_method": "Hand mix",
        "shaping_method": "Boule",
        "oven_temperature_c": 230,
        "baking_time_minutes": 40,
        "result_rating": 4,
    }
    bake_resp = requests.post(f"{SUPABASE_URL}/rest/v1/bakes", headers=headers, json=bake_payload, timeout=30)
    bake_resp.raise_for_status()
    bake_id = bake_resp.json()[0]["id"]

    image_id = uuid.uuid4().hex
    storage_path = f"{user_id}/2026/08/{image_id}.jpg"
    image_bytes = loaf_image_bytes()
    upload = requests.post(
        f"{SUPABASE_URL}/storage/v1/object/loaf-images/{storage_path}",
        headers={
            "apikey": anon,
            "Authorization": f"Bearer {token}",
            "Content-Type": "image/jpeg",
            "x-upsert": "false",
        },
        data=image_bytes,
        timeout=60,
    )
    upload.raise_for_status()

    # Count loaf_scans before analyze (must not increase).
    before_legacy = requests.get(
        f"{SUPABASE_URL}/rest/v1/loaf_scans?select=id&image_path=eq.{storage_path}",
        headers=headers,
        timeout=30,
    )
    before_legacy.raise_for_status()
    before_count = len(before_legacy.json())

    analyze = requests.post(
        f"{SUPABASE_URL}/functions/v1/analyze-loaf",
        headers=headers,
        json={"image_path": storage_path, "prompt_version": "v1"},
        timeout=120,
    )
    if not analyze.ok:
        raise RuntimeError(f"analyze-loaf failed: {analyze.status_code} {analyze.text}")
    analyze_body = analyze.json()
    if "analysis" not in analyze_body:
        raise RuntimeError(f"analyze-loaf missing analysis: {analyze_body}")
    analysis = analyze_body["analysis"]
    model = analyze_body.get("model") or "gpt-4o-mini"
    prompt_version = analyze_body.get("prompt_version") or "v1"

    after_analyze_legacy = requests.get(
        f"{SUPABASE_URL}/rest/v1/loaf_scans?select=id&image_path=eq.{storage_path}",
        headers=headers,
        timeout=30,
    )
    after_analyze_legacy.raise_for_status()
    assert len(after_analyze_legacy.json()) == before_count

    # Persist via authenticated RPC (canonical Phase C path).
    persist_body = {
        "p_bake_id": bake_id,
        "p_storage_path": storage_path,
        "p_model": model,
        "p_prompt_version": prompt_version,
        "p_confidence": max(0.0, min(1.0, float(analysis.get("overall_score", 50)) / 100.0)),
        "p_analysis_json": analysis,
        "p_rendered_explanation": analysis.get("summary") or "Loaf analysis",
        "p_quality_score": None,
        "p_quality_issue": None,
    }
    persist = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/persist_loaf_analysis",
        headers=headers,
        json=persist_body,
        timeout=30,
    )
    persist.raise_for_status()
    first_ids = persist.json()
    if isinstance(first_ids, list):
        first_ids = first_ids[0]

    # Idempotent retry
    persist2 = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/persist_loaf_analysis",
        headers=headers,
        json=persist_body,
        timeout=30,
    )
    persist2.raise_for_status()
    second_ids = persist2.json()
    if isinstance(second_ids, list):
        second_ids = second_ids[0]
    assert first_ids["scan_id"] == second_ids["scan_id"]
    assert first_ids["analysis_id"] == second_ids["analysis_id"]

    scans = requests.get(
        f"{SUPABASE_URL}/rest/v1/scans?select=id,bake_id,scan_type,storage_path&storage_path=eq.{storage_path}&scan_type=eq.loaf",
        headers=headers,
        timeout=30,
    )
    scans.raise_for_status()
    scan_rows = scans.json()
    assert len(scan_rows) == 1
    assert scan_rows[0]["bake_id"] == bake_id

    analyses = requests.get(
        f"{SUPABASE_URL}/rest/v1/ai_analyses?select=id,scan_id&scan_id=eq.{first_ids['scan_id']}",
        headers=headers,
        timeout=30,
    )
    analyses.raise_for_status()
    assert len(analyses.json()) == 1

    after_legacy = requests.get(
        f"{SUPABASE_URL}/rest/v1/loaf_scans?select=id&image_path=eq.{storage_path}",
        headers=headers,
        timeout=30,
    )
    after_legacy.raise_for_status()
    assert len(after_legacy.json()) == before_count

    # Unauthorized: cannot attach to another user's bake (random bake id).
    foreign = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/persist_loaf_analysis",
        headers=headers,
        json={
            **persist_body,
            "p_bake_id": str(uuid.uuid4()),
            "p_storage_path": f"{user_id}/2026/08/{uuid.uuid4().hex}.jpg",
        },
        timeout=30,
    )
    unauthorized_rejected = foreign.status_code >= 400

    # Reload persistence
    reload_scans = requests.get(
        f"{SUPABASE_URL}/rest/v1/scans?select=id,bake_id,ai_analyses(id)&bake_id=eq.{bake_id}&scan_type=eq.loaf",
        headers=headers,
        timeout=30,
    )
    reload_scans.raise_for_status()
    assert len(reload_scans.json()) == 1

    evidence = {
        "bake_id": bake_id[:8] + "...",
        "storage_path": ".../" + storage_path.split("/")[-1],
        "analyze_returned_analysis": bool(analysis),
        "analyze_wrote_loaf_scans": len(after_analyze_legacy.json()) != before_count,
        "first_ids": sanitize(first_ids),
        "idempotent_same_ids": first_ids == second_ids,
        "scan_count_for_path": len(scan_rows),
        "analysis_count": len(analyses.json()),
        "legacy_loaf_scans_unchanged": len(after_legacy.json()) == before_count,
        "unauthorized_rejected": unauthorized_rejected,
        "reload_count": len(reload_scans.json()),
    }
    out = ART / "phase_c15_loaf_persist_e2e.json"
    out.write_text(json.dumps(evidence, indent=2))
    print(json.dumps(evidence, indent=2))
    if not all(
        [
            evidence["analyze_returned_analysis"],
            not evidence["analyze_wrote_loaf_scans"],
            evidence["idempotent_same_ids"],
            evidence["scan_count_for_path"] == 1,
            evidence["legacy_loaf_scans_unchanged"],
            evidence["unauthorized_rejected"],
            evidence["reload_count"] == 1,
        ]
    ):
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"E2E failed: {exc}", file=sys.stderr)
        raise
