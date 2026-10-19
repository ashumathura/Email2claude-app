-- Only the server-side role (the Edge Function and release workflow) may touch these tables.
-- New tables in this project are not granted to service_role by default.
grant usage on schema public to service_role;
grant select, insert, update, delete on public.installs, public.licenses, public.releases to service_role;
grant execute on function public.generate_license_key() to service_role;
grant execute on function public.issue_license(text, int) to service_role;
