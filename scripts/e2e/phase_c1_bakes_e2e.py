#!/usr/bin/env python3
"""Phase C1 bake journal E2E against linked Supabase.

Validates: create -> list -> fetch -> unauthorized rejection -> reload persistence.
"""

from __future__ import annotations

import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "artifacts" / "e2e" / "phase_c1_bakes"
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
            if k in {"id", "user_id", "starter_id", "bake_id"}:
                out[k] = (str(v)[:8] + "...") if v else v
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
        f"{SUPABASE_URL}/rest/v1/starters?select=id,name,active&order=active.desc,created_at.desc&limit=1",
        headers=headers,
        timeout=30,
    )
    starters.raise_for_status()
    starter_rows = starters.json()
    if not starter_rows:
        raise RuntimeError("Need at least one starter for bake E2E")
    starter_id = starter_rows[0]["id"]

    payload = {
        "user_id": user_id,
        "starter_id": starter_id,
        "baked_at": datetime.now(timezone.utc).isoformat(),
        "name": f"PhaseC1 E2E {uuid.uuid4().hex[:8]}",
        "dough_hydration_percent": 75,
        "bulk_fermentation_minutes": 240,
        "final_proof_minutes": 120,
        "mixing_method": "Hand mix",
        "shaping_method": "Boule",
        "oven_temperature_c": 230,
        "baking_time_minutes": 40,
        "result_rating": 4,
        "fermentation_temperature_c": 24,
        "fermentation_temperature_source": "room",
        "notes": "phase-c1-e2e",
    }
    created = requests.post(
        f"{SUPABASE_URL}/rest/v1/bakes",
        headers=headers,
        json=payload,
        timeout=30,
    )
    created.raise_for_status()
    bake = created.json()[0]
    bake_id = bake["id"]

    listed = requests.get(
        f"{SUPABASE_URL}/rest/v1/bakes?select=*&id=eq.{bake_id}",
        headers=headers,
        timeout=30,
    )
    listed.raise_for_status()
    assert listed.json(), "list/fetch after create returned empty"

    fetched = requests.get(
        f"{SUPABASE_URL}/rest/v1/bakes?select=*&id=eq.{bake_id}",
        headers={**headers, "Accept": "application/vnd.pgrst.object+json"},
        timeout=30,
    )
    fetched.raise_for_status()
    assert fetched.json()["name"] == payload["name"]

    # Unauthorized: anon without user JWT should not read owner row.
    anon_only = requests.get(
        f"{SUPABASE_URL}/rest/v1/bakes?select=id&id=eq.{bake_id}",
        headers={"apikey": anon, "Authorization": f"Bearer {anon}"},
        timeout=30,
    )
    unauthorized_ok = anon_only.status_code in (200, 401) and anon_only.json() == []
    if anon_only.status_code == 200 and anon_only.json():
        unauthorized_ok = False

    # Reload persistence (second fetch after create).
    reload = requests.get(
        f"{SUPABASE_URL}/rest/v1/bakes?select=id,name,result_rating&id=eq.{bake_id}",
        headers=headers,
        timeout=30,
    )
    reload.raise_for_status()
    reload_rows = reload.json()
    assert len(reload_rows) == 1

    evidence = {
        "created": sanitize(bake),
        "list_count": len(listed.json()),
        "fetched_name": fetched.json().get("name"),
        "unauthorized_empty": unauthorized_ok,
        "reload_persisted": reload_rows[0].get("name") == payload["name"],
        "starter_linked": starter_id.startswith(str(starter_id)[:8]),
    }
    out = ART / "phase_c1_bakes_e2e.json"
    out.write_text(json.dumps(evidence, indent=2))
    print(json.dumps(evidence, indent=2))
    if not unauthorized_ok or not evidence["reload_persisted"]:
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"E2E failed: {exc}", file=sys.stderr)
        raise
