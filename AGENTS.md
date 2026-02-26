# AGENTS.md

Denne filen definerer hvordan Codex skal jobbe med prosjektet **Enkelt Budsjett**.
Mål: høy fart, tydelig kvalitet, små trygge leveranser.

## Prosjektkontekst
- Plattform: iOS (SwiftUI)
- Lagring: SwiftData (offline-first)
- Arkitektur: MVVM per feature
- Domene: Budsjett + Investeringer (snapshots), ingen bankintegrasjon i MVP
- Språk i UI/copy: Norsk

## Standard arbeidsflyt (alltid)
1. Design
- Klargjør mål, brukerflyt, edge cases, tomtilstander, mikrocopy.
- Lås akseptansekriterier før kode.

2. Implement
- Gjør minst mulig, men komplett, endring for å løse oppgaven.
- Flytt logikk til ViewModel/Service ved behov.
- Hold komponenter små og gjenbrukbare.

3. QA
- Kjør rask egenkontroll: build-feil, regressjoner, dark mode, tomtilstander, tilgjengelighet.
- Legg til/oppdater tester for kritisk logikk.

4. Commit
- Ett tema per commit.
- Bruk presis commit-melding med scope (feat/fix/refactor/test/docs).

## Agentprofiler

### 1) Designer-agent
Brukes når oppgaven gjelder UX, informasjonsarkitektur, copy, tomtilstander eller visuell konsistens.

Leveranse:
- Kort problemforståelse
- Foreslått skjermstruktur (topp -> bunn)
- Konkret mikrocopy (norsk)
- Beslutninger og tradeoffs
- Akseptansekriterier

Regler:
- Maks én primær handling per skjerm (med mindre eksplisitt behov)
- Ikke moraliserende språk
- Unngå duplisert informasjon mellom Oversikt og Investeringer

### 2) iOS-agent
Brukes når oppgaven er implementasjon i SwiftUI/SwiftData.

Leveranse:
- Faktiske kodeendringer i riktige mapper
- Oppdatert ViewModel/Service ved forretningslogikk
- Eventuelle migrasjons- eller schema-endringer
- Kort endringslogg med filstier

Regler:
- Unngå stor logikk i View
- Bruk `Button`/`NavigationLink` fremfor `onTapGesture` for handlinger
- Behold eksisterende designsystem (`AppTheme`, formattering)
- Endringer skal være idempotente der data genereres/opprettes

### 3) QA-agent
Brukes når du vil ha kvalitetssikring, review eller testfokus.

Leveranse:
- Funn sortert etter alvorlighet (høy -> lav)
- Reproduksjonssteg
- Foreslått fix
- Testforslag og resterende risiko

Regler:
- Prioriter funksjonelle feil før stil
- Sjekk tomtilstander og 0-data eksplisitt
- Sjekk tilgjengelighet (VoiceOver labels, Dynamic Type, kontrast)

### 4) Release-agent
Brukes før TestFlight/App Store eller ved større samlekutt.

Leveranse:
- Release-sjekkliste
- Risikoer/blokkere
- Forslag til release notes (NO)
- Verifisering av navn/copy/versjonskonsistens

Regler:
- Ingen nye features i release-fasen, kun stabilisering
- Bekreft at debug-only funksjoner er skjult i release
- Bekreft at demo-data-verktøy er kontrollert (kun debug/TestFlight hvis ønsket)

## Hvordan be agentene om jobb
Bruk denne malen i én melding:

- Agent: `Designer-agent | iOS-agent | QA-agent | Release-agent`
- Mål: `<hva skal oppnås>`
- Krav: `<må/skal-regler>`
- Akseptansekriterier: `<hvordan vi vet det er ferdig>`
- Leveranse: `implementer + test + commit` (eller kun spesifikasjon)

Eksempel:
- Agent: iOS-agent
- Mål: Forenkle Budsjett-hero når ingen grenser finnes
- Krav: Vis "Netto hittil", fjern dupliserte coach-kort
- Akseptansekriterier: Ingen store dobbelt-CTA, build uten feil
- Leveranse: Implementer, kjør rask QA, commit

## Commit-standard
- Format: `<type>(<scope>): <kort beskrivelse>`
- Typer: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

Eksempler:
- `feat(budget): innfør gruppegrenser med enkel setup-sheet`
- `fix(investments): hindre duplikat snapshot ved samme periodKey`
- `refactor(overview): flytt beregninger til viewmodel`

## Definition of Done (minimum)
- Funksjon virker som spesifisert
- Ingen nye build-feil
- Ingen åpenbare regressjoner i berørte skjermer
- Tomtilstand + 0-data er håndtert
- Dark mode og light mode ser ryddig ut
- Endringen er commitet med tydelig melding
