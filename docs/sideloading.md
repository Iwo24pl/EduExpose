# Instalacja IPA na iPhonie

CI buduje aplikację bez podpisu, bo repozytorium nie ma certyfikatu Apple.
Podpisujesz ją lokalnie swoim Apple ID — nie trzeba płatnego konta.

## Co będzie potrzebne

- iPhone z iOS 26
- komputer z Windows lub macOS
- darmowe Apple ID
- [Sideloadly](https://sideloadly.io/) oraz sterowniki Apple Devices (Windows)

## Kroki

1. Pobierz `EduExpose-unsigned.ipa` z wydania `latest`.
2. Podłącz iPhone, odblokuj go i zaufaj komputerowi.
3. Uruchom Sideloadly, przeciągnij IPA, wpisz Apple ID i kliknij Start.
4. Na iPhonie włącz tryb dewelopera: Ustawienia → Prywatność i bezpieczeństwo →
   Tryb dewelopera, następnie uruchom ponownie telefon.
5. Zaufaj certyfikatowi: Ustawienia → Ogólne → VPN i zarządzanie urządzeniem.

## Ograniczenia darmowego konta

- podpis wygasa po 7 dniach — powtórz kroki 3 i 5,
- maksymalnie 3 aplikacje na urządzeniu,
- brak powiadomień push i brak publikacji w App Store.

Aktualizacje: pobierz nowe IPA i podpisz je ponownie. Aplikacja nie instaluje
się sama — Apple nie pozwala na to poza App Store.
