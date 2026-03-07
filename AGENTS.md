# AGENTS.md

Denne filen definerer hvordan Codex skal jobbe med prosjektet **Spor økonomi**.
Mål: høy fart, tydelig kvalitet, små trygge leveranser.

## Prosjektkontekst
- Plattform: iOS (SwiftUI)
- Lagring: SwiftData (offline-first)
- Arkitektur: MVVM per feature
- Domene: Budsjett + Investeringer (snapshots), ingen bankintegrasjon i MVP
- Språk i UI/copy: Norsk

## Kjerneprinsipper
- Gjør minste komplette endring som løser oppgaven.
- Behold logikk i ViewModel eller Service, ikke i View, med mindre det er ren presentasjon.
- Bevar eksisterende designsystem, navngiving og formattering med mindre oppgaven eksplisitt sier noe annet.
- Ikke bland flere temaer i samme commit.
- Ikke kall noe "ferdig" uten at relevant verifikasjon er gjort og rapportert.

## Standard arbeidsflyt
1. Design
- Klargjør mål, brukerflyt, edge cases, tomtilstander og mikrocopy.
- Lås akseptansekriterier før kode.
- Avklar om oppgaven primært er design, implementasjon, QA eller release.

2. Implement
- Gjør minst mulig, men komplett, endring for å løse oppgaven.
- Flytt logikk til ViewModel eller Service ved behov.
- Hold komponenter små, lesbare og gjenbrukbare.
- Sørg for at dataopprettelse og automatiske operasjoner er idempotente.

3. QA
- Kjør rask egenkontroll for build-feil, regressjoner, tomtilstander, dark mode, light mode og tilgjengelighet.
- Legg til eller oppdater tester for kritisk logikk.
- Rapporter eksplisitt hva som faktisk ble verifisert, og hva som ikke ble verifisert.

4. Commit
- Ett tema per commit.
- Bruk presis commit-melding med scope.
- Ikke commit halvferdig arbeid med mindre brukeren ber om checkpoint.

## AI-sikker arbeidsflyt
- Skriv tester før implementasjon når oppgaven endrer forretningslogikk, dato-regler, import/eksport, onboarding, mål, challenges eller faste poster.
- Ved bugfix: skriv først en test som reproducerer feilen, og verifiser at den feiler før koden endres når det er praktisk mulig.
- Be AI bygge mot eksplisitte akseptansekriterier og tester, ikke mot vag tekst som "gjør dette ferdig".
- Ikke aksepter løsninger som kun gjør tester grønne ved å hardkode verdier, omgå logikk eller sette flagg ukritisk.
- Ikke endre eksisterende tester for å få grønt uten en konkret forklaring på hvorfor testen var feil eller utdatert.
- Foretrekk minimal implementasjon som får testene til å passere, og refaktorer først etter grønn status.
- For kritiske flyter skal det finnes minst én realistisk smoke-, integrasjons- eller ende-til-ende-verifisering i tillegg til enhetstester.

Praktisk regel:
- Red: test beskriver ønsket oppførsel og feiler.
- Green: implementer minste endring som gjør testen grønn.
- Refactor: rydd kode uten å endre oppførsel.

Standardformulering til AI ved logikkarbeid:
- "Skriv først tester som beskriver ønsket oppførsel."
- "Implementer deretter minimal kode for å få testene grønne."
- "Ikke endre eksisterende tester uten å forklare hvorfor."
- "Hvis testen er feil, stopp og forklar det før du endrer den."

## Når bruke hvilken agent

### Designer-agent
Bruk når oppgaven gjelder:
- UX, informasjonsarkitektur, skjermhierarki eller brukerflyt
- copy, mikrocopy eller tomtilstander
- visuell konsistens, CTA-prioritering eller forenkling av skjerm

Leveranse:
- Kort problemforståelse
- Foreslått skjermstruktur fra topp til bunn
- Konkret mikrocopy på norsk
- Beslutninger og tradeoffs
- Akseptansekriterier

Regler:
- Maks én primær handling per skjerm, med mindre behovet er eksplisitt
- Ikke moraliserende språk
- Unngå duplisert informasjon mellom Oversikt og Investeringer

### iOS-agent
Bruk når oppgaven er implementasjon i SwiftUI, Swift eller SwiftData.

Leveranse:
- Faktiske kodeendringer i riktige mapper
- Oppdatert ViewModel eller Service ved forretningslogikk
- Eventuelle migrasjons- eller schema-endringer
- Kort endringslogg med filstier
- Reell verifikasjonsstatus

Regler:
- Unngå stor logikk i View
- Bruk `Button` eller `NavigationLink` fremfor `onTapGesture` for handlinger
- Behold eksisterende designsystem (`AppTheme`, formattering)
- Endringer skal være idempotente der data genereres eller opprettes
- Nye hjelpetyper og utilities skal være små og gjenbrukbare

### QA-agent
Bruk når du vil ha review, testfokus eller kvalitetssikring før release eller commit.

Leveranse:
- Funn sortert etter alvorlighet, høy til lav
- Reproduksjonssteg
- Foreslått fix
- Testforslag
- Resterende risiko

Regler:
- Prioriter funksjonelle feil før stil og kodeform
- Sjekk tomtilstander og 0-data eksplisitt
- Sjekk tilgjengelighet: VoiceOver-labels, Dynamic Type og kontrast
- Skill tydelig mellom bekreftede feil, sannsynlige feil og kodegjeld
- Hvis ingen funn oppdages, si det eksplisitt og oppgi gjenværende risiko

### Release-agent
Bruk før TestFlight, App Store eller større samlekutt.

Leveranse:
- Release-sjekkliste
- Risikoer og blokkere
- Forslag til release notes på norsk
- Verifisering av navn, copy og versjonskonsistens

Regler:
- Ingen nye features i release-fasen, kun stabilisering
- Bekreft at debug-only funksjoner er skjult i release
- Bekreft at demo-data-verktøy er kontrollert
- Løft frem hva som ikke er verifisert, ikke bare hva som ser bra ut

## Obligatoriske QA-sjekkpunkter
Disse skal vurderes for alle relevante endringer:
- Build-status eller eksplisitt grunn til at build ikke ble kjørt
- Tomtilstand og 0-data
- Mørk og lys modus på berørte skjermer
- Tilgjengelighet for berørte kontroller
- Dato- og periodekanttilfeller der funksjonen bruker dato
- Idempotens når data genereres, importeres eller opprettes automatisk

## Testkrav per type endring
- Ren UI-copy eller layoutjustering: manuell QA er ofte nok
- ViewModel- eller service-logikk: enhetstest forventes
- Bugfix i logikk: reproduksjonstest forventes
- Import/eksport, onboarding, reminders, mål, challenges, faste poster: tester er obligatoriske
- Dataflyt på tvers av flere lag: legg til minst én integrasjonstest eller realistisk smoke-test hvis mulig

## Hvordan be agentene om jobb
Bruk denne malen i én melding:

- Agent: `Designer-agent | iOS-agent | QA-agent | Release-agent`
- Mål: `<hva skal oppnås>`
- Krav: `<må/skal-regler>`
- Akseptansekriterier: `<hvordan vi vet det er ferdig>`
- Leveranse: `implementer + test + commit` eller `kun spesifikasjon`

Eksempel:
- Agent: iOS-agent
- Mål: Forenkle Budsjett-hero når ingen grenser finnes
- Krav: Vis "Netto hittil", fjern dupliserte coach-kort
- Akseptansekriterier: Ingen store dobbelt-CTA, build uten feil
- Leveranse: Implementer, kjør rask QA, commit

## Forventet svarformat fra agentene
- Design: løsning først, deretter struktur, copy og akseptansekriterier
- Implementasjon: hva som ble endret, hvilke filer som ble berørt, hvordan det ble verifisert
- QA/review: funn først, sortert etter alvorlighet, med reproduksjon og foreslått fix
- Release: sjekkliste, blokkere, release notes og åpen risiko

## Commit-standard
- Format: `<type>(<scope>): <kort beskrivelse>`
- Typer: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

Eksempler:
- `feat(budget): innfør gruppegrenser med enkel setup-sheet`
- `fix(investments): hindre duplikat snapshot ved samme periodKey`
- `refactor(overview): flytt beregninger til viewmodel`
- `docs(agents): stram inn arbeidskontrakt`

## Definition of Done
- Funksjonen virker som spesifisert
- Ingen nye build-feil, eller tydelig forklart hvorfor build ikke ble kjørt
- Ingen åpenbare regressjoner i berørte skjermer
- Tomtilstand og 0-data er håndtert der det er relevant
- Dark mode og light mode ser ryddig ut der det er relevant
- Relevante tester er lagt til eller oppdatert
- Endringen er commitet med tydelig melding
