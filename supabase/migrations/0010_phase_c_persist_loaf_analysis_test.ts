import { assertEquals, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("persist_loaf_analysis migration enforces bake ownership and idempotency", async () => {
  const sql = await Deno.readTextFile(
    "supabase/migrations/0010_phase_c_persist_loaf_analysis.sql",
  );

  assertMatch(sql, /create unique index if not exists scans_loaf_user_path_unique/);
  assertMatch(sql, /create or replace function public\.persist_loaf_analysis\(/);
  assertMatch(sql, /from public\.bakes b\s+where b\.id = p_bake_id\s+and b\.user_id = v_user_id/);
  assertMatch(sql, /raise exception 'Bake not found for user'/);
  assertMatch(sql, /sc\.scan_type = 'loaf'/);
  assertMatch(sql, /sc\.storage_path = p_storage_path/);
  assertMatch(sql, /insert into public\.scans \(/);
  assertMatch(sql, /bake_id,/);
  assertMatch(sql, /insert into public\.ai_analyses \(/);
  assertMatch(sql, /grant execute on function public\.persist_loaf_analysis/);

  // Must not drop or truncate legacy loaf_scans.
  assertEquals(sql.toLowerCase().includes("drop table"), false);
  assertEquals(sql.toLowerCase().includes("truncate"), false);
  assertEquals(sql.includes("loaf_scans"), true); // mentioned as legacy only
});
