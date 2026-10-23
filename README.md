# EduExpose

Natywny klient eduVULCAN dla iOS, napisany w SwiftUI. Przepisanie projektu
Dzienniczek Szpontniczek (Szpontium) z Kotlina/Compose na Swift 6 i Liquid Glass.

Status - **pełny klient**. Wszystkie ekrany, logowanie eduVULCAN, podpisywanie
Hebe, obsługa wielu uczniów i sesja w Keychain są gotowe. CI buduje, testuje,
uruchamia aplikację w symulatorze i publikuje niepodpisane IPA.

## Funkcje

- logowanie eduVULCAN przez Prometheus, łącznie z captcha proof-of-work
- rejestracja urządzenia Hebe CE i podpisywanie każdego żądania RSA
- wielu uczniów, przełączanie aktywnego konta i zapamiętana sesja w Keychain
- oceny, średnie i szczegóły ocen
- plan lekcji z zastępstwami i nawigacją po tygodniach
- sprawdziany, zadania domowe, uwagi, ogłoszenia i wiadomości
- sprawdzanie aktualizacji przez GitHub Releases

## Wymagania

- iOS 26.0+
- Xcode 26
- XcodeGen

## Budowanie

    brew install xcodegen
    xcodegen generate
    open EduExpose.xcodeproj

Albo bez otwierania Xcode:

    xcodebuild -project EduExpose.xcodeproj -scheme EduExpose \
      -destination 'generic/platform=iOS Simulator' \
      CODE_SIGNING_ALLOWED=NO build

## Testy

    xcodebuild -project EduExpose.xcodeproj -scheme EduExpose \
      -destination 'platform=iOS Simulator,name=iPhone 17' test

## Instalacja na iPhonie bez konta deweloperskiego

Każdy zielony build gałęzi `swift` trafia jako niepodpisane IPA do wydania
[`latest`](https://github.com/Iwo24pl/EduExpose/releases/tag/latest).
Podpisz je Sideloadly swoim darmowym Apple ID — szczegóły w
[docs/sideloading.md](docs/sideloading.md). Certyfikat wygasa po 7 dniach.

## Architektura

- `EduExpose/App` — punkt wejścia, faza aplikacji i nawigacja
- `EduExpose/DesignSystem` — paleta, typografia, Liquid Glass
- `EduExpose/API` — Prometheus (logowanie), Hebe (REST), RSA i modele
- `EduExpose/Features` — ekrany funkcji

Plan, zakres i decyzje: [docs/roadmap.md](docs/roadmap.md).

## Status prawny

Nieoficjalny klient. Projekt nie jest powiązany z VULCAN ani eduVULCAN.
Korzysta z tych samych endpointów co aplikacja Dzienniczek VULCAN.

Projekt jest kontynuacją Dzienniczka Szpontniczek (licencja MIT) i zachowuje
jego historię oraz notice w pliku LICENSE.
