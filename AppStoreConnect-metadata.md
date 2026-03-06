# App Store Connect – juridiske metadata (Enkelt Budsjett)

Sist oppdatert: 2026-03-06

## 1) Required URL-er

Disse feltene må fylles i App Store Connect:

- Privacy Policy URL: `https://nithusan2002.github.io/Enkelt-Budsjett/personvern/`
- Support URL: `https://nithusan2002.github.io/Enkelt-Budsjett/support/`
- Marketing URL (valgfritt): `https://nithusan2002.github.io/Enkelt-Budsjett/`

Hvis dere senere kobler et eget domene til GitHub Pages, oppdater disse URL-ene samtidig.

## 2) Kontaktinfo (App Review Contact)

- E-post: `sporokonomi.app@gmail.com`
- Fornavn: `Nithusan`
- Etternavn: `___Fyll inn___`
- Telefon: `___Fyll inn___`

## 3) App Privacy (spørreskjema)

Tidligere notat med `None` er ikke lenger trygt hvis konto-flyten med e-post er med i builden.

For nåværende kodebase må App Privacy gjennomgås slik:

- Data Used to Track You: `No`
- Tracking (ATT): `No`

Hvis konto/innlogging sendes med i release-build:

- Data Linked to You:
  - `Contact Info > Email Address`
  - `Contact Info > Name` (hvis brukeren oppgir visningsnavn ved registrering)
  - `Identifiers > User ID`
- Formål: `App Functionality`

Hvis konto-flyten fjernes helt fra release-build før innsending, vurder skjemaet på nytt før dere sender inn.

Foreløpig vurdering for øvrig dataflyt:

- Budsjettdata, mål, transaksjoner og innstillinger lagres lokalt i appen.
- Hvis iCloud-synk er aktiv, kan data synkroniseres via CloudKit i brukerens Apple-konto.
- Ingen tredjepartsannonser eller tredjepartssporing er funnet.

Begrunnelse for gjennomgangen:

- Kodebasen har aktiv konto-flyt med e-postregistrering/innlogging via Supabase.
- `UserPreference` lagrer bruker-ID, e-post og valgfritt visningsnavn lokalt.
- Ingen analytics- eller tracking-SDK-er er funnet i kodebasen.

## 4) Når denne må oppdateres

Oppdater App Privacy og `PrivacyInfo.xcprivacy` umiddelbart hvis dere legger til:

- tredjeparts analytics/crash SDK
- annonser eller tracking
- backend som samler inn brukerdata
- nye Required Reason API-kategorier
- endringer i konto- eller autentiseringsflyten
