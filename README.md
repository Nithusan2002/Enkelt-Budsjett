# Enkelt Budsjett

En offline-first iOS-app bygget i SwiftUI + SwiftData for:
- budsjettsporing
- investeringsoversikt (månedlige snapshots)
- enkel måloppfølging

## Kjør lokalt

1. Åpne `Simple Budget - Budskjett planlegger gjort enkelt.xcodeproj` i Xcode.
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
