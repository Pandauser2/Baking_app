-- UP

create table if not exists public.loaf_scans (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    image_path text not null,
    crumb_score int,
    crust_score int,
    oven_spring_score int,
    overall_score int,
    strengths text[] not null default '{}',
    improvements text[] not null default '{}',
    next_steps text[] not null default '{}',
    ai_summary text,
    prompt_version text not null default 'v1',
    created_at timestamptz not null default now()
);

create index if not exists loaf_scans_user_created_idx
    on public.loaf_scans (user_id, created_at desc);

create index if not exists loaf_scans_created_idx
    on public.loaf_scans (created_at desc);

alter table public.loaf_scans enable row level security;

drop policy if exists "users own scans" on public.loaf_scans;
create policy "users own scans"
on public.loaf_scans
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
values ('loaf-images', 'loaf-images', false)
on conflict (id) do nothing;

drop policy if exists "users can upload own loaf images" on storage.objects;
create policy "users can upload own loaf images"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'loaf-images'
    and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "users can read own loaf images" on storage.objects;
create policy "users can read own loaf images"
on storage.objects
for select
to authenticated
using (
    bucket_id = 'loaf-images'
    and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "users can delete own loaf images" on storage.objects;
create policy "users can delete own loaf images"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'loaf-images'
    and split_part(name, '/', 1) = auth.uid()::text
);

-- DOWN

drop policy if exists "users can delete own loaf images" on storage.objects;
drop policy if exists "users can read own loaf images" on storage.objects;
drop policy if exists "users can upload own loaf images" on storage.objects;

delete from storage.buckets where id = 'loaf-images';

drop policy if exists "users own scans" on public.loaf_scans;

drop index if exists loaf_scans_created_idx;
drop index if exists loaf_scans_user_created_idx;
drop table if exists public.loaf_scans;

