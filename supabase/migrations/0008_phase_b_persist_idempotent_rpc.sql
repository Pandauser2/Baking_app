-- UP

-- Re-point starter_states away from duplicate scans, then remove duplicates.
with ranked_scans as (
    select
        id,
        first_value(id) over (
            partition by user_id, scan_type, storage_path
            order by created_at asc, id asc
        ) as keeper_id,
        row_number() over (
            partition by user_id, scan_type, storage_path
            order by created_at asc, id asc
        ) as row_num
    from public.scans
    where scan_type = 'starter'
),
duplicate_scans as (
    select id as duplicate_id, keeper_id
    from ranked_scans
    where row_num > 1
)
update public.starter_states st
set updated_from_scan_id = d.keeper_id
from duplicate_scans d
where st.updated_from_scan_id = d.duplicate_id;

with ranked_scans as (
    select
        id,
        row_number() over (
            partition by user_id, scan_type, storage_path
            order by created_at asc, id asc
        ) as row_num
    from public.scans
    where scan_type = 'starter'
)
delete from public.scans s
using ranked_scans r
where s.id = r.id
  and r.row_num > 1;

create unique index if not exists scans_starter_user_path_unique
on public.scans (user_id, scan_type, storage_path)
where scan_type = 'starter';

create or replace function public.persist_starter_analysis(
    p_starter_id uuid,
    p_storage_path text,
    p_quality_score numeric,
    p_quality_issue text,
    p_model text,
    p_prompt_version text,
    p_confidence numeric,
    p_analysis_json jsonb,
    p_rendered_explanation text,
    p_state_label text,
    p_recommendation text,
    p_due_hours integer
)
returns table (
    scan_id uuid,
    analysis_id uuid,
    recommendation_id uuid
)
language plpgsql
security invoker
as $$
declare
    v_user_id uuid;
    v_scan_id uuid;
    v_analysis_id uuid;
    v_recommendation_id uuid;
    v_expected_prefix text;
begin
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;

    if not exists (
        select 1
        from public.starters s
        where s.id = p_starter_id
          and s.user_id = v_user_id
    ) then
        raise exception 'Starter not found for user';
    end if;

    v_expected_prefix := v_user_id::text || '/' || p_starter_id::text || '/';
    if p_storage_path is null or left(p_storage_path, length(v_expected_prefix)) <> v_expected_prefix then
        raise exception 'Invalid storage path for starter';
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
    if p_rendered_explanation is null or btrim(p_rendered_explanation) = '' then
        raise exception 'Rendered explanation is required';
    end if;
    if p_state_label is null or btrim(p_state_label) = '' then
        raise exception 'State label is required';
    end if;
    if p_recommendation is null or btrim(p_recommendation) = '' then
        raise exception 'Recommendation is required';
    end if;

    -- Idempotent return when this storage path was already persisted.
    select sc.id, aa.id, r.id
    into v_scan_id, v_analysis_id, v_recommendation_id
    from public.scans sc
    join public.ai_analyses aa on aa.scan_id = sc.id
    join public.recommendations r on r.scan_id = sc.id
    where sc.user_id = v_user_id
      and sc.starter_id = p_starter_id
      and sc.scan_type = 'starter'
      and sc.storage_path = p_storage_path
    order by sc.created_at asc
    limit 1;

    if v_scan_id is not null and v_analysis_id is not null and v_recommendation_id is not null then
        return query
        select v_scan_id, v_analysis_id, v_recommendation_id;
        return;
    end if;

    insert into public.scans (
        user_id, starter_id, scan_type, storage_path, status, quality_score, quality_issue
    )
    values (
        v_user_id, p_starter_id, 'starter', p_storage_path, 'analyzed', p_quality_score, p_quality_issue
    )
    returning id into v_scan_id;

    insert into public.ai_analyses (
        scan_id, user_id, model, prompt_version, confidence, analysis_json, rendered_explanation
    )
    values (
        v_scan_id, v_user_id, p_model, p_prompt_version, p_confidence, p_analysis_json, p_rendered_explanation
    )
    returning id into v_analysis_id;

    insert into public.recommendations (
        user_id, scan_id, recommendation, due_at
    )
    values (
        v_user_id,
        v_scan_id,
        p_recommendation,
        now() + make_interval(hours => greatest(coalesce(p_due_hours, 12), 1))
    )
    returning id into v_recommendation_id;

    insert into public.starter_states (
        starter_id, user_id, state_label, updated_from_scan_id, updated_at
    )
    values (
        p_starter_id, v_user_id, p_state_label, v_scan_id, now()
    )
    on conflict (starter_id) do update
    set user_id = excluded.user_id,
        state_label = excluded.state_label,
        updated_from_scan_id = excluded.updated_from_scan_id,
        updated_at = excluded.updated_at;

    return query
    select v_scan_id, v_analysis_id, v_recommendation_id;
end;
$$;

-- DOWN
-- Keep prior persist_starter_analysis definition and unique index if rolling back.
