import { assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("atomic starter RPC migration includes create and set-active functions", async () => {
  const sql = await Deno.readTextFile(
    "supabase/migrations/0005_phase_b_starter_atomic_active_rpcs.sql",
  );

  assertMatch(sql, /create or replace function public\.create_starter_profile\(/);
  assertMatch(sql, /v_user_id := auth\.uid\(\)/);
  assertMatch(sql, /update public\.starters\s+set active = false[\s\S]*where user_id = v_user_id/);
  assertMatch(sql, /insert into public\.starters[\s\S]*returning \* into v_inserted/);

  assertMatch(sql, /create or replace function public\.set_active_starter\(/);
  assertMatch(sql, /where id = p_starter_id\s+and user_id = v_user_id/);
  assertMatch(sql, /update public\.starters\s+set active = false[\s\S]*where user_id = v_user_id/);
  assertMatch(sql, /update public\.starters\s+set active = true[\s\S]*returning \* into v_updated/);
});
