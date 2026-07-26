begin;

do $$
declare
    v_owner uuid;
    v_other_claim uuid := gen_random_uuid();
    v_starter_id uuid;
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

    insert into public.starters (user_id, name, hydration_preference, active)
    values (v_owner, 'integration-owner-starter', 100, true)
    returning id into v_starter_id;

    insert into public.feeding_logs (user_id, starter_id, logged_at, room_temp_c, flour_g, water_g, starter_g, notes)
    values (v_owner, v_starter_id, now(), 24.0, 50, 50, 25, 'integration owner insert');

    begin
        perform set_config('request.jwt.claim.sub', v_other_claim::text, true);
        insert into public.starters (user_id, name, hydration_preference, active)
        values (v_owner, 'integration-cross-user-starter', 100, true);
        raise exception 'Expected RLS rejection for cross-user starter insert';
    exception when others then
        if sqlstate <> '42501' and position('row-level security' in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;

    begin
        perform set_config('request.jwt.claim.sub', v_other_claim::text, true);
        insert into public.feeding_logs (user_id, starter_id, logged_at, room_temp_c)
        values (v_owner, v_starter_id, now(), 24.0);
        raise exception 'Expected RLS rejection for cross-user feeding insert';
    exception when others then
        if sqlstate <> '42501' and position('row-level security' in lower(sqlerrm)) = 0 then
            raise;
        end if;
    end;
end
$$;

rollback;
