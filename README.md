# Robbie Robot · leerapps

Leerapps voor het basisonderwijs met Robbie Robot als gids. Elke app staat in een eigen map en wordt via GitHub Pages online gezet.

| App | Map | Voor wie |
|---|---|---|
| Robbie in Robotland | [`robotland/`](robotland/) | 2de kleuterklas – 6de leerjaar |

## Online zetten (GitHub Pages)

Settings → Pages → *Build and deployment* → Source: **Deploy from a branch** → Branch: **main**, map **/ (root)** → Save.
Na een minuutje staat alles op `https://injadekock-spec.github.io/Robbie-Robot/`.

## Robbie in Robotland instellen

1. Voer [`robotland/supabase-robotland.sql`](robotland/supabase-robotland.sql) uit in de SQL Editor van je Supabase-project (pas onderaan je e-mailadres aan).
2. Vul bovenaan [`robotland/index.html`](robotland/index.html) bij `ROBBIE_CONFIG` de **Project URL** en de **anon / publishable key** in. Nooit de service_role- of secret key: deze map is openbaar.
3. Open de app, tik op het slotje, meld je aan en maak je klassen aan.
4. Met **kopieer link** bij een klas krijg je een link zoals `…/robotland/?klas=ABC123`. Zet die in Google Sites via *Invoegen → Insluiten → Via URL*. Toestellen die via die pagina spelen, zijn meteen aan de juiste klas gekoppeld.

Namen en sterren van leerlingen staan alleen in Supabase, nooit in deze map.
