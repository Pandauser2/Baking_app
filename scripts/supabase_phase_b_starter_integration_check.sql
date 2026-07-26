begin;

do $$
declare
    v_owner uuid;
    v_other_claim uuid := gen_random_uuid();
    v_active_a uuid;
    v_active_b uuid;
    v_active_count integer;
    v_before_active_id uuid;
    v_after_active_id uuid;
begin
    select id into v_owner
    from auth.users
    order by created_at asc
    limit 1;

    if v_owner is null then
        raise exception 'No auth users found for integration check';
    end if;

    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);

    -- Active starter creation through RPC.
    select id into v_active_a
    from public.create_starter_profile('integration-active-a', 100, true)
    limit 1;

    if v_active_a is null then
        raise exception 'create_starter_profile did not return inserted starter';
    end if;

    select count(*) into v_active_count
    from public.starters
    where user_id = v_owner and active = true;

    if v_active_count <> 1 then
        raise exception 'Expected exactly one active starter after first active creation, got %', v_active_count;
    end if;

    -- Inactive creation must not alter current active starter.
    perform public.create_starter_profile('integration-inactive', 100, false);

    select id into v_after_active_id
    from public.starters
    where user_id = v_owner and active = true
    limit 1;

    if v_after_active_id is distinct from v_active_a then
        raise exception 'Inactive creation changed active starter unexpectedly';
    end if;

    -- Active creation should keep exactly one active starter.
    select id into v_active_b
    from public.create_starter_profile('integration-active-b', 100, true)
    limit 1;

    select count(*) into v_active_count
    from public.starters
    where user_id = v_owner and active = true;

    if v_active_count <> 1 then
        raise exception 'Expected exactly one active starter after second active creation, got %', v_active_count;
    end if;

    select id into v_after_active_id
    from public.starters
    where user_id = v_owner and active = true
    limit 1;

    if v_after_active_id is distinct from v_active_b then
        raise exception 'Active creation did not switch active starter to latest';
    end if;

    -- Cross-user activation must fail.
    begin
        perform set_config('request.jwt.claim.sub', v_other_claim::text, true);
        perform public.set_active_starter(v_active_b);
        raise exception 'Expected cross-user set_active_starter to fail';
    exception when others then
        if sqlstate <> 'P0001' and sqlstate <> '42501' and position('not found for user' in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    -- Failed active creation must roll back deactivation.
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    select id into v_before_active_id
    from public.starters
    where user_id = v_owner and active = true
    limit 1;

    begin
        perform public.create_starter_profile(null, 100, true);
        raise exception 'Expected null-name creation failure';
    exception when others then
        if sqlstate <> '23502' then
            raise;
        end if;
    end;

    select id into v_after_active_id
    from public.starters
    where user_id = v_owner and active = true
    limit 1;

    if v_after_active_id is distinct from v_before_active_id then
        raise exception 'Failed creation changed active starter; expected transaction rollback';
    end if;

    -- set_active_starter should end with exactly one active starter.
    perform public.set_active_starter(v_active_a);

    select count(*) into v_active_count
    from public.starters
    where user_id = v_owner and active = true;

    if v_active_count <> 1 then
        raise exception 'Expected exactly one active starter after switching, got %', v_active_count;
    end if;
end
$$;

rollback;
