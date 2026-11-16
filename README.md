# Robbie Robot · leerapps

Leerapps voor het basisonderwijs met Robbie Robot als gids. Elke app staat in een eigen map en wordt via GitHub Pages online gezet.

| App | Map | Voor wie |
|---|---|---|
| Robbie in Robotland | [`robotland/`](robotland/) | 2de kleuterklas – 6de leerjaar |
| Robbie's Raketrace (maaltafels) | [`maaltafels/`](maaltafels/) | vanaf het 2de leerjaar |

## Online zetten (GitHub Pages)

Settings → Pages → *Build and deployment* → Source: **Deploy from a branch** → Branch: **main**, map **/ (root)** → Save.
Na een minuutje staat alles op `https://injadekock-spec.github.io/Robbie-Robot/`.

## Robbie in Robotland instellen

1. Voer [`robotland/supabase-robotland.sql`](robotland/supabase-robotland.sql) uit in de SQL Editor van je Supabase-project (pas onderaan je e-mailadres aan).
2. Vul bovenaan [`robotland/index.html`](robotland/index.html) bij `ROBBIE_CONFIG` de **Project URL** en de **anon / publishable key** in. Nooit de service_role- of secret key: deze map is openbaar.
3. Open de app, tik op het slotje, meld je aan en maak je klassen aan.
4. Met **kopieer link** bij een klas krijg je een link zoals `…/robotland/?klas=ABC123`. Zet die in Google Sites via *Invoegen → Insluiten → Via URL*. Toestellen die via die pagina spelen, zijn meteen aan de juiste klas gekoppeld.

Namen en sterren van leerlingen staan alleen in Supabase, nooit in deze map.

## Robbie's Raketrace (maaltafels) instellen

De maaltafel-app gebruikt **hetzelfde Supabase-project, dezelfde klassen, klascodes en leerlingen** als Robbie in Robotland. Stel dus eerst Robotland in en maak daar je klas en leerlingen aan (slotje → Klassen).

1. Voer [`maaltafels/supabase-maaltafels.sql`](maaltafels/supabase-maaltafels.sql) uit in de SQL Editor (na het Robotland-script).
2. Bovenaan [`maaltafels/index.html`](maaltafels/index.html) staan bij `MAALTAFEL_CONFIG` de **Project URL** en de **anon / publishable key**. Laat je ze leeg, dan blijft de voortgang alleen op het toestel zelf.
3. Geef de kinderen de link `…/maaltafels/?klas=ABC123` (met je eigen klascode), of laat hen de klascode zelf intikken.
4. Een kind kiest zijn naam en de eerste keer een **geheime code van 3 prentjes**. Met klascode + naam + prentjescode staat de voortgang daarna op elk toestel klaar.
5. Code vergeten? In de app: *Overzicht voor de juf* → aanmelden met je leerkracht-account → **🔑 wissen**. Het kind kiest dan een nieuwe code; de voortgang blijft.

Leerlingen kunnen de databank nooit rechtstreeks lezen: alleen hun eigen voortgang, via klascode + prentjescode. De prentjescode zelf wordt niet bewaard, alleen een hash.
