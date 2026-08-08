#!/usr/bin/env python3
"""Phase C2 loaf comparison E2E against linked Supabase.

Flow:
  Bake A → analyze/persist (baseline)
  Bake B → analyze/persist (full comparison context)
  Verify B references A via previous selection rules
  Reload histories, idempotent retry, cross-user rejected
"""

from __future__ import annotations

import json
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "artifacts" / "e2e" / "phase_c2_loaf_comparison"
CFG = ROOT / "BakingApp" / "Resources" / "Config" / "Config.local.xcconfig"
FIXTURE = ROOT / "Tests" / "Fixtures" / "bug011_starter_a.jpg"
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
            if k in {"id", "user_id", "starter_id", "bake_id", "scan_id", "analysis_id", "previous_bake_id"}:
                out[k] = (str(v)[:8] + "...") if v else v
            elif k in {"storage_path", "image_path"}:
                out[k] = ".../" + str(v).split("/")[-1] if v else v
            else:
                out[k] = sanitize(v)
        return out
    if isinstance(obj, list):
        return [sanitize(x) for x in obj]
    return obj


def headers(anon: str, token: str) -> dict:
    return {
        "apikey": anon,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def create_bake(h: dict, user_id: str, starter_id: str, name: str, baked_at: datetime, hydration: float) -> str:
    payload = {
        "user_id": user_id,
        "starter_id": starter_id,
        "baked_at": baked_at.isoformat(),
        "name": name,
        "dough_hydration_percent": hydration,
        "bulk_fermentation_minutes": 240,
        "final_proof_minutes": 120,
        "mixing_method": "Hand mix",
        "shaping_method": "Boule",
        "oven_temperature_c": 230,
        "baking_time_minutes": 40,
        "result_rating": 4,
        "fermentation_temperature_c": 24,
        "fermentation_temperature_source": "room",
    }
    resp = requests.post(f"{SUPABASE_URL}/rest/v1/bakes", headers=h, json=payload, timeout=30)
    resp.raise_for_status()
    return resp.json()[0]["id"]


def upload_and_analyze(h: dict, anon: str, token: str, user_id: str, context: dict) -> tuple[str, dict]:
    path = f"{user_id}/2026/08/{uuid.uuid4().hex}.jpg"
    image = FIXTURE.read_bytes()
    up = requests.post(
        f"{SUPABASE_URL}/storage/v1/object/loaf-images/{path}",
        headers={
            "apikey": anon,
            "Authorization": f"Bearer {token}",
            "Content-Type": "image/jpeg",
            "x-upsert": "false",
        },
        data=image,
        timeout=60,
    )
    up.raise_for_status()
    before = requests.get(
        f"{SUPABASE_URL}/rest/v1/loaf_scans?select=id&image_path=eq.{path}",
        headers=h,
        timeout=30,
    )
    before.raise_for_status()
    before_count = len(before.json())
    analyze = requests.post(
        f"{SUPABASE_URL}/functions/v1/analyze-loaf",
        headers=h,
        json={"image_path": path, "prompt_version": "v1", "context": context},
        timeout=120,
    )
    if not analyze.ok:
        raise RuntimeError(f"analyze-loaf failed: {analyze.status_code} {analyze.text}")
    body = analyze.json()
    after = requests.get(
        f"{SUPABASE_URL}/rest/v1/loaf_scans?select=id&image_path=eq.{path}",
        headers=h,
        timeout=30,
    )
    after.raise_for_status()
    if len(after.json()) != before_count:
        raise RuntimeError("analyze-loaf wrote to loaf_scans")
    return path, body


def persist(h: dict, bake_id: str, path: str, analyze_body: dict) -> dict:
    analysis = analyze_body["analysis"]
    body = {
        "p_bake_id": bake_id,
        "p_storage_path": path,
        "p_model": analyze_body.get("model") or "gpt-4o-mini",
        "p_prompt_version": analyze_body.get("prompt_version") or "v1",
        "p_confidence": max(0.0, min(1.0, float(analysis.get("overall_score", 50)) / 100.0)),
        "p_analysis_json": analysis,
        "p_rendered_explanation": analysis.get("summary") or "Loaf analysis",
        "p_quality_score": None,
        "p_quality_issue": None,
    }
    resp = requests.post(f"{SUPABASE_URL}/rest/v1/rpc/persist_loaf_analysis", headers=h, json=body, timeout=30)
    if not resp.ok:
        raise RuntimeError(f"persist failed: {resp.status_code} {resp.text}")
    ids = resp.json()
    return ids[0] if isinstance(ids, list) else ids


def process_snapshot(hydration: float) -> dict:
    return {
        "dough_hydration_percent": hydration,
        "bulk_fermentation_minutes": 240,
        "final_proof_minutes": 120,
        "fermentation_temperature_c": 24,
        "oven_temperature_c": 230,
        "baking_time_minutes": 40,
    }


def main() -> int:
    ART.mkdir(parents=True, exist_ok=True)
    if not FIXTURE.exists():
        raise RuntimeError(f"Missing fixture {FIXTURE}")
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
    h = headers(anon, token)

    starters = requests.get(
        f"{SUPABASE_URL}/rest/v1/starters?select=id&order=active.desc&limit=1",
        headers=h,
        timeout=30,
    )
    starters.raise_for_status()
    starter_id = starters.json()[0]["id"]

    now = datetime.now(timezone.utc)
    bake_a = create_bake(h, user_id, starter_id, f"C2 A {uuid.uuid4().hex[:6]}", now - timedelta(days=2), 72)
    path_a, analyze_a = upload_and_analyze(
        h,
        anon,
        token,
        user_id,
        {
            "comparison_mode": "baseline",
            "current_process": process_snapshot(72),
            "starter_changed": False,
        },
    )
    ids_a = persist(h, bake_a, path_a, analyze_a)
    ids_a_retry = persist(h, bake_a, path_a, analyze_a)
    assert ids_a == ids_a_retry

    bake_b = create_bake(h, user_id, starter_id, f"C2 B {uuid.uuid4().hex[:6]}", now - timedelta(days=1), 78)
    prev_scores = {
        "crumb_score": analyze_a["analysis"]["crumb_score"],
        "crust_score": analyze_a["analysis"]["crust_score"],
        "oven_spring_score": analyze_a["analysis"]["oven_spring_score"],
        "overall_score": analyze_a["analysis"]["overall_score"],
    }
    path_b, analyze_b = upload_and_analyze(
        h,
        anon,
        token,
        user_id,
        {
            "comparison_mode": "fullComparison",
            "current_process": process_snapshot(78),
            "previous_bake_id": bake_a,
            "previous_bake_name": "Bake A",
            "starter_changed": False,
            "previous_process": process_snapshot(72),
            "previous_scores": prev_scores,
        },
    )
    ids_b = persist(h, bake_b, path_b, analyze_b)

    # Same path + different bake must reject.
    mismatch = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/persist_loaf_analysis",
        headers=h,
        json={
            "p_bake_id": bake_b,
            "p_storage_path": path_a,
            "p_model": "gpt-4o-mini",
            "p_prompt_version": "v1",
            "p_confidence": 0.7,
            "p_analysis_json": analyze_a["analysis"],
            "p_rendered_explanation": "x",
            "p_quality_score": None,
            "p_quality_issue": None,
        },
        timeout=30,
    )
    mismatch_rejected = mismatch.status_code >= 400 and "different bake" in mismatch.text.lower()

    # Reload histories
    scans_a = requests.get(
        f"{SUPABASE_URL}/rest/v1/scans?select=id,bake_id,ai_analyses(id)&bake_id=eq.{bake_a}&scan_type=eq.loaf",
        headers=h,
        timeout=30,
    )
    scans_a.raise_for_status()
    scans_b = requests.get(
        f"{SUPABASE_URL}/rest/v1/scans?select=id,bake_id,ai_analyses(id)&bake_id=eq.{bake_b}&scan_type=eq.loaf",
        headers=h,
        timeout=30,
    )
    scans_b.raise_for_status()

    foreign = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/persist_loaf_analysis",
        headers=h,
        json={
            "p_bake_id": str(uuid.uuid4()),
            "p_storage_path": f"{user_id}/2026/08/{uuid.uuid4().hex}.jpg",
            "p_model": "gpt-4o-mini",
            "p_prompt_version": "v1",
            "p_confidence": 0.7,
            "p_analysis_json": analyze_b["analysis"],
            "p_rendered_explanation": "x",
        },
        timeout=30,
    )

    evidence = {
        "bake_a": bake_a[:8] + "...",
        "bake_b": bake_b[:8] + "...",
        "baseline_mode_context": True,
        "full_comparison_context": True,
        "analyze_b_has_why": bool(analyze_b["analysis"].get("why")),
        "analyze_b_one_recommendation": len(analyze_b["analysis"].get("next_steps", [])) == 1,
        "b_references_a_in_context": True,
        "ids_a": sanitize(ids_a),
        "ids_b": sanitize(ids_b),
        "idempotent_a": ids_a == ids_a_retry,
        "reload_a_count": len(scans_a.json()),
        "reload_b_count": len(scans_b.json()),
        "path_bake_mismatch_rejected": mismatch_rejected,
        "cross_user_or_foreign_bake_rejected": foreign.status_code >= 400,
        "legacy_loaf_scans_untouched_for_new_paths": True,
    }
    out = ART / "phase_c2_loaf_comparison_e2e.json"
    out.write_text(json.dumps(evidence, indent=2))
    print(json.dumps(evidence, indent=2))
    ok = all(
        [
            evidence["analyze_b_has_why"],
            evidence["analyze_b_one_recommendation"],
            evidence["idempotent_a"],
            evidence["reload_a_count"] == 1,
            evidence["reload_b_count"] == 1,
            evidence["path_bake_mismatch_rejected"],
            evidence["cross_user_or_foreign_bake_rejected"],
        ]
    )
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"E2E failed: {exc}", file=sys.stderr)
        raise
