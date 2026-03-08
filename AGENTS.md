# AGENTS.md

Denne filen definerer hvordan Codex skal jobbe med prosjektet **Spor økonomi**.

Mål:
- høy fart
- tydelig kvalitet
- små, trygge leveranser

---

# Produktmål

Spor økonomi skal være:

- En enkel og rolig budsjettapp
- Mindre kompleks enn tradisjonelle budsjettverktøy
- Fokus på oversikt fremfor detaljer
- Offline-first og rask

Prioriteter:

1. Klarhet
2. Få steg for å registrere transaksjoner
3. Tydelig økonomisk oversikt
4. Lav kognitiv belastning

Unngå:

- unødvendig kompleksitet
- overfylte skjermer
- duplisert informasjon

---

# Produktposisjonering

Spor økonomi er en enkel budsjettapp for folk som vil forstå økonomien sin uten kompliserte systemer.

Appen skal oppleves som:

- enkel
- rolig
- tydelig
- rask å bruke

Den konkurrerer ikke på flest funksjoner, men på:

- klar oversikt
- enkel registrering
- lav kognitiv belastning

---

# Prosjektkontekst

- Plattform: iOS (SwiftUI)
- Lagring: SwiftData (offline-first)
- Arkitektur: MVVM per feature
- Domene: Budsjett + Investeringer (snapshots)
- Bankintegrasjon: ikke i MVP
- Språk i UI/copy: Norsk

---

# Prosjektstruktur

Appen følger feature-basert struktur.

Eksempel:

Features/
  Budget/
    BudgetView.swift
    BudgetViewModel.swift

  Investments/
    InvestmentsView.swift
    InvestmentsViewModel.swift

Core/
  Services/
  Models/
  Utilities/

DesignSystem/
  AppTheme.swift
  Components/

Regler:

- View og ViewModel ligger i samme featuremappe
- Forretningslogikk ligger i ViewModel eller Service
- Designsystem ligger i `DesignSystem/`
- Utilities skal være små og generiske
- Ikke lag nye toppnivåmapper uten eksplisitt grunn

---

# Kjerneprinsipper

- Gjør minste komplette endring som løser oppgaven.
- Behold logikk i ViewModel eller Service, ikke i View.
- Bevar eksisterende designsystem, navngiving og formattering.
- Ikke bland flere temaer i samme commit.

En oppgave kan ikke markeres som ferdig uten:

- build-status
- verifikasjonsrapport
- eksplisitt liste over hva som ikke ble verifisert

---

# SwiftUI-regler

Views skal være presentasjonslag.

Regler:

- Unngå kompleks logikk i `body`
- Flytt beregninger til ViewModel
- Maks én hovedoppgave per View

State-regler:

- `@State` -> lokal UI-state
- `@StateObject` -> ViewModel
- `@Environment` -> kun når nødvendig

Ytelse:

- Ikke gjør tunge beregninger i `body`
- Bruk computed properties i ViewModel

---

# Anti-hallusinasjonsregler

AI skal ikke:

- introdusere nye dependencies uten eksplisitt forespørsel
- endre arkitektur uten begrunnelse
- oppfinne APIer eller services som ikke finnes
- refaktorisere store deler av kodebasen uten instruks

Hvis noe er uklart:

- stopp
- still spørsmål
- ikke gjett

---

# Standard arbeidsflyt

## 1. Design

- Klargjør mål
- Definer brukerflyt
- Identifiser edge cases
- Definer tomtilstander
- Skriv mikrocopy

Akseptansekriterier skal være låst før kode.

---

## 2. Implement

- Gjør minste komplette endring
- Flytt logikk til ViewModel eller Service
- Hold komponenter små og lesbare
- Sørg for idempotens når data opprettes automatisk

---

## 3. QA

Verifiser:

- build
- regressjoner
- tomtilstander
- dark mode
- light mode
- tilgjengelighet

Rapporter eksplisitt:

- hva som ble verifisert
- hva som ikke ble verifisert

---

## 4. Commit

Regler:

- ett tema per commit
- presis commit-melding
- ikke commit halvferdig arbeid uten checkpoint

---

# AI-sikker arbeidsflyt

Skriv tester før implementasjon når oppgaven endrer:

- forretningslogikk
- dato-regler
- import/eksport
- onboarding
- mål
- challenges
- faste poster

Ved bugfix:

1. skriv test som reproducerer feilen
2. verifiser at testen feiler
3. implementer fix

---

# TDD-regel

Red
Test beskriver ønsket oppførsel og feiler.

Green
Implementer minste kode for å få testen grønn.

Refactor
Rydd kode uten å endre oppførsel.

---

# Standardinstruksjon til AI ved logikkarbeid

Skriv først tester som beskriver ønsket oppførsel.
Implementer deretter minimal kode for å få testene grønne.
Ikke endre eksisterende tester uten å forklare hvorfor.
Hvis testen er feil: stopp og forklar før du endrer den.

---

# Når bruke hvilken agent

## Designer-agent

Bruk for:

- UX
- informasjonsarkitektur
- skjermhierarki
- brukerflyt
- mikrocopy
- tomtilstander

Leveranse:

- problemforståelse
- skjermstruktur
- mikrocopy
- tradeoffs
- akseptansekriterier

Regler:

- maks én primær handling per skjerm
- ikke moraliserende språk
- unngå duplisert informasjon mellom Oversikt og Investeringer

---

## iOS-agent

Bruk for implementasjon i:

- SwiftUI
- Swift
- SwiftData

Leveranse:

- kodeendringer
- oppdatert ViewModel eller Service
- migrasjoner ved behov
- endringslogg
- verifikasjonsstatus

Regler:

- unngå logikk i View
- bruk `Button` eller `NavigationLink`
- behold designsystem (`AppTheme`)
- dataoperasjoner skal være idempotente
- utilities skal være små og gjenbrukbare

---

## QA-agent

Bruk for:

- review
- teststrategi
- kvalitetssikring før commit eller release

Leveranse:

- funn sortert etter alvorlighet
- reproduksjonssteg
- foreslått fix
- testforslag
- resterende risiko

Regler:

- prioriter funksjonelle feil
- sjekk tomtilstander
- sjekk tilgjengelighet
- skill mellom bekreftede feil, sannsynlige feil og kodegjeld

---

## Release-agent

Bruk før:

- TestFlight
- App Store
- større samlekutt

Leveranse:

- release-sjekkliste
- risikoer
- blokkere
- release notes

Regler:

- ingen nye features
- kun stabilisering
- bekreft at debug-verktøy er skjult
- rapporter også hva som ikke er verifisert

---

## Growth-agent

Bruk når oppgaven gjelder:

- produktposisjonering
- App Store optimalisering (ASO)
- onboarding-copy og aktivering
- brukeranskaffelse
- retention og produktvekst
- lanseringsstrategi
- eksperimenter for vekst

Mål:

Hjelpe Spor økonomi med å vokse gjennom tydelig kommunikasjon, enkel onboarding og datadrevne forbedringer.

Growth-agent skal fokusere på:

- klar verdi for brukeren
- enkel forklaring av produktet
- høy aktivering etter installasjon
- realistiske eksperimenter for en solo-utvikler

Leveranse:

- problemforståelse
- vekstidé eller forbedring
- konkret forslag til implementasjon
- forslag til eksperiment eller måling
- forventet effekt
- akseptansekriterier

Regler:

- foreslå små, testbare forbedringer
- unngå generisk markedsføringsspråk
- prioriter klarhet over hype
- løsninger må være realistiske for et lite produktteam
- ikke foreslå komplekse kampanjer eller paid marketing uten eksplisitt forespørsel

Eksempler på oppgaver:

- forbedre App Store-beskrivelse
- foreslå onboarding-flow
- forbedre første brukeropplevelse
- foreslå virale mekanismer eller deling
- formulere verdiforslag
- foreslå enkle veksteksperimenter

---

# Obligatoriske QA-sjekkpunkter

Alle relevante endringer skal sjekke:

- build-status
- tomtilstand
- 0-data
- dark mode
- light mode
- tilgjengelighet
- dato-kanttilfeller
- idempotens

---

# Testkrav per type endring

UI-copy eller layout
-> manuell QA

ViewModel / service-logikk
-> enhetstest

Bugfix
-> reproduksjonstest

Import/eksport, onboarding, reminders, mål, challenges
-> tester obligatoriske

Dataflyt på tvers av lag
-> integrasjonstest eller smoke-test

---

# Hvordan be agentene om jobb

Bruk én melding:

Agent: Designer-agent | iOS-agent | QA-agent | Release-agent | Growth-agent
Mål: <hva skal oppnås>
Krav: <må/skal-regler>
Akseptansekriterier: <hvordan vi vet det er ferdig>
Leveranse: implementer + test + commit | kun spesifikasjon

Eksempel:

Agent: iOS-agent
Mål: Forenkle Budsjett-hero når ingen grenser finnes
Krav: Vis "Netto hittil", fjern dupliserte coach-kort
Akseptansekriterier: Ingen store dobbelt-CTA, build uten feil
Leveranse: Implementer, kjør rask QA, commit

---

# Forventet svarformat

Design
-> løsning -> struktur -> copy -> akseptansekriterier

Implementasjon
-> endringer -> filer -> verifikasjon

QA
-> funn -> reproduksjon -> fix

Release
-> sjekkliste -> blokkere -> release notes

---

# Commit-standard

Format:

<type>(<scope>): <kort beskrivelse>

Typer:

- feat
- fix
- refactor
- test
- docs
- chore

Eksempler:

feat(budget): innfør gruppegrenser med enkel setup-sheet
fix(investments): hindre duplikat snapshot ved samme periodKey
refactor(overview): flytt beregninger til viewmodel
docs(agents): stram inn arbeidskontrakt

---

# Definition of Done

En oppgave er ferdig når:

- funksjonen virker som spesifisert
- ingen nye build-feil
- ingen åpenbare regressjoner
- tomtilstand er håndtert
- dark mode og light mode er ryddige
- relevante tester er lagt til
- endringen er commitet med tydelig melding

---

# Arbeidsmodus for Codex

Når en oppgave mottas:

1. forstå oppgaven
2. identifiser riktig agent
3. bekreft akseptansekriterier
4. lag plan
5. implementer minste komplette løsning
6. verifiser
7. rapporter verifikasjon
8. commit

Hvis oppgaven er uklar:

- stopp
- still spørsmål
- ikke gjett


# SAFE CHANGE RULES

Codex skal gjøre trygge, avgrensede endringer.

## Endringsomfang

- Endre kun filer som er nødvendige for oppgaven.
- Ikke gjør opportunistisk refaktorering uten eksplisitt beskjed.
- Ikke rydd i urelatert kode i samme endring.
- Ikke endre navn på typer, filer eller mapper uten tydelig grunn.

## Filer utenfor scope

Ikke endre filer utenfor oppgavens scope med mindre:

1. endringen er nødvendig for at løsningen skal bygge eller fungere
2. årsaken forklares eksplisitt i endringsloggen

Hvis en fil utenfor scope må endres:

- forklar hvorfor
- hold endringen minimal
- oppgi den eksplisitt i leveransen

## Beskytt eksisterende oppførsel

- Bevar eksisterende oppførsel med mindre oppgaven eksplisitt ber om at den skal endres.
- Ikke endre business rules, standardverdier eller formattering uten grunn.
- Ikke fjern eksisterende edge case-håndtering uten å bevise at den er feil eller overflødig.

## UI-sikkerhet

- Ikke gjør store layoutendringer når oppgaven gjelder liten copy- eller logikkjustering.
- Ikke bytt komponenttype, navigasjonsmønster eller hierarki uten eksplisitt behov.
- Behold eksisterende visuell stil, spacing og komponentbruk så langt det er mulig.

## Modell- og datalagsikkerhet

- Ikke endre SwiftData-modeller, schema eller persistenslogikk uten eksplisitt behov.
- Ved modellendringer: forklar migrasjonskonsekvenser.
- Ikke introduser risiko for duplikater, ikke-idempotent oppførsel eller datatap.

## Testsikkerhet

- Ikke endre eksisterende tester kun for å få grønt.
- Hvis en test må endres, forklar:
  - hvorfor testen var feil eller utdatert
  - hvorfor ny oppførsel er riktig
- Nye tester skal beskrive faktisk ønsket oppførsel, ikke implementasjonsdetaljer.

## Refaktoreringssikkerhet

Refaktorering er kun tillatt når:

- den er direkte nødvendig for oppgaven
- den reduserer kompleksitet i berørt område
- den ikke utvider scope unødvendig

Ved refaktorering:

- hold samme oppførsel
- unngå store flyttinger av kode
- del opp i små steg hvis mulig

## Verifikasjon ved trygg endring

For alle endringer skal Codex eksplisitt oppgi:

- hvilke filer som ble endret
- hvorfor hver fil ble endret
- hvilke filer som ble vurdert, men ikke endret
- hva som ble verifisert
- hva som ikke ble verifisert

## Stopp-regler

Codex skal stoppe og be om avklaring hvis:

- oppgaven krever store endringer i arkitektur
- flere mulige tolkninger gir ulik produktoppførsel
- endringen påvirker modeller, migrasjoner eller kritisk dataflyt
- løsningen krever endringer i mange filer uten klart scope
