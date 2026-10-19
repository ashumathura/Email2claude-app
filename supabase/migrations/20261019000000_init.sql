-- eMail to Claude backend: installs, licenses, releases.
-- Row-level security is on and there are no policies: only the service role
-- (the `checkin` Edge Function and the release workflow) can read or write.

create extension if not exists pgcrypto with schema extensions;

-- One row per app install, keyed by a random ID the app generates.
-- Without analytics consent only device_id and the two dates are kept.
create table public.installs (
  device_id          uuid primary key,
  first_open_at      timestamptz not null default now(),
  last_used_at       timestamptz not null default now(),
  analytics_consent  boolean not null default false,
  consent_updated_at timestamptz,
  -- Analytics: filled only while the user has opted in, cleared when they opt out.
  macos_version      text,
  os_language        text,
  app_version        text,
  ip_address         inet,
  ip_country         text,
  ip_city            text,
  license_key        text
);

create table public.licenses (
  key        text primary key,
  email      text,
  status     text not null default 'active' check (status in ('active', 'revoked')),
  expires_at timestamptz,
  note       text,
  created_at timestamptz not null default now()
);

create table public.releases (
  version      text primary key,
  dmg_path     text not null,
  sha256       text not null,
  min_macos    text not null default '13.0',
  notes        text,
  published    boolean not null default false,
  published_at timestamptz not null default now()
);

alter table public.installs enable row level security;
alter table public.licenses enable row level security;
alter table public.releases enable row level security;

revoke all on public.installs, public.licenses, public.releases from anon, authenticated;

-- License keys look like EMC-XXXXX-XXXXX-XXXXX-XXXXX: 100 random bits, no 0/O/1/I.
create or replace function public.generate_license_key()
returns text
language plpgsql
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := extensions.gen_random_bytes(20);
  result text := 'EMC';
  i int;
begin
  for i in 0..19 loop
    if i % 5 = 0 then result := result || '-'; end if;
    result := result || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
  end loop;
  return result;
end;
$$;

-- select public.issue_license('buyer@example.com');           -- never expires
-- select public.issue_license('buyer@example.com', 365);      -- valid for a year
create or replace function public.issue_license(buyer_email text, valid_days int default null)
returns text
language plpgsql
set search_path = ''
as $$
declare
  new_key text := public.generate_license_key();
begin
  insert into public.licenses (key, email, expires_at)
  values (new_key, buyer_email, case when valid_days is null then null else now() + make_interval(days => valid_days) end);
  return new_key;
end;
$$;

revoke execute on function public.generate_license_key() from public, anon, authenticated;
revoke execute on function public.issue_license(text, int) from public, anon, authenticated;

-- Private bucket for the signed DMGs. No storage policies: downloads happen through
-- short-lived signed URLs that the Edge Function hands out after the license check.
insert into storage.buckets (id, name, public, file_size_limit)
values ('releases', 'releases', false, 157286400)
on conflict (id) do nothing;
