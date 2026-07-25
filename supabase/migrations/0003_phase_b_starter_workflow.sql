-- UP

create table public.starters (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    hydration_preference numeric nullable,
    created_at timestamptz not null default now(),
    active boolean not null default true
);

create index starters_user_active_idx
on public.starters (user_id, active);

create table public.feeding_logs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    starter_id uuid not null references public.starters(id) on delete cascade,
    logged_at timestamptz not null default now(),
    room_temp_c numeric(4,1) not null,
    flour_g integer nullable,
    water_g integer nullable,
    starter_g integer nullable,
    notes text nullable
);

create index feeding_logs_starter_logged_idx
on public.feeding_logs (starter_id, logged_at desc);

create index feeding_logs_user_logged_idx
on public.feeding_logs (user_id, logged_at desc);

create table public.scans (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    starter_id uuid nullable references public.starters(id) on delete cascade,
    bake_id uuid nullable,
    scan_type text not null check (scan_type in ('starter', 'loaf')),
    storage_path text not null,
    created_at timestamptz not null default now(),
    status text not null check (status in ('uploaded', 'analyzed', 'failed')),
    quality_score numeric(3,2) nullable,
    quality_issue text nullable
);

create index scans_user_created_idx
on public.scans (user_id, created_at desc);

create index scans_starter_created_idx
on public.scans (starter_id, created_at desc);

create table public.ai_analyses (
    id uuid primary key default gen_random_uuid(),
    scan_id uuid not null unique references public.scans(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    model text not null,
    prompt_version text not null,
    confidence numeric(3,2) not null,
    analysis_json jsonb not null,
    rendered_explanation text not null,
    created_at timestamptz not null default now()
);

create index ai_analyses_user_created_idx
on public.ai_analyses (user_id, created_at desc);

create table public.starter_states (
    starter_id uuid primary key references public.starters(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    state_label text not null,
    updated_from_scan_id uuid not null references public.scans(id),
    updated_at timestamptz not null default now()
);

create index starter_states_user_updated_idx
on public.starter_states (user_id, updated_at desc);

create table public.recommendations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    scan_id uuid not null references public.scans(id) on delete cascade,
    recommendation text not null,
    due_at timestamptz nullable,
    completed_at timestamptz nullable,
    outcome text not null default 'unknown'
        check (outcome in ('followed', 'helpful', 'not_helpful', 'skipped', 'unknown')),
    created_at timestamptz not null default now()
);

create index recommendations_user_created_idx
on public.recommendations (user_id, created_at desc);

create index recommendations_scan_idx
on public.recommendations (scan_id);

create index recommendations_due_idx
on public.recommendations (due_at);

alter table public.starters enable row level security;
alter table public.feeding_logs enable row level security;
alter table public.scans enable row level security;
alter table public.ai_analyses enable row level security;
alter table public.starter_states enable row level security;
alter table public.recommendations enable row level security;

create policy starters_owner_all
on public.starters
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy feeding_logs_owner_all
on public.feeding_logs
for all
using (
    auth.uid() = user_id
    and exists (
        select 1
        from public.starters s
        where s.id = starter_id
          and s.user_id = auth.uid()
    )
)
with check (
    auth.uid() = user_id
    and exists (
        select 1
        from public.starters s
        where s.id = starter_id
          and s.user_id = auth.uid()
    )
);

create policy scans_owner_all
on public.scans
for all
using (
    auth.uid() = user_id
    and (
        starter_id is null
        or exists (
            select 1
            from public.starters s
            where s.id = starter_id
              and s.user_id = auth.uid()
        )
    )
)
with check (
    auth.uid() = user_id
    and (
        starter_id is null
        or exists (
            select 1
            from public.starters s
            where s.id = starter_id
              and s.user_id = auth.uid()
        )
    )
);

create policy ai_analyses_owner_all
on public.ai_analyses
for all
using (
    auth.uid() = user_id
    and exists (
        select 1
        from public.scans sc
        where sc.id = scan_id
          and sc.user_id = auth.uid()
    )
)
with check (
    auth.uid() = user_id
    and exists (
        select 1
        from public.scans sc
        where sc.id = scan_id
          and sc.user_id = auth.uid()
    )
);

create policy starter_states_owner_all
on public.starter_states
for all
using (
    auth.uid() = user_id
    and exists (
        select 1
        from public.starters s
        where s.id = starter_id
          and s.user_id = auth.uid()
    )
)
with check (
    auth.uid() = user_id
    and exists (
        select 1
        from public.starters s
        where s.id = starter_id
          and s.user_id = auth.uid()
    )
);

create policy recommendations_owner_all
on public.recommendations
for all
using (
    auth.uid() = user_id
    and exists (
        select 1
        from public.scans sc
        where sc.id = scan_id
          and sc.user_id = auth.uid()
    )
)
with check (
    auth.uid() = user_id
    and exists (
        select 1
        from public.scans sc
        where sc.id = scan_id
          and sc.user_id = auth.uid()
    )
);

insert into storage.buckets (id, name, public)
values ('starter-images', 'starter-images', false)
on conflict (id) do nothing;

create policy starter_images_select_own
on storage.objects
for select
to authenticated
using (
    bucket_id = 'starter-images'
    and split_part(name, '/', 1) = auth.uid()::text
);

create policy starter_images_insert_own
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'starter-images'
    and split_part(name, '/', 1) = auth.uid()::text
);

create policy starter_images_delete_own
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'starter-images'
    and split_part(name, '/', 1) = auth.uid()::text
);

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

grant execute on function public.persist_starter_analysis(
    uuid, text, numeric, text, text, text, numeric, jsonb, text, text, text, integer
) to authenticated;

-- DOWN
drop function if exists public.persist_starter_analysis(
    uuid, text, numeric, text, text, text, numeric, jsonb, text, text, text, integer
);

drop policy if exists starter_images_delete_own on storage.objects;
drop policy if exists starter_images_insert_own on storage.objects;
drop policy if exists starter_images_select_own on storage.objects;

drop policy if exists recommendations_owner_all on public.recommendations;
drop policy if exists starter_states_owner_all on public.starter_states;
drop policy if exists ai_analyses_owner_all on public.ai_analyses;
drop policy if exists scans_owner_all on public.scans;
drop policy if exists feeding_logs_owner_all on public.feeding_logs;
drop policy if exists starters_owner_all on public.starters;

drop table if exists public.recommendations;
drop table if exists public.starter_states;
drop table if exists public.ai_analyses;
drop table if exists public.scans;
drop table if exists public.feeding_logs;
drop table if exists public.starters;
