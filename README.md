# Enkelt Budsjett

En offline-first iOS-app bygget i SwiftUI + SwiftData for:
- budsjettsporing
- investeringsoversikt (månedlige snapshots)
- enkel måloppfølging

## Foreløpig status

- Budsjett: inntekt, utgift og manuell sparing med gruppert visning.
- Faste poster: månedlig auto-opprettelse av transaksjoner.
- Investeringer: månedlig innsjekk med oppdatering per måned (`periodKey`).
- Oversikt: formue, utvikling og spart hittil i år.
- Dataflyt: eksport/import av JSON med `Slå sammen` eller `Erstatt alt`.

## Kjør lokalt

1. Åpne `Enkelt Budsjett.xcodeproj` i Xcode.
2. Velg iPhone-simulator eller fysisk enhet.
3. Trykk `Run` (`Cmd + R`).

## MVP-fokus

- Lokal lagring (ingen konto nødvendig)
- NOK som valuta
- Månedsbasert budsjett og investeringsinsjekk
- Enkel, varm og ikke-moraliserende UX

## Data og personvern

- Appen lagrer data lokalt på enheten (offline-first).
- Ingen tredjepartssporing i MVP.
- Eksport og import av data (JSON) er tilgjengelig fra `Innstillinger > Data`.

## App Store-klargjøring (juridisk)

- Privacy manifest: `Enkelt Budsjett/PrivacyInfo.xcprivacy`
- App Store Connect metadata: `AppStoreConnect-metadata.md`
- Personverntekst (NO): `docs/legal/personvern-no.md`
- Vilkår (NO): `docs/legal/vilkar-no.md`

## GitHub Pages

Repoet inneholder en statisk landingsside i `docs/` som kan publiseres direkte med GitHub Pages.

1. Push repoet til GitHub.
2. Gå til `Settings > Pages`.
3. Velg `Deploy from a branch`.
4. Velg branch `main` og mappe `/docs`.
5. Publisert side blir tilgjengelig på `https://<github-bruker>.github.io/<repo-navn>/`

Følgende undersider blir også publisert:

- `https://<github-bruker>.github.io/<repo-navn>/support/`
- `https://<github-bruker>.github.io/<repo-navn>/personvern/`
- `https://<github-bruker>.github.io/<repo-navn>/vilkar/`

## Demo-år (realistisk)

- I Debug og TestFlight vises en egen seksjon i `Innstillinger > Demo`.
- Velg `Last inn demo (3 år realistisk)` for å fylle appen med 36 måneder data.
- Velg `Tøm alle data` i samme seksjon for å nullstille.

Demo-datasettet inkluderer:
- 36 `BudgetMonth`
- realistiske kategorier/budsjettplaner/transaksjoner (studentprofil i NOK)
- 36 investeringssnapshots (Fond/Aksjer/BSU/Buffer/Krypto)
- mål og preferanser slik at Oversikt ser ferdig ut
