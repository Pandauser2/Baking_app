import { assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("persist idempotent RPC migration enforces path uniqueness and returns existing ids", async () => {
  const sql = await Deno.readTextFile("supabase/migrations/0008_phase_b_persist_idempotent_rpc.sql");

  assertMatch(sql, /create unique index if not exists scans_starter_user_path_unique/);
  assertMatch(sql, /create or replace function public\.persist_starter_analysis/);
  assertMatch(sql, /sc\.storage_path = p_storage_path/);
  assertMatch(sql, /return query\s+select v_scan_id, v_analysis_id, v_recommendation_id;/);
});
