# Librus backend

Status: the app now uses `RegistryStudent` end to end. eduVULCAN and Librus
share the same screens; the Keychain format migrates the old flat
`StoredStudent` array in place.

## Why two Librus flows

| Flow | Status | Used for |
| --- | --- | --- |
| Konto LIBRUS portal (`portal.librus.pl/konto-librus`) → `SynergiaAccounts` → `AutoLoginToken` | Implemented, fixture-tested | Multi-child and the preferred parent login |
| `synergia.librus.pl/loguj/portalRodzina` → `api.librus.pl/OAuth/Authorization` → cookies → `synergia.librus.pl/gateway/api/2.0` | Confirmed live through October 2026 | Fallback and single-child accounts |
| `api.librus.pl/OAuth/Token` password grant | Dead since roughly March 2026 (`unsupported_grant_type`) | Never |

The portal flow is the only one that enumerates every child from one parent
account. For each child it obtains a short-lived Synergia API token, exchanges
it for an `AutoLoginToken`, and opens a normal Synergia web session with
`DZIENNIKSID`. The existing gateway client then reads the journal exactly as
in the web flow.

Primary references:

- [`librus-synergia`](https://github.com/MichalZaniewicz/librus-synergia)
  (MIT): current web flow, session lifetime, refresh, cookie allowlist, error
  taxonomy, attendance shapes, tests. Protocol facts and patterns were ported
  with attribution.
- [`ha-librus-synergia`](https://github.com/MichalZaniewicz/ha-librus-synergia)
  (MIT): password-persistence disclosure, forced re-login, diagnostics
  redaction, degraded modules.
- `emsi/librus_pyapi` (AGPL-3.0): protocol facts only, no code copied.
- `szkolny-eu/szkolny-android` (GPL-3.0): protocol facts for the portal,
  `SynergiaAccounts`, `AutoLoginToken` and captcha WebView only, no code
  copied.

## Components

```text
EduExpose/API/Registry/
  EduRegistry.swift          provider identity
  RegistrySession.swift      storage-neutral sessions + legacy migration
  RegistryAuthService.swift  sign-in boundary (Prometheus adapter included)
  JournalService.swift       provider-neutral journal reads + Hebe adapter

EduExpose/API/Librus/
  LibrusConstants.swift      hosts, endpoints, lifetimes
  LibrusErrors.swift         typed failures and Polish messages
  LibrusHosts.swift          strict HTTPS host allowlist
  LibrusDate.swift           Europe/Warsaw school dates
  LibrusCookies.swift        cookie parser + private per-account jar
  LibrusTransport.swift      URLSession transport, no cookies/cache/redirects
  LibrusTrace.swift          redacted diagnostics
  LibrusSessionActor.swift   login, refresh, bridge, 401 recovery
  LibrusPortalClient.swift   portal login, child list, AutoLoginToken bridge
  LibrusDTOs.swift           gateway/wiadomości/attendance payloads
  LibrusAPIClient.swift      typed endpoints
  LibrusMapper.swift         DTO → existing UI models (grades and attendance)
  LibrusProfileLoader.swift  Me/School/Class/User → Account + periods
  LibrusJournalService.swift JournalService implementation + caches
  LibrusAuthService.swift    portal-first sign-in + session recreation
  LibrusMailService.swift    read-only MailService + capabilities
  LibrusMessageBody.swift    base64 → XML/CDATA → plain text
```

## Provider-neutral frontend

- `AppModel` stores `[RegistryStudent]`, builds one `JournalService` per
  student and routes every `load…` method through it.
- The login screen has an eduVULCAN / Librus picker and remembers the last
  choice. Librus uses “E-mail” and the Konto LIBRUS label.
- Provider badges appear in the login result, account switcher, settings,
  Start and More.
- `MessagesView` reads `mailCapabilities`; Librus shows read-only mail and
  hides compose, reply, forward and delete.
- Attendance uses the same `AttendanceView` for both providers. Librus
  exposes a full-year period (`number == 0`) plus semesters; `PeriodLabel`
  gives both providers the same “Rok szkolny YYYY/YY” / “Okres N” wording.
- Existing EduExpose 1.x Keychain data is decoded as `[StoredStudent]`,
  converted with `RegistryStudent(legacy:)`, and saved back in the new format.

## Session policy

- Web login: valid for 20 hours, 5-minute safety margin, refresh after 2
  hours through `GET https://synergia.librus.pl/refreshToken`.
- Portal child: a Synergia web session, treated as valid for 45 minutes with
  a refresh after 30 minutes through a fresh `AutoLoginToken` bridge.
- A refresh only counts when the response sets a **new** session cookie. A
  `200` without a new cookie is a failure.
- A failed refresh is not retried for 30 minutes.
- A 401 first tries a refresh; if the request is still rejected, one forced
  login is attempted, then the request is retried once.
- A 401 immediately after a refresh goes straight to the forced login
  instead of refreshing again.
- Concurrent 401s share one login/refresh task.
- A failed login is not retried for 60 seconds.
- 403, 404, 405 and 401 `Insufficient scopes` are module refusals, never a
  reason to log in.
- 429, 502, 503 and 504 are retry-later answers and never trigger a login.
- Messages have their own bootstrap (`/wiadomosci3`) and are re-bootstrapped
  before a password login; a second rejection is not allowed to loop.
- Reference data (subjects, users, classrooms, categories, lessons, attendance
  types) is cached for a day; user data for a minute. The app does not poll
  in the background.

## Attendance mapping

Librus returns raw attendance records; VULCAN returns ready statistics. The
mapper derives the same UI models:

| UI model | Librus source |
| --- | --- |
| Entries | `Attendances` + `Attendances/Types` + `Lessons` |
| Month statistics | grouped by `Attendances[].Date`, plus synthetic month `0` |
| Subject statistics | `Lessons[].Subject` → `Subjects` |
| Type flags | `Types[].Name` and `IsPresenceKind` |
| Time slot | `LessonNo` → “Lekcja N” |
| Percentage | present records / all records in the period |

The records are filtered by `Semester` for semester periods and are all
included for the full-year period. The existing `AttendanceSnapshot` fills
zero counters from the detailed entries, so a Librus percentage is never
shown next to empty counters.

## Security rules

- One `LibrusSessionActor` and one cookie jar per account. Never use
  `HTTPCookieStorage.shared`.
- Portal cookies and child cookies have separate jars; each child gets its own
  `LibrusPortalClient` for the bridge.
- The URLSession is ephemeral, has no cookie storage, no disk cache, no
  automatic redirects, and a 30 s/60 s timeout.
- Only `oauth_token`, `DZIENNIKSID`, `SDZIENNIKSID` and `DeviceCookie` are
  persisted. `DeviceCookie` keeps its `Path=/OAuth`; losing it brings
  captchas back.
- Cookies, passwords, portal refresh tokens and child access tokens live only
  inside the Keychain blob, never in files or UserDefaults. The password is
  stored because the app needs unattended renewal.
- Every URL is checked against the HTTPS host allowlist in `LibrusHosts`.
  `Location` values are resolved and checked before they are followed.
- `app://librus` is parsed for its OAuth code but never requested. The app
  does not register the scheme.
- The trace stores host/path/status/cookie names only. Response bodies,
  headers, cookies and credentials never enter it.
- A captcha is never bypassed. The fallback is a future isolated
  `WKWebView` with a non-persistent data store.

## Integration sketch

```swift
let auth = LibrusAuthService()
let students = try await auth.signIn(login: email, password: password)
// One RegistryStudent per child; store the whole array in Keychain.

// After launch, recreate the live objects from the stored session.
let actor = try await auth.makeSession(for: student)
let journal = LibrusJournalService(session: actor)
let mail = LibrusMailService(session: actor, displayName: student.displayName)
```

`RegistryStudent(legacy:)` maps an old `StoredStudent` from EduExpose 1.x to
an `.eduVulcan` session. The new store is a single versioned array; decoding
falls back to the legacy array and immediately saves the migrated form.

## Tests

- `LibrusCookieTests`: parsing, `Expires`/`Max-Age`, `Path=/OAuth`, domain
  matching, allowlist persistence.
- `LibrusSessionTests`: login handshake, invalid credentials, captcha,
  refresh, 401→refresh→retry, 401 after refresh→login, 403, insufficient
  scopes, 503, login backoff.
- `LibrusMappingTests`: `Me`, class, grades (`4+`), timetable, cancellations,
  homework, announcements, attendance months/subjects/semesters, portal
  account lists, portal redirect codes and station CSRF fields.
- `RegistryModelTests`: Keychain-style codable round trips, portal session
  round trip, old Librus session compatibility and legacy migration.

Everything runs without a Librus account. When a real account becomes
available, first capture redacted key shapes (no values) and check:

1. Login without captcha and that `DeviceCookie` is present.
2. `Metody`/`Me` shape and the student name.
3. A refresh after a session is older than 2 hours.
4. A deliberate 401 → one refresh → one retry.
5. Messages bootstrap and one inbox item.
6. The first real `Timetables`/`Grades` payload against the fixtures.

## Known limitations

- The portal flow is fixture-tested but has not been verified against a real
  Konto LIBRUS parent account in this environment. If a school disables the
  portal, the single-child web login remains the fallback.
- A portal session only refreshes through `AutoLoginToken`; when the portal
  refresh token itself is revoked the app asks for the password again.
- Messages are read-only: no compose, reply, forward, delete or attachment
  download.
- The mobile API's old password grant is not implemented.
- Librus attendance percentages are derived from records. Counts and entries
  are exact; a school's own percentage may differ by rounding.
- Custom attendance types are classified by name and `IsPresenceKind`.
  Unknown types stay visible instead of being dropped.
- The first live login may require a small mapping adjustment; the tolerant
  DTOs and redacted trace are there for that.
