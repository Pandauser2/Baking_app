-- UP
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
    select
        id as duplicate_id,
        keeper_id
    from ranked_scans
    where row_num > 1
),
updated_states as (
    update public.starter_states st
    set updated_from_scan_id = d.keeper_id
    from duplicate_scans d
    where st.updated_from_scan_id = d.duplicate_id
    returning st.starter_id
)
delete from public.scans s
using duplicate_scans d
where s.id = d.duplicate_id;

create unique index if not exists scans_starter_user_path_unique
on public.scans (user_id, scan_type, storage_path)
where scan_type = 'starter';

-- DOWN
drop index if exists public.scans_starter_user_path_unique;
