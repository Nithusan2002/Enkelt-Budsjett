# Spor økonomi

Spor økonomi er en enkel og rolig iOS-app for personlig økonomi, bygget med SwiftUI og SwiftData.

Appen er laget for brukere som vil forstå hva de har igjen denne måneden uten komplisert oppsett, tunge budsjettsystemer eller bankintegrasjon i MVP.

## Status

Dette finnes i appen nå:

- onboarding med kort flyt til første oversikt
- valg mellom lokal bruk og konto
- budsjett med inntekt, utgifter, manuell sparing og gruppegrenser
- faste poster med månedlig auto-opprettelse
- oversikt med netto denne måneden, mål og spart hittil i år
- investeringsoversikt med månedlige snapshots
- eksport og import av data
- innstillinger for personvern, visning, lagring og konto
- demo-verktøy for debug og sandbox/TestFlight

## Produktretning

Spor økonomi skal være:

- enkel
- rolig
- tydelig
- rask å bruke

Kjerneverdi:

`Se hva du har igjen denne måneden.`

## Teknologi

- iOS app i SwiftUI
- lokal lagring med SwiftData
- feature-basert struktur
- offline-first som utgangspunkt
- valgfri autentisering via Supabase-oppsett når konfigurert

## Prosjektstruktur

Viktige mapper:

- `SporOkonomi/App` appstart, session state og root-navigation
- `SporOkonomi/Features` feature-flater som Oversikt, Budsjett, Investeringer, Onboarding og Innstillinger
- `SporOkonomi/Domain` modeller og tjenester
- `SporOkonomi/Shared` tema, utilities og delt UI-logikk
- `SporOkonomiTests` enhetstester
- `docs` statisk launch-side og juridiske sider for publisering

## Kjør lokalt

1. Åpne `SporOkonomi.xcodeproj` i Xcode.
2. Velg scheme `SporOkonomi`.
3. Velg simulator eller fysisk enhet.
4. Kjør appen med `Cmd + R`.

## Test og verifikasjon

Repoet inneholder enhetstester for blant annet:

- onboarding
- oversikt
- budsjett
- investeringer
- tilbakevendende poster og demo-data
- import
- auth/session-flyt

## Data og personvern

- appen lagrer data lokalt på enheten som standard
- ingen bankintegrasjon i MVP
- eksport og import av data er tilgjengelig fra innstillinger
- juridiske tekster finnes både som publiserte sider i `docs/` og kildetekster i `docs/legal/`

Relevante filer:

- `docs/legal/personvern-no.md`
- `docs/legal/vilkar-no.md`
- `SporOkonomi/PrivacyInfo.xcprivacy`

## Launch-side og GitHub Pages

Repoet inneholder en statisk launch-side i `docs/`.

Publiser med GitHub Pages:

1. Push repoet til GitHub.
2. Gå til `Settings > Pages`.
3. Velg `Deploy from a branch`.
4. Velg branch `main` og mappe `/docs`.

Undersider i `docs/`:

- `support/`
- `personvern/`
- `vilkar/`

## Demo-data

Appen har demo-verktøy for å fylle appen med realistiske data.

- i Debug er demo-verktøy tilgjengelige i innstillinger
- i sandbox/TestFlight vises de også via StoreKit-basert miljøsjekk
- demo-seeding kan brukes for QA, previews og markedsføringsbilder

Eksisterende demo-data dekker blant annet:

- budsjettmåneder
- transaksjoner
- faste poster
- investeringssnapshots
- mål og preferanser

## Begrensninger akkurat nå

- bankintegrasjon er ikke del av MVP
- launch-siden bruker fortsatt manuell GitHub Pages-publisering
- full release-klargjøring av App Store-materiale pågår fortsatt

## Lisens

Dette repoet er offentlig for portfolio-, lærings- og evalueringsformål.

Koden, designressurser og produktmateriell er ikke lisensiert for gjenbruk, distribusjon eller kommersiell bruk uten skriftlig tillatelse.

Se `LICENSE` for detaljer.

## Relaterte filer

- `AGENTS.md` arbeidskontrakt og prosjektregler for agenter
- `AppStoreConnect-metadata.md` App Store-arbeidsnotater
