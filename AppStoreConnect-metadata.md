# App Store Connect – juridiske metadata (Enkelt Budsjett)

Sist oppdatert: 2026-02-28

## 1) Required URL-er

Disse feltene må fylles i App Store Connect:

- Privacy Policy URL: `https://simplebudget.app/personvern`
- Support URL: `https://simplebudget.app/support`
- Marketing URL (valgfritt): `https://simplebudget.app`

## 2) Kontaktinfo (App Review Contact)

- E-post: `hei@simplebudget.app`
- Fornavn: `Nithusan`
- Etternavn: `___Fyll inn___`
- Telefon: `___Fyll inn___`

## 3) App Privacy (spørreskjema)

Sett følgende i App Store Connect for nåværende MVP:

- Data Used to Track You: `No`
- Data Linked to You: `None`
- Data Not Linked to You: `None`
- Tracking (ATT): `No`

Begrunnelse for denne utfyllingen i nåværende app:

- Ingen tredjepartsannonser eller tredjepartssporing.
- Ingen app-analytics SDK-er funnet i kodebasen.
- Data lagres lokalt (SwiftData) og i iCloud/CloudKit for brukers egen synk.

## 4) Når denne må oppdateres

Oppdater App Privacy og `PrivacyInfo.xcprivacy` umiddelbart hvis dere legger til:

- tredjeparts analytics/crash SDK
- annonser eller tracking
- backend som samler inn brukerdata
- nye Required Reason API-kategorier
