-- =====================================================================
--  Robbie in Robotland · Supabase-opzet
--  Plak dit volledige script in Supabase → SQL Editor → New query → Run.
--  Pas EERST onderaan je e-mailadres aan (stap 5).
--  Je kan het script later opnieuw uitvoeren: bestaande gegevens blijven.
-- =====================================================================

-- 1. Tabellen ----------------------------------------------------------
create table if not exists public.leerkrachten (
  email text primary key
);

create table if not exists public.klassen (
  id         uuid primary key default gen_random_uuid(),
  naam       text not null check (char_length(naam) between 1 and 60),
  code       text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  aangemaakt timestamptz not null default now()
);

create table if not exists public.leerlingen (
  id         uuid primary key default gen_random_uuid(),
  klas_id    uuid not null references public.klassen(id) on delete cascade,
  naam       text not null check (char_length(naam) between 1 and 40),
  symbool    text not null default '⭐' check (char_length(symbool) between 1 and 8),
  niveau     smallint not null default 0 check (niveau between 0 and 3),
  volgorde   int not null default 0,
  aangemaakt timestamptz not null default now()
);
create index if not exists leerlingen_klas_idx on public.leerlingen(klas_id);

create table if not exists public.voortgang (
  leerling_id uuid not null references public.leerlingen(id) on delete cascade,
  sleutel     text not null check (sleutel ~ '^[1-3]-([0-9]|1[0-9])$'),  -- niveau-level, bv. 2-17 (max. 20 levels per niveau)
  sterren     smallint not null check (sterren between 1 and 3),
  eerst       timestamptz not null default now(),   -- eerste keer opgelost
  bijgewerkt  timestamptz not null default now(),   -- laatste verbetering
  primary key (leerling_id, sleutel)
);

-- 1b. Bestaande installatie bijwerken: tot 20 levels per niveau
alter table public.voortgang drop constraint if exists voortgang_sleutel_check;
alter table public.voortgang add constraint voortgang_sleutel_check check (sleutel ~ '^[1-3]-([0-9]|1[0-9])$');

-- 2. Wie is leerkracht? ------------------------------------------------
create or replace function public.rr_is_leerkracht()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.leerkrachten
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- 3. Beveiliging (Row Level Security) ----------------------------------
--    Leerlingen (niet aangemeld) kunnen NIETS rechtstreeks lezen of schrijven.
--    Ze gebruiken enkel de twee functies hieronder, met de klascode.
--    Alleen een aangemelde leerkracht uit de tabel leerkrachten beheert alles.
alter table public.leerkrachten enable row level security;
alter table public.klassen      enable row level security;
alter table public.leerlingen   enable row level security;
alter table public.voortgang    enable row level security;

drop policy if exists "leerkracht leest zichzelf" on public.leerkrachten;
create policy "leerkracht leest zichzelf" on public.leerkrachten
  for select to authenticated using (public.rr_is_leerkracht());

drop policy if exists "leerkracht beheert klassen" on public.klassen;
create policy "leerkracht beheert klassen" on public.klassen
  for all to authenticated using (public.rr_is_leerkracht()) with check (public.rr_is_leerkracht());

drop policy if exists "leerkracht beheert leerlingen" on public.leerlingen;
create policy "leerkracht beheert leerlingen" on public.leerlingen
  for all to authenticated using (public.rr_is_leerkracht()) with check (public.rr_is_leerkracht());

drop policy if exists "leerkracht beheert voortgang" on public.voortgang;
create policy "leerkracht beheert voortgang" on public.voortgang
  for all to authenticated using (public.rr_is_leerkracht()) with check (public.rr_is_leerkracht());

-- 4. Functies voor de klastoestellen -----------------------------------
-- Klaslijst + sterren ophalen met de klascode
create or replace function public.rr_klas(p_code text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'klas', json_build_object('id', k.id, 'naam', k.naam),
    'leerlingen', coalesce((
        select json_agg(json_build_object('id', l.id, 'naam', l.naam, 'symbool', l.symbool, 'niveau', l.niveau)
                        order by l.volgorde, l.naam)
        from public.leerlingen l where l.klas_id = k.id), '[]'::json),
    'voortgang', coalesce((
        select json_agg(json_build_object('leerling_id', v.leerling_id, 'sleutel', v.sleutel,
                        'sterren', v.sterren, 'eerst', v.eerst, 'bijgewerkt', v.bijgewerkt))
        from public.voortgang v join public.leerlingen l on l.id = v.leerling_id
        where l.klas_id = k.id), '[]'::json)
  )
  from public.klassen k
  where k.code = upper(trim(p_code));
$$;

-- Sterren bewaren (houdt altijd het beste resultaat bij)
create or replace function public.rr_sterren(p_code text, p_leerling uuid, p_sleutel text, p_sterren int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.leerlingen l join public.klassen k on k.id = l.klas_id
    where l.id = p_leerling and k.code = upper(trim(p_code))
  ) then
    raise exception 'onbekende leerling of klascode' using errcode = 'P0002';
  end if;
  insert into public.voortgang as v (leerling_id, sleutel, sterren)
  values (p_leerling, p_sleutel, least(greatest(p_sterren, 1), 3))
  on conflict (leerling_id, sleutel) do update
    set sterren    = greatest(v.sterren, excluded.sterren),
        bijgewerkt = case when excluded.sterren > v.sterren then now() else v.bijgewerkt end;
end;
$$;

revoke all on function public.rr_klas(text) from public;
revoke all on function public.rr_sterren(text, uuid, text, int) from public;
revoke all on function public.rr_is_leerkracht() from public;
grant execute on function public.rr_klas(text) to anon, authenticated;
grant execute on function public.rr_sterren(text, uuid, text, int) to anon, authenticated;
grant execute on function public.rr_is_leerkracht() to authenticated;

-- 5. JOUW E-MAILADRES ---------------------------------------------------
--    Vervang het adres hieronder door het e-mailadres van je leerkracht-account
--    (hetzelfde als bij Authentication → Users). Meerdere leerkrachten? Voeg extra regels toe.
insert into public.leerkrachten (email) values ('jouw.naam@school.be')
on conflict do nothing;
