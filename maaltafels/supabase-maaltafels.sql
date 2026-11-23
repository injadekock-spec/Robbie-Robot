-- =====================================================================
--  Robbie's Raketrace (maaltafels) · Supabase-opzet
--  Voer EERST robotland/supabase-robotland.sql uit (klassen + leerlingen).
--  Plak daarna dit volledige script in Supabase → SQL Editor → New query → Run.
--  Je kan het script later opnieuw uitvoeren: bestaande gegevens blijven.
--
--  De maaltafel-app gebruikt dezelfde klassen, klascodes en leerlingen als
--  Robbie in Robotland. Per leerling komt er één rij bij met de voortgang
--  en (versleuteld) de geheime prentjescode.
-- =====================================================================

-- 1. Tabel ---------------------------------------------------------------
create table if not exists public.maaltafels (
  leerling_id     uuid primary key references public.leerlingen(id) on delete cascade,
  pin_hash        text,                                  -- hash van de prentjescode (nooit de code zelf)
  mislukt         smallint not null default 0,           -- foute pogingen na elkaar
  geblokkeerd_tot timestamptz,                           -- even op slot na 5 foute pogingen
  gegevens        jsonb not null default '{}'::jsonb,    -- voortgang van de app
  bijgewerkt      timestamptz not null default now()
);

-- 1b. Tafels die de juf vrijgeeft ---------------------------------------
--    instellingen = {"m":[10 getallen],"d":[10 getallen]} voor tafel 1 t.e.m. 10
--    0 = op slot · 1 = nieuw (oefenen tot het diploma van Bugbot) · 2 = gekend
--    Per klas een standaard; per leerling kan je die overschrijven ({} = volgt de klas).
alter table public.maaltafels add column if not exists instellingen jsonb not null default '{}'::jsonb;

create table if not exists public.maaltafels_klas (
  klas_id      uuid primary key references public.klassen(id) on delete cascade,
  instellingen jsonb not null default '{}'::jsonb,
  bijgewerkt   timestamptz not null default now()
);

-- 2. Beveiliging -----------------------------------------------------------
--    Leerlingen kunnen NIETS rechtstreeks lezen of schrijven: alleen via de
--    functies hieronder, met klascode + prentjescode. De leerkracht beheert alles.
alter table public.maaltafels enable row level security;

drop policy if exists "leerkracht beheert maaltafels" on public.maaltafels;
create policy "leerkracht beheert maaltafels" on public.maaltafels
  for all to authenticated using (public.rr_is_leerkracht()) with check (public.rr_is_leerkracht());

alter table public.maaltafels_klas enable row level security;

drop policy if exists "leerkracht beheert maaltafels_klas" on public.maaltafels_klas;
create policy "leerkracht beheert maaltafels_klas" on public.maaltafels_klas
  for all to authenticated using (public.rr_is_leerkracht()) with check (public.rr_is_leerkracht());

-- 3. Hulpfuncties ----------------------------------------------------------
create or replace function public.mt_hash(p_leerling uuid, p_pin text)
returns text language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(p_pin || ':' || p_leerling::text, 'UTF8')), 'hex');
$$;

create or replace function public.mt_in_klas(p_code text, p_leerling uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.leerlingen l join public.klassen k on k.id = l.klas_id
    where l.id = p_leerling and k.code = upper(trim(p_code))
  );
$$;

-- Welke tafels mag deze leerling oefenen? Eigen instelling, anders die van de klas.
create or replace function public.mt_tafels(p_leerling uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(
    (select m.instellingen from public.maaltafels m
      where m.leerling_id = p_leerling and m.instellingen <> '{}'::jsonb),
    (select k.instellingen from public.maaltafels_klas k
      join public.leerlingen l on l.klas_id = k.klas_id where l.id = p_leerling),
    '{}'::jsonb);
$$;

-- 4. Functies voor de leerlingen -------------------------------------------
-- Klaslijst ophalen met de klascode (zonder voortgang)
create or replace function public.mt_klas(p_code text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'klas', json_build_object('id', k.id, 'naam', k.naam),
    'leerlingen', coalesce((
        select json_agg(json_build_object('id', l.id, 'naam', l.naam, 'symbool', l.symbool,
                 'heeft_code', exists (select 1 from public.maaltafels m
                                       where m.leerling_id = l.id and m.pin_hash is not null))
               order by l.volgorde, l.naam)
        from public.leerlingen l where l.klas_id = k.id), '[]'::json)
  )
  from public.klassen k
  where k.code = upper(trim(p_code));
$$;

-- Eerste keer: de leerling kiest een prentjescode (kan alleen als er nog geen is)
create or replace function public.mt_code_kiezen(p_code text, p_leerling uuid, p_pin text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not public.mt_in_klas(p_code, p_leerling) then
    return json_build_object('ok', false, 'fout', 'onbekend');
  end if;
  if p_pin is null or p_pin !~ '^[0-8]{3}$' then
    return json_build_object('ok', false, 'fout', 'ongeldige_code');
  end if;
  insert into public.maaltafels as m (leerling_id, pin_hash)
  values (p_leerling, public.mt_hash(p_leerling, p_pin))
  on conflict (leerling_id) do update
    set pin_hash = excluded.pin_hash, mislukt = 0, geblokkeerd_tot = null
    where m.pin_hash is null;
  if not found then
    return json_build_object('ok', false, 'fout', 'code_bestaat');
  end if;
  return json_build_object('ok', true, 'gegevens',
    (select gegevens from public.maaltafels where leerling_id = p_leerling),
    'tafels', public.mt_tafels(p_leerling));
end;
$$;

-- Aanmelden: voortgang ophalen met klascode + prentjescode
create or replace function public.mt_laden(p_code text, p_leerling uuid, p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare r public.maaltafels%rowtype;
begin
  if not public.mt_in_klas(p_code, p_leerling) then
    return json_build_object('ok', false, 'fout', 'onbekend');
  end if;
  select * into r from public.maaltafels where leerling_id = p_leerling;
  if not found or r.pin_hash is null then
    return json_build_object('ok', false, 'fout', 'geen_code');
  end if;
  if r.geblokkeerd_tot is not null and r.geblokkeerd_tot > now() then
    return json_build_object('ok', false, 'fout', 'geblokkeerd');
  end if;
  if p_pin is null or r.pin_hash <> public.mt_hash(p_leerling, p_pin) then
    update public.maaltafels
      set geblokkeerd_tot = case when mislukt + 1 >= 5 then now() + interval '2 minutes' else null end,
          mislukt         = case when mislukt + 1 >= 5 then 0 else mislukt + 1 end
      where leerling_id = p_leerling;
    return json_build_object('ok', false, 'fout', 'foute_code');
  end if;
  update public.maaltafels set mislukt = 0, geblokkeerd_tot = null where leerling_id = p_leerling;
  return json_build_object('ok', true, 'gegevens', r.gegevens, 'tafels', public.mt_tafels(p_leerling));
end;
$$;

-- Voortgang bewaren
create or replace function public.mt_bewaren(p_code text, p_leerling uuid, p_pin text, p_gegevens jsonb)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not public.mt_in_klas(p_code, p_leerling) then
    return json_build_object('ok', false, 'fout', 'onbekend');
  end if;
  if p_gegevens is null or jsonb_typeof(p_gegevens) <> 'object' or length(p_gegevens::text) > 200000 then
    return json_build_object('ok', false, 'fout', 'ongeldige_gegevens');
  end if;
  update public.maaltafels
    set gegevens = p_gegevens, bijgewerkt = now()
    where leerling_id = p_leerling and pin_hash is not null
      and pin_hash = public.mt_hash(p_leerling, coalesce(p_pin, ''));
  if not found then
    return json_build_object('ok', false, 'fout', 'foute_code');
  end if;
  return json_build_object('ok', true, 'tafels', public.mt_tafels(p_leerling));
end;
$$;

-- 5. Functies voor de leerkracht (aangemeld) --------------------------------
-- Overzicht van een klas met alle voortgang
create or replace function public.mt_overzicht(p_code text)
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.rr_is_leerkracht() then
    raise exception 'alleen voor leerkrachten' using errcode = '42501';
  end if;
  return coalesce((
    select json_agg(json_build_object('id', l.id, 'naam', l.naam, 'symbool', l.symbool,
             'heeft_code', m.pin_hash is not null, 'gegevens', coalesce(m.gegevens, '{}'::jsonb),
             'bijgewerkt', m.bijgewerkt,
             'instellingen', coalesce(m.instellingen, '{}'::jsonb),
             'klas_instellingen', coalesce(kt.instellingen, '{}'::jsonb)) order by l.volgorde, l.naam)
    from public.leerlingen l
    join public.klassen k on k.id = l.klas_id
    left join public.maaltafels m on m.leerling_id = l.id
    left join public.maaltafels_klas kt on kt.klas_id = k.id
    where k.code = upper(trim(p_code))), '[]'::json);
end;
$$;

-- Prentjescode van een leerling wissen (voortgang blijft; het kind kiest een nieuwe code)
create or replace function public.mt_code_wissen(p_leerling uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.rr_is_leerkracht() then
    raise exception 'alleen voor leerkrachten' using errcode = '42501';
  end if;
  update public.maaltafels set pin_hash = null, mislukt = 0, geblokkeerd_tot = null
    where leerling_id = p_leerling;
end;
$$;

-- Tafels instellen voor de hele klas (p_leerling = null) of voor één leerling
-- ({} bij een leerling = terug naar de instelling van de klas)
create or replace function public.mt_tafels_zetten(p_code text, p_leerling uuid, p_instellingen jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_klas uuid;
begin
  if not public.rr_is_leerkracht() then
    raise exception 'alleen voor leerkrachten' using errcode = '42501';
  end if;
  if p_instellingen is null or jsonb_typeof(p_instellingen) <> 'object' or length(p_instellingen::text) > 2000 then
    raise exception 'ongeldige instellingen';
  end if;
  select id into v_klas from public.klassen where code = upper(trim(p_code));
  if v_klas is null then
    raise exception 'onbekende klas';
  end if;
  if p_leerling is null then
    insert into public.maaltafels_klas as k (klas_id, instellingen) values (v_klas, p_instellingen)
    on conflict (klas_id) do update set instellingen = excluded.instellingen, bijgewerkt = now();
  else
    if not public.mt_in_klas(p_code, p_leerling) then
      raise exception 'onbekende leerling';
    end if;
    insert into public.maaltafels as m (leerling_id, instellingen) values (p_leerling, p_instellingen)
    on conflict (leerling_id) do update set instellingen = excluded.instellingen;
  end if;
end;
$$;

-- 6. Rechten -----------------------------------------------------------------
revoke all on function public.mt_hash(uuid, text) from public, anon, authenticated;
revoke all on function public.mt_in_klas(text, uuid) from public, anon, authenticated;
revoke all on function public.mt_klas(text) from public, anon, authenticated;
revoke all on function public.mt_code_kiezen(text, uuid, text) from public, anon, authenticated;
revoke all on function public.mt_laden(text, uuid, text) from public, anon, authenticated;
revoke all on function public.mt_bewaren(text, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.mt_overzicht(text) from public, anon, authenticated;
revoke all on function public.mt_code_wissen(uuid) from public, anon, authenticated;
revoke all on function public.mt_tafels(uuid) from public, anon, authenticated;
revoke all on function public.mt_tafels_zetten(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.mt_klas(text) to anon, authenticated;
grant execute on function public.mt_code_kiezen(text, uuid, text) to anon, authenticated;
grant execute on function public.mt_laden(text, uuid, text) to anon, authenticated;
grant execute on function public.mt_bewaren(text, uuid, text, jsonb) to anon, authenticated;
grant execute on function public.mt_overzicht(text) to authenticated;
grant execute on function public.mt_code_wissen(uuid) to authenticated;
grant execute on function public.mt_tafels_zetten(text, uuid, jsonb) to authenticated;
