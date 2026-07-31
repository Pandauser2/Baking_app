begin;

do $$
declare
    v_owner uuid;
    v_starter_id uuid;
    v_scan_id uuid;
    v_analysis_id uuid;
    v_recommendation_id uuid;
    v_path text;
    v_scan_count_before integer;
    v_analysis_count_before integer;
    v_recommendation_count_before integer;
    v_state_count_before integer;
    v_scan_count_after integer;
    v_analysis_count_after integer;
    v_recommendation_count_after integer;
    v_state_count_after integer;
begin
    select id into v_owner
    from auth.users
    order by created_at asc
    limit 1;

    if v_owner is null then
        raise exception 'No auth users found for persist integration check';
    end if;

    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);

    select id into v_starter_id
    from public.create_starter_profile('persist-check-starter', 100, true)
    limit 1;

    if v_starter_id is null then
        raise exception 'create_starter_profile did not return starter';
    end if;

    v_path := v_owner::text || '/' || v_starter_id::text || '/2026/07/' || gen_random_uuid()::text || '.jpg';

    select scan_id, analysis_id, recommendation_id
    into v_scan_id, v_analysis_id, v_recommendation_id
    from public.persist_starter_analysis(
        v_starter_id,
        v_path,
        0.95,
        null,
        'gpt-4o-mini',
        'v1',
        0.82,
        '{"scan_type":"starter","observations":["Visible bubbles"],"diagnosis":["active"],"confidence":0.82,"next_steps":[{"instruction":"Feed now","time_window_hours":12}],"human_explanation":"Starter looks active.","risk_flags":[],"compare_to_previous":{"changed":true,"explanation":"More bubbles."},"starter_state":"active"}'::jsonb,
        'Starter looks active.',
        'active',
        'Feed now',
        12
    );

    if v_scan_id is null or v_analysis_id is null or v_recommendation_id is null then
        raise exception 'persist_starter_analysis did not return all ids';
    end if;

    select count(*) into v_scan_count_before
    from public.scans
    where id = v_scan_id and user_id = v_owner and starter_id = v_starter_id;

    select count(*) into v_analysis_count_before
    from public.ai_analyses
    where id = v_analysis_id and user_id = v_owner and scan_id = v_scan_id;

    select count(*) into v_recommendation_count_before
    from public.recommendations
    where id = v_recommendation_id and user_id = v_owner and scan_id = v_scan_id;

    select count(*) into v_state_count_before
    from public.starter_states
    where starter_id = v_starter_id and user_id = v_owner and updated_from_scan_id = v_scan_id;

    if v_scan_count_before <> 1 or v_analysis_count_before <> 1 or v_recommendation_count_before <> 1 or v_state_count_before <> 1 then
        raise exception 'Expected successful persistence writes to all tables';
    end if;

    -- Failed persistence should roll back all writes from that invocation.
    begin
        perform public.persist_starter_analysis(
            v_starter_id,
            v_owner::text || '/' || v_starter_id::text || '/2026/07/' || gen_random_uuid()::text || '.jpg',
            0.95,
            null,
            'gpt-4o-mini',
            'v1',
            1.75, -- invalid confidence to force validation failure
            '{"scan_type":"starter","observations":["Visible bubbles"],"diagnosis":["active"],"confidence":0.82,"next_steps":[{"instruction":"Feed now","time_window_hours":12}],"human_explanation":"Starter looks active.","risk_flags":[],"compare_to_previous":{"changed":true,"explanation":"More bubbles."},"starter_state":"active"}'::jsonb,
            'Starter looks active.',
            'active',
            'Feed now',
            12
        );
        raise exception 'Expected persist_starter_analysis validation failure';
    exception when others then
        if position('confidence must be between 0 and 1' in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    select count(*) into v_scan_count_after
    from public.scans
    where user_id = v_owner and starter_id = v_starter_id;

    select count(*) into v_analysis_count_after
    from public.ai_analyses
    where user_id = v_owner and scan_id = v_scan_id;

    select count(*) into v_recommendation_count_after
    from public.recommendations
    where user_id = v_owner and scan_id = v_scan_id;

    select count(*) into v_state_count_after
    from public.starter_states
    where starter_id = v_starter_id and user_id = v_owner;

    if v_scan_count_after <> 1 then
        raise exception 'Failed persist created extra scans; expected rollback';
    end if;
    if v_analysis_count_after <> 1 or v_recommendation_count_after <> 1 then
        raise exception 'Failed persist created extra analysis/recommendation rows; expected rollback';
    end if;
    if v_state_count_after < 1 then
        raise exception 'Starter state unexpectedly missing after rollback check';
    end if;
end
$$;

rollback;
