# Nowe API wiadomości eduVULCAN (Prometheus)

Skrzynka nowego eduVULCAN działa pod `https://wiadomosci.eduvulcan.pl/{tenant}/api/...`
i wymaga sesji SSO oraz nagłówków `X-V-AppGuid` i `X-V-RequestVerificationToken`.
To **nie** jest stary moduł UONET+ `uonetplus-wiadomosciplus`.

`globalKeySkrzynka` w endpointach adresowych to klucz **skrzynki nadawcy** z
`/api/Skrzynki` (jednej z Twoich skrzynek), a nie klucz osoby, do której piszesz.

## Endpointy używane przez aplikację

| Operacja | Metoda i ścieżka | Odpowiedź |
|---|---|---|
| Twoje skrzynki | `GET /Skrzynki` | `[{globalKey, nazwa, typUzytkownika}]` |
| Odebrane | `GET /OdebraneSkrzynka?globalKeySkrzynka=…&idLastWiadomosc=0&pageSize=50` | lista wiadomości |
| Wysłane | `GET /WyslaneSkrzynka?…` | lista wiadomości |
| Kosz | `GET /UsunieteSkrzynka?…` | lista wiadomości |
| Szczegóły | `GET /WiadomoscSzczegoly?apiGlobalKey=…` | treść, nadawca, odbiorcy, załączniki |
| Oznacz jako przeczytane | `PUT /WiadomoscSzczegoly` z `{"apiGlobalKey": "…"}` | |
| Nowa wiadomość | `POST /WiadomoscNowa` | |
| Odpowiedź / przekazanie | `POST /WiadomoscOdpowiedzPrzekaz` | |
| Nauczyciele | `GET /Pracownicy?globalKeySkrzynka=…` | `[{skrzynkaGlobalKey, nazwa}]` |
| Rodzice / opiekunowie | `GET /Opiekunowie?globalKeySkrzynka=…` | `[{skrzynkaGlobalKey, nazwa}]` |
| Uczniowie | `GET /Uczniowie?globalKeySkrzynka=…` | `[{skrzynkaGlobalKey, nazwa}]` |
| Do kosza | `POST /MoveTrash` | `204`, body: tablica kluczy |
| Usuń trwale | `POST /Delete` | `204`, body: tablica kluczy |

## Adresaci

Trzy katalogi zwracają ten sam kształt: `skrzynkaGlobalKey` i `nazwa` w formacie
`Imię Nazwisko - R - (Szkoła)`. Rola zależy od endpointu, nie od nazwy:

- `Pracownicy` → nauczyciele i pracownicy (`P`),
- `Opiekunowie` → rodzice/opiekunowie (`R`, `O`),
- `Uczniowie` → uczniowie (`U`).

Dekoder akceptuje też `globalKey`/`name`, gdyby wariant API używał innych nazw pól.

## Usuwanie

Pierwsze usunięcie w Odebranych/Wysłanych trafia do `MoveTrash`; dopiero
usunięcie w Koszu wywołuje `Delete`. Body obu wywołań to tablica kluczy
wiadomości (`["<apiGlobalKey>"]`), tak jak w kliencie webowym.

Jeśli serwer odrzuci kształt body, pierwsze wywołanie zwróci `400`/`415`, a w
diagnostyce pojawi się wpis `api POST MoveTrash <status>`.

## Odpowiedź z kluczami

`GET /WiadomoscOdpowiedzPrzekaz?apiGlobalKey=…` może zwrócić
`nadawcaSkrzynkaGlobalKey`, `nadawcaSkrzynkaNazwa` i
`adresaci[{skrzynkaGlobalKey, nazwa}]`. Aplikacja używa tego do dokładnego
wypełnienia „Odpowiedz”/„Odpowiedz wszystkim”; gdy endpoint nie jest dostępny,
dopasowuje wyświetlane nazwy do katalogu adresatów.

## Ograniczenia

- Konta Hebe (`restUrl` zawiera `hebe`) są w tej aplikacji tylko do odczytu:
  brak wysyłania, adresatów i usuwania.
- Diagnostyka (`Ustawienia → Diagnostyka → Pokaż dziennik`) zapisuje
  `contacts.<Endpoint>` oraz `api <METODA> <Endpoint> <status>` bez tokenów i
  wartości zapytań.
