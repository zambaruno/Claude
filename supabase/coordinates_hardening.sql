-- Run once on the existing project AFTER the 0.2.0 app is installed on testers' phones.
-- Before this change anyone, even without signing in, could read the exact
-- latitude/longitude of every find through the public API. Afterwards the
-- columns can be written by the app but not read back by any client.
-- Old app versions (0.1.x) read these columns with select(*) in the detail
-- screen and will fail to open a find until they are updated.
revoke select on public.finds from anon, authenticated;
grant select (id, finder_id, image_path, description, place_label, status, handed_to, created_at)
  on public.finds to anon, authenticated;
