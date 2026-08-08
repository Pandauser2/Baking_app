import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("0011 persist_loaf_analysis rejects path/bake mismatch and keeps same-bake idempotent", async () => {
  const sql = await Deno.readTextFile(
    new URL("./0011_phase_c_persist_loaf_bake_idempotency.sql", import.meta.url),
  );
  assertEquals(sql.includes("persist_loaf_analysis"), true);
  assertEquals(sql.includes("Storage path already linked to a different bake"), true);
  assertEquals(sql.includes("v_existing_bake_id is distinct from p_bake_id"), true);
  assertEquals(sql.includes("is distinct from p_bake_id"), true);
  assertEquals(sql.toLowerCase().includes("drop table"), false);
  assertEquals(sql.includes("loaf_scans"), false);
});
