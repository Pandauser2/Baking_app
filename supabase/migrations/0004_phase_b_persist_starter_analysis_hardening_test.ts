import { assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test("persist_starter_analysis hardening checks are present", async () => {
  const sql = await Deno.readTextFile("supabase/migrations/0004_phase_b_persist_starter_analysis_hardening.sql");

  assertMatch(sql, /v_expected_prefix := v_user_id::text \|\| '\/' \|\| p_starter_id::text \|\| '\/'/);
  assertMatch(sql, /left\(p_storage_path, length\(v_expected_prefix\)\) <> v_expected_prefix/);
  assertMatch(sql, /p_confidence is null or p_confidence < 0 or p_confidence > 1/);
  assertMatch(sql, /p_quality_score is not null and \(p_quality_score < 0 or p_quality_score > 1\)/);
  assertMatch(sql, /p_model is null or btrim\(p_model\) = ''/);
  assertMatch(sql, /p_prompt_version is null or btrim\(p_prompt_version\) = ''/);
  assertMatch(sql, /p_rendered_explanation is null or btrim\(p_rendered_explanation\) = ''/);
  assertMatch(sql, /p_state_label is null or btrim\(p_state_label\) = ''/);
  assertMatch(sql, /p_recommendation is null or btrim\(p_recommendation\) = ''/);
});

