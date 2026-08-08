#!/usr/bin/env python3
"""Phase C2.1 loaf comparison correctness E2E against linked Supabase.

Proves:
  - baseline snapshot persisted (comparison_mode=baseline, previous_bake_id=null)
  - fullComparison previous_bake_id persisted
  - reload returns identical snapshot
  - modifying bake journal after scan does NOT alter historical comparison
  - existing idempotency still passes
"""

from __future__ import annotations

import copy
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

SCORE_THRESHOLD = 5


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
                "bake_id",
                "scan_id",
                "analysis_id",
                "previous_bake_id",
                "previous_starter_id",
            }:
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


def classify_score(delta: int) -> str:
    if delta >= SCORE_THRESHOLD:
        return "improved"
    if delta <= -SCORE_THRESHOLD:
        return "regressed"
    return "unchanged"


def classify_process(delta: float, unchanged_within: float) -> str:
    if abs(delta) <= unchanged_within:
        return "unchanged"
    return "increased" if delta > 0 else "decreased"


def process_snapshot(hydration: float) -> dict:
    return {
        "dough_hydration_percent": hydration,
        "bulk_fermentation_minutes": 240,
        "final_proof_minutes": 120,
        "fermentation_temperature_c": 24,
        "oven_temperature_c": 230,
        "baking_time_minutes": 40,
    }


def build_process_deltas(current: dict, previous: dict) -> list[dict]:
    specs = [
        ("hydration", "dough_hydration_percent", 1.0),
        ("bulk_fermentation", "bulk_fermentation_minutes", 15.0),
        ("final_proof", "final_proof_minutes", 15.0),
        ("fermentation_temperature", "fermentation_temperature_c", 2.0),
        ("oven_temperature", "oven_temperature_c", 2.0),
        ("bake_time", "baking_time_minutes", 15.0),
    ]
    out = []
    for dimension, key, within in specs:
        cur = current.get(key)
        prev = previous.get(key)
        if cur is None or prev is None:
            continue
        delta = float(cur) - float(prev)
        change = classify_process(delta, within)
        assert change in {"increased", "decreased", "unchanged"}
        assert change not in {"improved", "regressed"}
        out.append(
            {
                "dimension": dimension,
                "previous": float(prev),
                "current": float(cur),
                "delta": delta,
                "change": change,
            }
        )
    return out


def build_score_deltas(current: dict, previous: dict) -> list[dict]:
    dims = [
        ("crumb", "crumb_score"),
        ("crust", "crust_score"),
        ("oven_spring", "oven_spring_score"),
        ("overall", "overall_score"),
    ]
    out = []
    for dimension, key in dims:
        cur = int(current[key])
        prev = int(previous[key])
        delta = cur - prev
        out.append(
            {
                "dimension": dimension,
                "previous": prev,
                "current": cur,
                "delta": delta,
                "classification": classify_score(delta),
            }
        )
    return out


def attach_comparison(analysis: dict, comparison: dict) -> dict:
    payload = copy.deepcopy(analysis)
    payload["comparison"] = comparison
    return payload


def persist(h: dict, bake_id: str, path: str, analyze_body: dict, analysis_json: dict) -> dict:
    body = {
        "p_bake_id": bake_id,
        "p_storage_path": path,
        "p_model": analyze_body.get("model") or "gpt-4o-mini",
        "p_prompt_version": analyze_body.get("prompt_version") or "v1",
        "p_confidence": max(0.0, min(1.0, float(analysis_json.get("overall_score", 50)) / 100.0)),
        "p_analysis_json": analysis_json,
        "p_rendered_explanation": analysis_json.get("summary") or "Loaf analysis",
        "p_quality_score": None,
        "p_quality_issue": None,
    }
    resp = requests.post(f"{SUPABASE_URL}/rest/v1/rpc/persist_loaf_analysis", headers=h, json=body, timeout=30)
    if not resp.ok:
        raise RuntimeError(f"persist failed: {resp.status_code} {resp.text}")
    ids = resp.json()
    return ids[0] if isinstance(ids, list) else ids


def fetch_analysis_json(h: dict, analysis_id: str) -> dict:
    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/ai_analyses?select=id,analysis_json&id=eq.{analysis_id}",
        headers=h,
        timeout=30,
    )
    resp.raise_for_status()
    rows = resp.json()
    if not rows:
        raise RuntimeError(f"analysis {analysis_id} missing")
    return rows[0]["analysis_json"]


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
    bake_a = create_bake(h, user_id, starter_id, f"C21 A {uuid.uuid4().hex[:6]}", now - timedelta(days=2), 72)
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
    baseline_comparison = {
        "comparison_mode": "baseline",
        "previous_bake_id": None,
        "previous_starter_id": None,
        "starter_changed": False,
        "score_deltas": [],
        "process_deltas": [],
        "recommendation": (analyze_a["analysis"].get("next_steps") or ["Keep going"])[0],
    }
    analysis_a = attach_comparison(analyze_a["analysis"], baseline_comparison)
    ids_a = persist(h, bake_a, path_a, analyze_a, analysis_a)
    ids_a_retry = persist(h, bake_a, path_a, analyze_a, analysis_a)
    assert ids_a == ids_a_retry

    reloaded_a = fetch_analysis_json(h, ids_a["analysis_id"])
    assert reloaded_a.get("comparison") == baseline_comparison
    assert reloaded_a["comparison"]["comparison_mode"] == "baseline"
    assert reloaded_a["comparison"]["previous_bake_id"] is None

    bake_b = create_bake(h, user_id, starter_id, f"C21 B {uuid.uuid4().hex[:6]}", now - timedelta(days=1), 78)
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
    score_deltas = build_score_deltas(analyze_b["analysis"], prev_scores)
    process_deltas = build_process_deltas(process_snapshot(78), process_snapshot(72))
    # Prove threshold helpers used by client mirror (±4 unchanged, ±5 boundary).
    assert classify_score(4) == "unchanged"
    assert classify_score(-4) == "unchanged"
    assert classify_score(5) == "improved"
    assert classify_score(-5) == "regressed"
    assert all(d["change"] in {"increased", "decreased", "unchanged"} for d in process_deltas)
    assert any(d["dimension"] == "hydration" and d["change"] == "increased" for d in process_deltas)

    full_comparison = {
        "comparison_mode": "fullComparison",
        "previous_bake_id": bake_a,
        "previous_starter_id": starter_id,
        "starter_changed": False,
        "score_deltas": score_deltas,
        "process_deltas": process_deltas,
        "recommendation": (analyze_b["analysis"].get("next_steps") or ["Add steam"])[0],
    }
    analysis_b = attach_comparison(analyze_b["analysis"], full_comparison)
    ids_b = persist(h, bake_b, path_b, analyze_b, analysis_b)

    reloaded_b = fetch_analysis_json(h, ids_b["analysis_id"])
    assert reloaded_b.get("comparison") == full_comparison
    assert reloaded_b["comparison"]["previous_bake_id"] == bake_a
    assert reloaded_b["comparison"]["comparison_mode"] == "fullComparison"

    # Mutate bake journal after scan — historical snapshot must stay identical.
    patch = requests.patch(
        f"{SUPABASE_URL}/rest/v1/bakes?id=eq.{bake_b}",
        headers=h,
        json={"dough_hydration_percent": 95},
        timeout=30,
    )
    patch.raise_for_status()
    reloaded_after_edit = fetch_analysis_json(h, ids_b["analysis_id"])
    assert reloaded_after_edit.get("comparison") == full_comparison
    hyd = next(d for d in reloaded_after_edit["comparison"]["process_deltas"] if d["dimension"] == "hydration")
    assert hyd["current"] == 78
    assert hyd["change"] == "increased"

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
            "p_analysis_json": analysis_a,
            "p_rendered_explanation": "x",
            "p_quality_score": None,
            "p_quality_issue": None,
        },
        timeout=30,
    )
    mismatch_rejected = mismatch.status_code >= 400 and "different bake" in mismatch.text.lower()

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
            "p_analysis_json": analysis_b,
            "p_rendered_explanation": "x",
        },
        timeout=30,
    )

    evidence = {
        "bake_a": bake_a[:8] + "...",
        "bake_b": bake_b[:8] + "...",
        "score_threshold": SCORE_THRESHOLD,
        "plus_minus_4_unchanged": classify_score(4) == "unchanged" and classify_score(-4) == "unchanged",
        "plus_5_improved": classify_score(5) == "improved",
        "minus_5_regressed": classify_score(-5) == "regressed",
        "process_uses_increased_decreased": all(
            d["change"] in {"increased", "decreased", "unchanged"} for d in process_deltas
        ),
        "baseline_snapshot": sanitize(reloaded_a.get("comparison")),
        "full_comparison_previous_bake_id_persisted": reloaded_b["comparison"]["previous_bake_id"] == bake_a,
        "reload_identical_snapshot": reloaded_b.get("comparison") == full_comparison,
        "journal_edit_does_not_alter_snapshot": reloaded_after_edit.get("comparison") == full_comparison,
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
            evidence["plus_minus_4_unchanged"],
            evidence["plus_5_improved"],
            evidence["minus_5_regressed"],
            evidence["process_uses_increased_decreased"],
            evidence["baseline_snapshot"]["comparison_mode"] == "baseline",
            evidence["baseline_snapshot"]["previous_bake_id"] is None,
            evidence["full_comparison_previous_bake_id_persisted"],
            evidence["reload_identical_snapshot"],
            evidence["journal_edit_does_not_alter_snapshot"],
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
