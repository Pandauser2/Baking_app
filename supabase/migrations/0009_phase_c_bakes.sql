-- UP
-- Phase C1: Bake journal foundation.
-- Canonical loaf/starter scan table remains public.scans (do not duplicate).
-- public.loaf_scans stays the Phase B score-card table used by analyze-loaf;
-- bake linkage for future loaf coaching uses scans.bake_id -> bakes.id.

create table if not exists public.bakes (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    starter_id uuid not null references public.starters(id) on delete restrict,
    baked_at timestamptz not null,
    name text not null,
    dough_hydration_percent numeric(5,2) not null
        check (dough_hydration_percent >= 40 and dough_hydration_percent <= 120),
    bulk_fermentation_minutes integer not null
        check (bulk_fermentation_minutes >= 0),
    final_proof_minutes integer not null
        check (final_proof_minutes >= 0),
    mixing_method text not null
        check (char_length(trim(mixing_method)) > 0),
    shaping_method text not null
        check (char_length(trim(shaping_method)) > 0),
    oven_temperature_c numeric(5,1) not null
        check (oven_temperature_c >= 100 and oven_temperature_c <= 350),
    baking_time_minutes integer not null
        check (baking_time_minutes > 0),
    result_rating smallint not null
        check (result_rating between 1 and 5),
    fermentation_temperature_c numeric(4,1) null
        check (
            fermentation_temperature_c is null
            or (fermentation_temperature_c >= 0 and fermentation_temperature_c <= 50)
        ),
    fermentation_temperature_source text null
        check (
            fermentation_temperature_source is null
            or fermentation_temperature_source in ('room', 'dough')
        ),
    retardation_minutes integer null
        check (retardation_minutes is null or retardation_minutes >= 0),
    number_of_folds integer null
        check (number_of_folds is null or number_of_folds >= 0),
    steaming_method text null,
    flour_notes text null,
    notes text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint bakes_name_not_blank check (char_length(trim(name)) > 0),
    constraint bakes_fermentation_temp_source_pair check (
        (fermentation_temperature_c is null and fermentation_temperature_source is null)
        or (fermentation_temperature_c is not null and fermentation_temperature_source is not null)
    )
);

create index if not exists bakes_user_baked_at_idx
    on public.bakes (user_id, baked_at desc);

create index if not exists bakes_starter_baked_at_idx
    on public.bakes (starter_id, baked_at desc);

alter table public.bakes enable row level security;

drop policy if exists bakes_owner_all on public.bakes;
create policy bakes_owner_all
on public.bakes
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

-- Link canonical scans.bake_id to bakes (column already exists without FK).
do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'scans_bake_id_fkey'
    ) then
        alter table public.scans
            add constraint scans_bake_id_fkey
            foreign key (bake_id)
            references public.bakes(id)
            on delete set null;
    end if;
end $$;

create index if not exists scans_bake_id_idx
    on public.scans (bake_id);

-- Harden scans RLS so bake_id, when set, must belong to the authenticated user.
drop policy if exists scans_owner_all on public.scans;
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
    and (
        bake_id is null
        or exists (
            select 1
            from public.bakes b
            where b.id = bake_id
              and b.user_id = auth.uid()
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
    and (
        bake_id is null
        or exists (
            select 1
            from public.bakes b
            where b.id = bake_id
              and b.user_id = auth.uid()
        )
    )
);

-- DOWN
-- Rollback (documented; apply manually if needed):
-- drop policy if exists scans_owner_all on public.scans;
-- recreate prior scans_owner_all policy from 0003_phase_b_starter_workflow.sql (without bake ownership);
-- alter table public.scans drop constraint if exists scans_bake_id_fkey;
-- drop index if exists scans_bake_id_idx;
-- drop policy if exists bakes_owner_all on public.bakes;
-- drop index if exists bakes_starter_baked_at_idx;
-- drop index if exists bakes_user_baked_at_idx;
-- drop table if exists public.bakes;
