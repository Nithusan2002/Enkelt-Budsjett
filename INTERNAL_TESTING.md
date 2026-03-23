# Intern TestFlight-sjekkliste

Bruk denne før hver intern TestFlight-build.

## Før upload

- bekreft at builden er grønn
- bekreft at AI og premium ikke er synlige i vanlig brukerflyt
- bekreft at ingen `kommer snart`-flater er tilgjengelige fra kjerneopplevelsen

## Smoke-test i appen

Kjør denne rekkefølgen på én faktisk testbuild:

1. onboarding
2. fortsett uten konto
3. konto-flyt hvis den skal testes i denne builden
4. legg til første transaksjon
5. sjekk Oversikt
6. åpne Budsjett
7. åpne Investeringer
8. test eksport/import
9. test varsler og Face ID hvis relevant

## What to Test

Bruk korte noter i TestFlight. Standardtekst:

> Test onboarding, første registrering, Oversikt, Budsjett, Investeringer og Innstillinger. Si gjerne fra hvis noe er uklart, tungvint eller ikke fungerer som forventet.

## Fokus for første interne runde

- onboarding og førsteinntrykk
- første registrering
- om Oversikt er lett å forstå
- om noe er uklart eller tungvint

## Kategoriser feedback

- blocker
- bug
- uklarhet
- forbedringsønske
- nice-to-have

## Prioritering mellom builds

Maks tre forbedringer per runde:

1. blokkere og krasj
2. uklar kjerneflyt
3. friksjon i første verdi
4. små copy- og UX-justeringer
