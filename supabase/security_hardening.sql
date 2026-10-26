-- Applied after schema.sql on the project with automatic RLS enabled.
alter function public.protect_claim_update() set search_path = '';
revoke all on function public.protect_claim_update() from public, anon, authenticated;
revoke all on function public.rls_auto_enable() from public, anon, authenticated;
create index if not exists finds_finder_idx on public.finds (finder_id);
create index if not exists claims_claimant_idx on public.claims (claimant_id);
