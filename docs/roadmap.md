# Roadmapa przebudowy

Cel: 100% parytetu z obecnym UI Dzienniczka Szpontniczek, natywnie w SwiftUI,
na iOS 26+, z Liquid Glass i bez pozostałości Kotlina.

## Decyzje

| Obszar | Decyzja |
| --- | --- |
| Logowanie | wyłącznie eduVULCAN (Prometheus + Hebe CE) |
| Zakres | ekrany obecnej aplikacji; ukryte endpointy tylko jako warstwa API |
| System | iOS 26.0+, iPhone, pion |
| Język | polski |
| Repozytorium | ta sama historia, gałąź `swift` |
| Dystrybucja | niepodpisane IPA z GitHub Actions + Sideloadly |
| Bundle ID | com.iwo24pl.eduexpose |

## Stan po przebudowie

- [x] wiadomości z Prometheus dla kont nie-Hebe, z fallbackiem odczytu Hebe
- [x] wysyłanie, odpowiedź i przekazywanie wiadomości tekstowych
- [x] książka adresowa (Pracownicy/Opiekunowie/Uczniowie) i wybór „Od:”
- [x] usuwanie wiadomości: do kosza, a z kosza trwale
- [x] ciemny granatowy motyw, ikona aplikacji i ekran startowy z logo
- [ ] załączniki w wysyłanych wiadomościach
- [ ] weryfikacja live payloadów wysyłki na koncie produkcyjnym

## Etapy

- [x] **M0 — fundament**: XcodeGen, paleta, Liquid Glass, 5 zakładek, CI + IPA
- [ ] **M1 — logowanie i Hebe**: CSRF, zgody, captcha PoW, `/api/ap`, rejestracja
      Hebe CE, podpis RSA, envelope, mapowanie błędów, wektory testowe z Kotlina
- [ ] **M2 — sesja**: wielu uczniów, Keychain, przywracanie sesji, wylogowanie
- [ ] **M3 — ekrany główne**: Start, Oceny, Plan (zastępstwa), Sprawdziany, Zadania
- [ ] **M4 — ekrany poboczne**: Notatki, Ogłoszenia, Wiadomości, Więcej, konto
- [ ] **M5 — Liquid Glass**: dopracowanie szkła, przejścia, typografia, dostępność
- [ ] **M6 — utwardzanie**: cache, stany błędów, odświeżanie, prywatność, testy
- [ ] **M7 — wydanie**: tag, release IPA, instrukcja instalacji, porządki w repo

## Parytet — 12 przepływów

Logowanie i zgody, wybór ucznia, Start, Oceny, Plan, Sprawdziany, Zadania,
Ogłoszenia, Wiadomości (odebrane/wysłane/kosz) z detalami, Notatki, Więcej/konto,
sprawdzanie aktualizacji (na iOS: informacja o nowym wydaniu na GitHubie).

## Ryzyka

- Podpis Hebe musi być bajt w bajt zgodny z Kotlinem — wektory testowe przed UI.
- Logowanie opiera się na HTML — izolowany adapter i czytelne stany błędów.
- Brak płatnego konta: brak App Store, TestFlight i powiadomień push.
- IPA podpisane darmowym certyfikatem działa 7 dni i wymaga ponownego podpisania.
- Odświeżanie w tle na iOS jest best-effort (`BGAppRefreshTask`).
