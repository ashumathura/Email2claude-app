-- Free license keys are issued from the app: one per email address, tied to the device that asked.
-- The email and device_id are removed from the license row when the user erases their data;
-- the key itself stays valid.

alter table public.licenses add column if not exists device_id uuid;

create unique index if not exists licenses_email_unique
  on public.licenses (lower(email)) where email is not null;
