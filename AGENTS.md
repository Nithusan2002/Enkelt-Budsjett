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

# UI consistency system

Mål:
- gjøre appen mer symmetrisk uten å gjøre skjermene monotone
- sikre at Budsjett, Investeringer og Mål føles som samme produktfamilie
- standardisere mønstre for hero, seksjoner, forms og handlinger

Prinsipp:
- del visuell logikk og komponentmønstre
- varier informasjonsprioritet per feature
- standardiser struktur før dekor

## 1. Hero-regel

Alle hovedskjermer skal ha et hero-kort øverst når skjermen har ett tydelig hovedtall eller hovedstatus.

Hero-kortet skal som standard ha:
- liten label
- ett hovedtall eller hovedstatus
- én sekundær statuslinje
- eventuelt én lavprioritert metadata-linje

Hero-kort skal dele samme visuelle shell:
- lik hjørneradius
- lik intern padding
- subtil gradient
- myk shadow
- samme border/stroke-logikk

Innholdet skal fortsatt være feature-spesifikt:
- Budsjett skal være mer operativt og handlingsnært
- Investeringer skal være mer status- og utviklingsdrevet
- Mål skal være mer fokusert og enkelt

## 2. Seksjonsheader-regel

Alle større seksjoner skal bruke samme grunnmønster:
- venstre: seksjonstittel
- høyre: én sekundær handling hvis relevant

Eksempler:
- `Beholdning` + `+`
- `Grupper` + `Rediger`
- `Historikk` + `Se alle`

Regler:
- seksjonsspesifikke handlinger skal ligge i header når de naturlig hører til seksjonen
- unngå å plassere lokale admin-handlinger nederst i skjermen hvis de kan ligge i header
- høyrehandlingen skal være liten, tydelig og sekundær

## 3. Primær CTA-regel

Hver hovedskjerm skal ha maks én tydelig primær CTA.

Regler:
- bruk floating CTA kun når handlingen er sentral for skjermen
- copy skal alltid være feature-spesifikk
- basestil kan være delt, men tekst og accessibility-label skal aldri være hardkodet til en annen feature
- primær CTA skal ikke konkurrere med lokale seksjonshandlinger

## 4. Form-regel

Alle opprett- og rediger-skjermer skal bruke samme grunnstruktur:
- tydelig skjermtittel
- kort hjelpetekst kun ved behov
- labels over felter
- jevn vertikal spacing
- én tydelig lagrehandling

Unngå:
- dobbeltoverskrifter som sier nesten det samme
- felt uten tydelig label
- blanding av ulike datovisninger eller inputmønstre i samme form

## 5. Kort-regel

Kort skal brukes for å gruppere informasjon, ikke bare som dekor.

Kort skal være konsistente på tvers av appen:
- samme radiusfamilie
- samme border-logikk
- samme shadow-nivå per korttype
- samme padding-prinsipper

Ikke introduser nye kortstiler uten tydelig funksjonell grunn.

## 6. Typografi-regel

Det skal være tydelig hva som er viktigst på skjermen.

Regler:
- ett hovedtall per skjerm får sterkest visuell vekt
- seksjonstitler skal bruke konsistent størrelse og vekt
- metadata og hjelpetekst skal bruke sekundært nivå
- ikke la flere elementer konkurrere om å være hovedfokus

## 7. Tomtilstandsregel

Alle tomtilstander skal være korte og konkrete:
- hva mangler
- hva kan brukeren gjøre nå

Regler:
- én anbefalt handling er nok
- ikke bruk flere coach-kort samtidig
- unngå moraliserende språk

## 8. Handlingshierarki-regel

Handlingshierarki skal være tydelig:
- primær handling: visuelt tydelig og unik
- sekundære handlinger: små og lokale
- administrative handlinger: nedtonet eller flyttet til riktig seksjonsnivå
- destruktive handlinger: vises bare når konteksten er tydelig

## 9. Språk- og formatregel

All UI-copy skal være norsk.

Regler:
- bruk norsk datoformat konsekvent
- bruk konsekvent pengebeløp-format
- unngå blanding av norsk og engelsk i labels, datoer og hjelpetekst

## 10. Feature-familie-regel

Budsjett, Investeringer og Mål skal føles som samme app.

Det betyr:
- samme designlogikk
- samme komponentfamilie
- samme handlingshierarki
- men ulik informasjonsprioritet per feature

Målet er ikke identiske skjermer, men gjenkjennelig struktur og rytme.

Prioriter standardisering i denne rekkefølgen:
1. hero-kort
2. seksjonsheadere
3. primær CTA
4. formskjermer
5. tomtilstander

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

# Cost-aware execution rules

Mål:
Bruk Codex effektivt og unngå unødvendig token- og kreditbruk.

### Standard arbeidsmåte
- Foretrekk små, avgrensede oppgaver fremfor store brede oppgaver.
- Endre kun filer som er nødvendige for oppgaven.
- Ikke gjør opportunistisk refaktorering.
- Ikke skann hele repoet hvis oppgaven gjelder én skjerm eller én feature.

### Før implementasjon
- Start med en kort plan.
- Identifiser hvilke filer som sannsynligvis må endres før kode skrives.
- Hvis scope er uklart: stopp og be om avklaring i stedet for å gjette.

### Build policy
- Ikke bygg Xcode-prosjektet for rene copy-endringer, spacing, farger eller små UI-justeringer.
- Ikke bygg prosjektet for små visuelle endringer som er isolert til én View, med mindre det er høy risiko for compile-feil.
- Bygg prosjektet når:
  - ViewModel er endret
  - SwiftData-modeller eller schema er endret
  - navigasjon er endret
  - nye filer eller nye typer er introdusert
  - avhengigheter mellom filer er endret
  - logikk for beregninger eller dataflyt er endret

### Verifikasjon før build
Før build vurderes skal agenten:
- gjøre en manuell compile-risk-vurdering
- se etter åpenbare typefeil, manglende imports, ugyldige kall, rename-konflikter og binding-feil
- rapportere om endringen virker lav, medium eller høy risiko

### Test policy
- Ikke skriv eller kjør unødvendige tester for ren copy eller små layoutendringer.
- Skriv tester når oppgaven endrer logikk, dato-regler, dataflyt, import/eksport, onboarding, mål, challenges eller faste poster.
- Ved bugfix i logikk: prioriter reproduksjonstest først.

### Token-effektiv responsstil
Når agenten svarer:
- vær kort og konkret
- ikke gjenta hele problemet
- ikke forklar grunnleggende SwiftUI-konsepter med mindre det blir bedt om
- ikke dump store mengder kode som ikke er endret
- vis kun relevante filer og relevante endringer

### Scope control
- Hvis oppgaven gjelder én skjerm, jobb kun i den skjermen og nærmeste relevante ViewModel/Service.
- Ikke les eller vurder urelaterte features.
- Ikke foreslå større arkitekturendringer med mindre brukeren ber om det eksplisitt.

### Change batching
- Foretrekk én tydelig oppgave per kjøring.
- Ikke kombiner designforbedring, refaktorering, ny feature og bugfix i samme oppgave.
- Del heller opp i små steg.

### Når agenten skal stoppe
Stopp og be om avklaring hvis:
- oppgaven krever gjennomgang av mange filer
- flere tolkninger gir ulik produktoppførsel
- løsningen krever stor refaktorering
- build/test virker nødvendig, men kostnaden er høy og nytten er uklar

### Standard leveranseformat
- Plan
- Endrede filer
- Kort forklaring på hva som ble gjort
- Verifikasjon
- Om prosjektet ikke ble bygget: forklar hvorfor

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
