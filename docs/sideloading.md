# Instalacja EduExpose na iPhonie

EduExpose nie jest dostępny w App Store. CI publikuje **niepodpisane IPA**,
które podpisujesz swoim Apple ID — darmowe konto w zupełności wystarczy.

Do instalacji używamy **iLoader** (komputer) i opcjonalnie **SideStore**
(iPhone). Oba narzędzia są otwarte i aktywnie rozwijane; SideStore pozwala
odświeżać aplikację bez komputera. Sideloadly nie jest już częścią tej
instrukcji.

| Wariant | Kiedy wybrać | Odświeżanie |
| --- | --- | --- |
| **A. iLoader** | chcesz zainstalować aplikację od razu z komputera | ręcznie co 7 dni |
| **B. SideStore** | chcesz aktualizować i odświeżać aplikację na iPhonie | automatycznie, gdy LocalDevVPN działa |

Oba warianty można połączyć: iLoader instaluje SideStore, a SideStore zajmuje
się EduExpose.

## Co będzie potrzebne

- iPhone z iOS **26.0** lub nowszym i włączonym kodem (passcode),
- komputer: Windows (z iTunes), macOS (bez dodatków) lub Linux (z usbmuxd),
- kabel USB i zaufanie komputerowi,
- darmowe Apple ID z włączoną weryfikacją dwuetapową,
- Wi-Fi — wymagane przez SideStore,
- [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044) z App Store
  (tylko wariant B).

Pobieraj iLoader wyłącznie z [iloader.app](https://iloader.app) albo
[GitHub Releases](https://github.com/nab138/iloader/releases). Strony
oferujące „podpisy” i certyfikaty to scam.

## Wariant A — iLoader (najszybszy)

iLoader podpisuje IPA Twoim Apple ID i instaluje je przez USB lub Wi-Fi. Sam
tworzy certyfikat, rejestruje App ID i zarządza plikami pairing.

1. Zainstaluj iTunes (Windows) lub upewnij się, że działa `usbmuxd` (Linux).
   Na macOS nie trzeba nic dodatkowego.
2. Zainstaluj iLoader i podłącz iPhone'a. Na ekranie telefonu wybierz
   **Zaufaj** i podaj kod.
3. Uruchom iLoader i zaloguj się Apple ID (pierwsze logowanie wymaga kodu 2FA).
4. Wybierz swoje urządzenie, a następnie **Import IPA** / **Install IPA**
   i wskaż `EduExpose-unsigned.ipa`.
5. Na iPhonie: **Ustawienia → Ogólne → VPN i zarządzanie urządzeniem**,
   wybierz wpis z nazwą Apple ID i dotknij **Zaufaj**.
6. **Ustawienia → Prywatność i bezpieczeństwo → Tryb dewelopera** — włącz
   i uruchom telefon ponownie.
7. Otwórz EduExpose.

Aktualizacja: pobierz nowe IPA i powtórz kroki 2–4. Podpis wygasa po 7 dniach
na darmowym koncie — wtedy wystarczy ponownie podpisać ten sam plik.

## Wariant B — SideStore (odświeżanie na urządzeniu)

SideStore to aplikacja na iPhone'a, która podpisuje i odświeża aplikacje Twoim
Apple ID. Komputer i iLoader są potrzebne **tylko do pierwszej instalacji**
SideStore.

1. Zainstaluj **LocalDevVPN** i połącz się. Zezwól na konfigurację VPN i podaj
   kod. VPN działa lokalnie — nie wysyła ruchu przez zewnętrzny serwer.
2. Na komputerze uruchom iLoader, podłącz iPhone'a i wybierz
   **Install SideStore (Stable)**.
3. Na iPhonie zaufaj certyfikatowi dewelopera i włącz Tryb dewelopera
   (kroki 5–6 z wariantu A).
4. Włącz LocalDevVPN, otwórz SideStore i zaloguj się tym samym Apple ID.
5. W **My Apps** dotknij licznika **7 DAYS** obok SideStore, aby go odświeżyć.
   Jeśli pojawi się pytanie o certyfikat, wybierz **Yes** / **Refresh Now**.
6. Pobierz `EduExpose-unsigned.ipa` na iPhone'a (Safari lub Pliki), a następnie:
   - otwórz plik i wybierz **Udostępnij → SideStore**, albo
   - w SideStore dotknij **+** i wskaż IPA z plików.
7. Po instalacji uruchom EduExpose.

Aktualizacje: pobierz nowe IPA i zainstaluj je w SideStore w ten sam sposób.
Dane aplikacji zostają, dopóki nie usuniesz jej z telefonu.

### Limity darmowego Apple ID

- podpis ważny **7 dni** (SideStore odświeża go w tle, gdy LocalDevVPN działa),
- maksymalnie **3 aktywne aplikacje**, w tym sam SideStore,
- maksymalnie **10 różnych App ID** w tygodniu.

Płatne konto Apple Developer (99 USD/rok) wydłuża podpis do 365 dni i znosi
limit aplikacji — nie jest wymagane.

## Weryfikacja SHA-256

Każde wydanie zawiera `EduExpose-unsigned.ipa.sha256`. Przed podpisaniem
sprawdź plik:

```bash
# macOS / Linux
shasum -a 256 EduExpose-unsigned.ipa
```

```powershell
# Windows
Get-FileHash -Algorithm SHA256 .\EduExpose-unsigned.ipa
```

Wynik musi być identyczny z plikiem `.sha256` i opisem wydania. Jeśli się
różni, pobierz IPA ponownie.

## Typowe problemy

| Objaw | Rozwiązanie |
| --- | --- |
| „Untrusted Developer” przy uruchomieniu | Zaufaj certyfikatowi w Ustawienia → Ogólne → VPN i zarządzanie urządzeniem. |
| „Developer Mode disabled” | Włącz Tryb dewelopera i uruchom telefon ponownie. |
| iLoader nie widzi iPhone'a (Windows) | Zainstaluj iTunes, odblokuj telefon, zaakceptuj „Zaufaj”, użyj innego kabla/portu USB. |
| SideStore nie loguje się lub błąd Anisette | W Ustawieniach SideStore zmień **Anisette URL** na oficjalny serwer; tymczasowa awaria serwera też daje ten błąd. |
| Podpis wygasł | Odśwież aplikację w SideStore albo podpisz IPA ponownie w iLoaderze. |
| SideStore zgubił pairing | Wygeneruj pairing ponownie w iLoaderze i zaimportuj go do SideStore. |
| Aplikacja nie instaluje się | Sprawdź SHA-256, zwolnij miejsce w limicie 3 aplikacji i spróbuj ponownie. |

## Bezpieczeństwo

- iLoader i SideStore są otwartoźródłowe; nie udostępniaj nikomu swojego Apple
  ID, hasła ani kodu 2FA.
- Nie korzystaj z płatnych „sklepów z podpisami” ani z gotowych certyfikatów
  z nieznanych źródeł.
- Aplikacja łączy się bezpośrednio z eduVULCAN; instalacja przez iLoader lub
  SideStore nie dodaje żadnego pośrednika do ruchu aplikacji.
- Aktualizacje EduExpose sprawdzisz w aplikacji, ale instalacja zawsze odbywa
  się przez iLoader/SideStore — iOS nie pozwala na aktualizacje poza App Store.

Więcej o SideStore: [docs.sidestore.io](https://docs.sidestore.io/).
