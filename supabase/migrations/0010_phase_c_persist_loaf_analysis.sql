-- UP
-- Phase C1.5: Canonical loaf analysis persistence via scans + ai_analyses.
-- Edge Function analyze-loaf is analysis-only; iOS persists through this RPC.
-- Legacy public.loaf_scans is intentionally retained (no drop / no new writes from Phase C).

-- Idempotency key for loaf scans (mirrors starter unique path index).
create unique index if not exists scans_loaf_user_path_unique
on public.scans (user_id, scan_type, storage_path)
where scan_type = 'loaf';

create or replace function public.persist_loaf_analysis(
    p_bake_id uuid,
    p_storage_path text,
    p_model text,
    p_prompt_version text,
    p_confidence numeric,
    p_analysis_json jsonb,
    p_rendered_explanation text,
    p_quality_score numeric default null,
    p_quality_issue text default null
)
returns table (
    scan_id uuid,
    analysis_id uuid
)
language plpgsql
security invoker
as $$
declare
    v_user_id uuid;
    v_starter_id uuid;
    v_scan_id uuid;
    v_analysis_id uuid;
    v_expected_prefix text;
begin
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;

    select b.starter_id
    into v_starter_id
    from public.bakes b
    where b.id = p_bake_id
      and b.user_id = v_user_id;

    if v_starter_id is null then
        raise exception 'Bake not found for user';
    end if;

    v_expected_prefix := v_user_id::text || '/';
    if p_storage_path is null or left(p_storage_path, length(v_expected_prefix)) <> v_expected_prefix then
        raise exception 'Invalid storage path for user';
    end if;

    if p_confidence is null or p_confidence < 0 or p_confidence > 1 then
        raise exception 'Confidence must be between 0 and 1';
    end if;

    if p_quality_score is not null and (p_quality_score < 0 or p_quality_score > 1) then
        raise exception 'Quality score must be null or between 0 and 1';
    end if;

    if p_model is null or btrim(p_model) = '' then
        raise exception 'Model is required';
    end if;
    if p_prompt_version is null or btrim(p_prompt_version) = '' then
        raise exception 'Prompt version is required';
    end if;
    if p_analysis_json is null then
        raise exception 'Analysis JSON is required';
    end if;
    if p_rendered_explanation is null or btrim(p_rendered_explanation) = '' then
        raise exception 'Rendered explanation is required';
    end if;

    -- Idempotent return when this loaf storage path was already persisted.
    select sc.id, aa.id
    into v_scan_id, v_analysis_id
    from public.scans sc
    join public.ai_analyses aa on aa.scan_id = sc.id
    where sc.user_id = v_user_id
      and sc.scan_type = 'loaf'
      and sc.storage_path = p_storage_path
    order by sc.created_at asc
    limit 1;

    if v_scan_id is not null and v_analysis_id is not null then
        return query
        select v_scan_id, v_analysis_id;
        return;
    end if;

    insert into public.scans (
        user_id,
        starter_id,
        bake_id,
        scan_type,
        storage_path,
        status,
        quality_score,
        quality_issue
    )
    values (
        v_user_id,
        v_starter_id,
        p_bake_id,
        'loaf',
        p_storage_path,
        'analyzed',
        p_quality_score,
        p_quality_issue
    )
    returning id into v_scan_id;

    insert into public.ai_analyses (
        scan_id,
        user_id,
        model,
        prompt_version,
        confidence,
        analysis_json,
        rendered_explanation
    )
    values (
        v_scan_id,
        v_user_id,
        p_model,
        p_prompt_version,
        p_confidence,
        p_analysis_json,
        p_rendered_explanation
    )
    returning id into v_analysis_id;

    return query
    select v_scan_id, v_analysis_id;
end;
$$;

grant execute on function public.persist_loaf_analysis(
    uuid, text, text, text, numeric, jsonb, text, numeric, text
) to authenticated;

-- DOWN
-- drop function if exists public.persist_loaf_analysis(uuid, text, text, text, numeric, jsonb, text, numeric, text);
-- drop index if exists scans_loaf_user_path_unique;
-- Legacy loaf_scans table is intentionally not dropped.
