-- UP

create or replace function public.create_starter_profile(
    p_name text,
    p_hydration_preference numeric,
    p_active boolean
)
returns setof public.starters
language plpgsql
security invoker
as $$
declare
    v_user_id uuid;
    v_inserted public.starters%rowtype;
begin
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;

    if coalesce(p_active, false) then
        update public.starters
        set active = false
        where user_id = v_user_id
          and active = true;
    end if;

    insert into public.starters (
        user_id,
        name,
        hydration_preference,
        active
    )
    values (
        v_user_id,
        p_name,
        p_hydration_preference,
        coalesce(p_active, false)
    )
    returning * into v_inserted;

    return next v_inserted;
end;
$$;

grant execute on function public.create_starter_profile(
    text, numeric, boolean
) to authenticated;

create or replace function public.set_active_starter(
    p_starter_id uuid
)
returns setof public.starters
language plpgsql
security invoker
as $$
declare
    v_user_id uuid;
    v_updated public.starters%rowtype;
begin
    v_user_id := auth.uid();
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;

    if not exists (
        select 1
        from public.starters
        where id = p_starter_id
          and user_id = v_user_id
    ) then
        raise exception 'Starter not found for user';
    end if;

    update public.starters
    set active = false
    where user_id = v_user_id
      and active = true;

    update public.starters
    set active = true
    where id = p_starter_id
      and user_id = v_user_id
    returning * into v_updated;

    return next v_updated;
end;
$$;

grant execute on function public.set_active_starter(
    uuid
) to authenticated;

-- NOTE:
-- This migration intentionally omits executable DOWN statements because
-- Supabase CLI `db push` runs the full SQL file sequentially.
