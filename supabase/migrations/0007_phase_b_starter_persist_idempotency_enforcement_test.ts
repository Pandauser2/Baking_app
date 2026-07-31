import { assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("persist idempotency enforcement migration keeps one scan per user+path", async () => {
  const sql = await Deno.readTextFile("supabase/migrations/0007_phase_b_starter_persist_idempotency_enforcement.sql");

  assertMatch(sql, /partition by user_id, scan_type, storage_path/);
  assertMatch(sql, /update public\.starter_states/);
  assertMatch(sql, /delete from public\.scans s/);
  assertMatch(sql, /create unique index if not exists scans_starter_user_path_unique/);
  assertMatch(sql, /where scan_type = 'starter'/);
});
