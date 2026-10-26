-- Run once in the Supabase SQL Editor. Enable the Google provider in Auth.
create extension if not exists pgcrypto;
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  avatar_path text,
  created_at timestamptz not null default now()
);
create table if not exists public.finds (
  id uuid primary key default gen_random_uuid(),
  finder_id uuid not null references auth.users(id) on delete cascade,
  image_path text not null,
  description text not null check (char_length(description) between 1 and 150),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  place_label text,
  status text not null default 'held' check (status in ('held','handed_over','returned')),
  handed_to text,
  created_at timestamptz not null default now(),
  check (status <> 'handed_over' or nullif(trim(handed_to), '') is not null)
);
create index if not exists finds_feed_idx on public.finds (created_at desc);
create table if not exists public.claims (
  id uuid primary key default gen_random_uuid(),
  find_id uuid not null references public.finds(id) on delete cascade,
  claimant_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(message) between 1 and 500),
  response text check (char_length(response) <= 500),
  created_at timestamptz not null default now(),
  unique(find_id, claimant_id)
);
create index if not exists claims_find_idx on public.claims (find_id, created_at);
-- Only these tables are exposed to the mobile client. RLS policies below
-- still decide which individual rows and operations each role may use.
grant usage on schema public to anon, authenticated;
-- Column-level grant: latitude and longitude are intentionally not readable by clients.
grant select (id, finder_id, image_path, description, place_label, status, handed_to, created_at) on public.finds to anon, authenticated;
grant insert, update on public.finds to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.claims to authenticated;
alter table public.profiles enable row level security;
alter table public.finds enable row level security;
alter table public.claims enable row level security;
create policy "profiles read own" on public.profiles for select to authenticated using (id = auth.uid());
create policy "profiles insert own" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "profiles update own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "finds read" on public.finds for select to anon, authenticated using (true);
create policy "finds insert own" on public.finds for insert to authenticated with check (finder_id = auth.uid());
create policy "finds update own" on public.finds for update to authenticated using (finder_id = auth.uid()) with check (finder_id = auth.uid());
create policy "claims read parties" on public.claims for select to authenticated using (claimant_id = auth.uid() or exists (select 1 from public.finds f where f.id = find_id and f.finder_id = auth.uid()));
create policy "claims insert claimant" on public.claims for insert to authenticated with check (claimant_id = auth.uid() and exists (select 1 from public.finds f where f.id = find_id and f.finder_id <> auth.uid() and f.status <> 'returned'));
create policy "claims finder respond" on public.claims for update to authenticated using (exists (select 1 from public.finds f where f.id = find_id and f.finder_id = auth.uid())) with check (exists (select 1 from public.finds f where f.id = find_id and f.finder_id = auth.uid()));
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('finds', 'finds', true, 2097152, array['image/jpeg'])
on conflict (id) do nothing;
update storage.buckets set file_size_limit = 2097152, allowed_mime_types = array['image/jpeg']::text[] where id = 'finds';
create policy "public found photos" on storage.objects for select to anon, authenticated using (bucket_id = 'finds');
create policy "owner photo upload" on storage.objects for insert to authenticated with check (bucket_id = 'finds' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owner photo deletion" on storage.objects for delete to authenticated using (bucket_id = 'finds' and (storage.foldername(name))[1] = auth.uid()::text);
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;
create policy "public avatars" on storage.objects for select to anon, authenticated using (bucket_id = 'avatars');
create policy "owner avatar upload" on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owner avatar update" on storage.objects for update to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owner avatar delete" on storage.objects for delete to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Prevent a finder from rewriting a claimant's original statement or identity.
create or replace function public.protect_claim_update() returns trigger language plpgsql as $$
begin
  if new.id is distinct from old.id or new.find_id is distinct from old.find_id or
     new.claimant_id is distinct from old.claimant_id or new.message is distinct from old.message or
     new.created_at is distinct from old.created_at then
    raise exception 'Only the response may be changed';
  end if;
  return new;
end; $$;
create trigger claims_immutable before update on public.claims for each row execute function public.protect_claim_update();
