# Enkelt Budsjett

En offline-first iOS-app bygget i SwiftUI + SwiftData for:
- budsjettsporing
- investeringsoversikt (månedlige snapshots)
- enkel måloppfølging

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
- Eksport av data (JSON) er tilgjengelig fra `Innstillinger > Data`.

## Demo-år (realistisk)

- I Debug og TestFlight vises en egen seksjon i `Innstillinger > Demo`.
- Velg `Last inn demo (3 år realistisk)` for å fylle appen med 36 måneder data.
- Velg `Tøm alle data` i samme seksjon for å nullstille.

Demo-datasettet inkluderer:
- 36 `BudgetMonth`
- realistiske kategorier/budsjettplaner/transaksjoner (studentprofil i NOK)
- 36 investeringssnapshots (Fond/Aksjer/BSU/Buffer/Krypto)
- mål og preferanser slik at Oversikt ser ferdig ut
