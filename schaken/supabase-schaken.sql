-- Robbie's Schaakkasteel: opslag van de voortgang.
-- Al uitgevoerd in het Supabase-project op 21/11/2026. Alleen opnieuw uitvoeren bij een nieuw project.
-- Gebruikt dezelfde klassen, leerlingen en leerkrachten als Robotland en Raketrace,
-- en de hulpfuncties mt_in_klas en mt_hash uit maaltafels/supabase-maaltafels.sql (voer dat script eerst uit).

create table if not exists public.schaken (
  leerling_id uuid primary key references public.leerlingen(id) on delete cascade,
  pin_hash text,
  mislukt smallint not null default 0,
  geblokkeerd_tot timestamptz,
  gegevens jsonb not null default '{}'::jsonb,
  instellingen jsonb not null default '{}'::jsonb,
  bijgewerkt timestamptz not null default now()
);
alter table public.schaken enable row level security;
drop policy if exists "leerkracht beheert schaken" on public.schaken;
create policy "leerkracht beheert schaken" on public.schaken for all to authenticated
  using (public.rr_is_leerkracht()) with check (public.rr_is_leerkracht());

-- Klas en leerlingen opzoeken met de klascode
create or replace function public.sk_klas(p_code text) returns json
language sql stable security definer set search_path to 'public' as $$
  select json_build_object(
    'klas', json_build_object('id', k.id, 'naam', k.naam),
    'leerlingen', coalesce((
        select json_agg(json_build_object('id', l.id, 'naam', l.naam, 'symbool', l.symbool,
                 'heeft_code', exists (select 1 from public.schaken s
                                       where s.leerling_id = l.id and s.pin_hash is not null))
               order by l.volgorde, l.naam)
        from public.leerlingen l where l.klas_id = k.id), '[]'::json))
  from public.klassen k where k.code = upper(trim(p_code));
$$;

-- Eerste keer: prentjescode kiezen (alleen een hash wordt bewaard)
create or replace function public.sk_code_kiezen(p_code text, p_leerling uuid, p_pin text) returns json
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.mt_in_klas(p_code, p_leerling) then
    return json_build_object('ok', false, 'fout', 'onbekend');
  end if;
  if p_pin is null or p_pin !~ '^[0-8]{3}$' then
    return json_build_object('ok', false, 'fout', 'ongeldige_code');
  end if;
  insert into public.schaken as s (leerling_id, pin_hash)
  values (p_leerling, public.mt_hash(p_leerling, 'sk' || p_pin))
  on conflict (leerling_id) do update
    set pin_hash = excluded.pin_hash, mislukt = 0, geblokkeerd_tot = null
    where s.pin_hash is null;
  if not found then
    return json_build_object('ok', false, 'fout', 'code_bestaat');
  end if;
  return (select json_build_object('ok', true, 'gegevens', gegevens, 'instellingen', instellingen)
          from public.schaken where leerling_id = p_leerling);
end; $$;

-- Aanmelden en voortgang laden (5 foute pogingen = 2 minuten wachten)
create or replace function public.sk_laden(p_code text, p_leerling uuid, p_pin text) returns json
language plpgsql security definer set search_path to 'public' as $$
declare r public.schaken%rowtype;
begin
  if not public.mt_in_klas(p_code, p_leerling) then
    return json_build_object('ok', false, 'fout', 'onbekend');
  end if;
  select * into r from public.schaken where leerling_id = p_leerling;
  if not found or r.pin_hash is null then
    return json_build_object('ok', false, 'fout', 'geen_code');
  end if;
  if r.geblokkeerd_tot is not null and r.geblokkeerd_tot > now() then
    return json_build_object('ok', false, 'fout', 'geblokkeerd');
  end if;
  if p_pin is null or r.pin_hash <> public.mt_hash(p_leerling, 'sk' || p_pin) then
    update public.schaken
      set geblokkeerd_tot = case when mislukt + 1 >= 5 then now() + interval '2 minutes' else null end,
          mislukt = case when mislukt + 1 >= 5 then 0 else mislukt + 1 end
      where leerling_id = p_leerling;
    return json_build_object('ok', false, 'fout', 'foute_code');
  end if;
  update public.schaken set mislukt = 0, geblokkeerd_tot = null where leerling_id = p_leerling;
  return json_build_object('ok', true, 'gegevens', r.gegevens, 'instellingen', r.instellingen);
end; $$;

-- Voortgang bewaren
create or replace function public.sk_bewaren(p_code text, p_leerling uuid, p_pin text, p_gegevens jsonb) returns json
language plpgsql security definer set search_path to 'public' as $$
declare r public.schaken%rowtype;
begin
  if not public.mt_in_klas(p_code, p_leerling) then
    return json_build_object('ok', false, 'fout', 'onbekend');
  end if;
  if p_gegevens is null or jsonb_typeof(p_gegevens) <> 'object' or length(p_gegevens::text) > 200000 then
    return json_build_object('ok', false, 'fout', 'ongeldige_gegevens');
  end if;
  update public.schaken set gegevens = p_gegevens, bijgewerkt = now()
    where leerling_id = p_leerling and pin_hash is not null
      and pin_hash = public.mt_hash(p_leerling, 'sk' || coalesce(p_pin, ''))
    returning * into r;
  if not found then
    return json_build_object('ok', false, 'fout', 'foute_code');
  end if;
  return json_build_object('ok', true, 'instellingen', r.instellingen);
end; $$;

-- Alleen voor leerkrachten: overzicht, instellingen, code wissen, voortgang wissen
create or replace function public.sk_overzicht(p_code text) returns json
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.rr_is_leerkracht() then
    raise exception 'alleen voor leerkrachten' using errcode = '42501';
  end if;
  return coalesce((
    select json_agg(json_build_object('id', l.id, 'naam', l.naam, 'symbool', l.symbool,
             'heeft_code', s.pin_hash is not null, 'gegevens', coalesce(s.gegevens, '{}'::jsonb),
             'instellingen', coalesce(s.instellingen, '{}'::jsonb), 'bijgewerkt', s.bijgewerkt)
           order by l.volgorde, l.naam)
    from public.leerlingen l join public.klassen k on k.id = l.klas_id
    left join public.schaken s on s.leerling_id = l.id
    where k.code = upper(trim(p_code))), '[]'::json);
end; $$;

create or replace function public.sk_instellingen(p_leerling uuid, p_instellingen jsonb) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.rr_is_leerkracht() then
    raise exception 'alleen voor leerkrachten' using errcode = '42501';
  end if;
  if p_instellingen is null or jsonb_typeof(p_instellingen) <> 'object' or length(p_instellingen::text) > 5000 then
    raise exception 'ongeldige instellingen';
  end if;
  insert into public.schaken as s (leerling_id, instellingen) values (p_leerling, p_instellingen)
  on conflict (leerling_id) do update set instellingen = excluded.instellingen;
end; $$;

create or replace function public.sk_code_wissen(p_leerling uuid) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.rr_is_leerkracht() then
    raise exception 'alleen voor leerkrachten' using errcode = '42501';
  end if;
  update public.schaken set pin_hash = null, mislukt = 0, geblokkeerd_tot = null where leerling_id = p_leerling;
end; $$;

create or replace function public.sk_voortgang_wissen(p_leerling uuid) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.rr_is_leerkracht() then
    raise exception 'alleen voor leerkrachten' using errcode = '42501';
  end if;
  update public.schaken set gegevens = '{}'::jsonb, bijgewerkt = now() where leerling_id = p_leerling;
end; $$;

revoke all on function public.sk_overzicht(text), public.sk_instellingen(uuid, jsonb), public.sk_code_wissen(uuid), public.sk_voortgang_wissen(uuid) from public, anon;
grant execute on function public.sk_overzicht(text), public.sk_instellingen(uuid, jsonb), public.sk_code_wissen(uuid), public.sk_voortgang_wissen(uuid) to authenticated;
grant execute on function public.sk_klas(text), public.sk_code_kiezen(text, uuid, text), public.sk_laden(text, uuid, text), public.sk_bewaren(text, uuid, text, jsonb) to anon, authenticated;
