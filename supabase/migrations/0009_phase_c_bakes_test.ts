import { assertEquals, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("phase C bakes migration creates owner RLS and scans.bake_id FK", async () => {
  const sql = await Deno.readTextFile("supabase/migrations/0009_phase_c_bakes.sql");

  assertMatch(sql, /create table if not exists public\.bakes \(/);
  assertMatch(sql, /starter_id uuid not null references public\.starters\(id\)/);
  assertMatch(sql, /result_rating smallint not null/);
  assertMatch(sql, /fermentation_temperature_source text null/);
  assertMatch(sql, /check \(\s*fermentation_temperature_source is null\s+or fermentation_temperature_source in \('room', 'dough'\)\s*\)/);
  assertMatch(sql, /create index if not exists bakes_user_baked_at_idx/);
  assertMatch(sql, /create policy bakes_owner_all/);
  assertMatch(sql, /from public\.starters s\s+where s\.id = starter_id\s+and s\.user_id = auth\.uid\(\)/);

  assertMatch(sql, /constraint scans_bake_id_fkey/);
  assertMatch(sql, /references public\.bakes\(id\)/);
  assertMatch(sql, /on delete set null/);
  assertMatch(sql, /from public\.bakes b\s+where b\.id = bake_id\s+and b\.user_id = auth\.uid\(\)/);

  assertMatch(sql, /-- DOWN/);
  assertMatch(sql, /drop table if exists public\.bakes/);

  // Guard against accidental duplicate loaf scan table.
  assertEquals(sql.includes("create table if not exists public.loaf_scans"), false);
  assertEquals(sql.includes("create table public.loaf_scans"), false);
});
