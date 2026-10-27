# Librus backend (experimental)

Status: backend only. The UI, `AppModel` and the existing `StoredStudent`
Keychain format are intentionally untouched in this branch.

## Why the web-cookie flow

Two Librus flows still circulate online:

| Flow | Status | Used for |
| --- | --- | --- |
| `synergia.librus.pl/loguj/portalRodzina` → `api.librus.pl/OAuth/Authorization` → cookies → `synergia.librus.pl/gateway/api/2.0` | Confirmed live through October 2026 | This backend |
| Mobile portal OAuth (`portal.librus.pl/konto-librus`) → `api.librus.pl/2.0` with bearer tokens | Still used by the Kotlin reference, but more moving parts and no announcements/profile | Deferred multi-child importer |
| `api.librus.pl/OAuth/Token` password grant | Dead since roughly March 2026 (`unsupported_grant_type`) | Never |

The web-cookie flow needs one session, has a documented refresh endpoint and
covers journal, school/class profile, announcements and the modern
Wiadomości API. It exposes one student per session (`Me.User`); the mobile
portal flow is the only reference that enumerates several children.

Primary references:

- [`librus-synergia`](https://github.com/MichalZaniewicz/librus-synergia)
  (MIT): current flow, session lifetime, refresh, cookie allowlist, error
  taxonomy, tests. Protocol facts and patterns were ported with attribution.
- [`ha-librus-synergia`](https://github.com/MichalZaniewicz/ha-librus-synergia)
  (MIT): password-persistence disclosure, forced re-login, diagnostics
  redaction, degraded modules.
- `emsi/librus_pyapi` (AGPL-3.0): protocol facts only, no code copied.
- `szkolny-eu/szkolny-android` (GPL-3.0): protocol facts for `AutoLoginToken`
  and captcha WebView only, no code copied.

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
  LibrusSessionActor.swift   login, refresh, 401 recovery, single-flight
  LibrusDTOs.swift           gateway/wiadomości payloads
  LibrusAPIClient.swift      typed endpoints
  LibrusMapper.swift         DTO → existing UI models
  LibrusProfileLoader.swift  Me/School/Class/User → Account
  LibrusJournalService.swift JournalService implementation + caches
  LibrusAuthService.swift    sign-in + session recreation
  LibrusMailService.swift    read-only MailService + capabilities
  LibrusMessageBody.swift    base64 → XML/CDATA → plain text
```

## Session policy

- A login is treated as valid for 20 hours, with a 5-minute safety margin.
- Refresh through `GET https://synergia.librus.pl/refreshToken` after 2 hours.
- A refresh only counts when the response sets a **new** `oauth_token`
  cookie. A `200` without a new cookie is a failure.
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
- Reference data (subjects, users, classrooms, categories) is cached for a
  day; user data for a minute. The app does not poll in the background.

## Security rules

- One `LibrusSessionActor` and one cookie jar per account. Never use
  `HTTPCookieStorage.shared`.
- The URLSession is ephemeral, has no cookie storage, no disk cache, no
  automatic redirects, and a 30 s/60 s timeout.
- Only `oauth_token`, `DZIENNIKSID`, `SDZIENNIKSID` and `DeviceCookie` are
  persisted. `DeviceCookie` keeps its `Path=/OAuth`; losing it brings
  captchas back.
- Cookies are persisted inside the Keychain blob, never in files or
  UserDefaults. The password is optional and only stored because the app
  needs unattended renewal.
- Every URL is checked against the HTTPS host allowlist in `LibrusHosts`.
  `Location` values are resolved and checked before they are followed.
- `app://librus` is not registered; the older mobile flow is not used here.
- The trace stores host/path/status/cookie names only. Response bodies,
  headers, cookies and credentials never enter it.
- A captcha is never bypassed. The fallback is a future isolated
  `WKWebView` with a non-persistent data store.

## Integration sketch (frontend phase)

```swift
let auth = LibrusAuthService()
let students = try await auth.signIn(login: email, password: password)
guard let student = students.first else { throw LibrusError.missingSession }

// Store the whole RegistryStudent in Keychain.
let data = try JSONEncoder().encode(student)

// After launch, recreate the live objects from the stored session.
let session = try await auth.makeSession(for: student)
let journal: any JournalService = LibrusJournalService(session: session)
let mail: any MailService = LibrusMailService(
    session: session,
    displayName: student.displayName
)
```

`RegistryStudent(legacy:)` maps an old `StoredStudent` from EduExpose 1.x to
an `.eduVulcan` session. Persisting the new model should be done per account
(one Keychain item each) so one corrupt blob cannot remove every student.

## Tests

- `LibrusCookieTests`: parsing, `Expires`/`Max-Age`, `Path=/OAuth`, domain
  matching, allowlist persistence.
- `LibrusSessionTests`: login handshake, invalid credentials, captcha,
  refresh, 401→refresh→retry, 401 after refresh→login, 403, insufficient
  scopes, 503, login backoff.
- `LibrusMappingTests`: `Me`, class, grades (`4+`), timetable, cancellations,
  homework, string notice ids, disabled averages, lucky day, base64 bodies.
- `RegistryModelTests`: Keychain-style codable round trips and legacy
  migration.

Everything runs without a Librus account. When a real account becomes
available, first capture redacted key shapes (no values) and check:

1. Login without captcha and that `DeviceCookie` is present.
2. `Metody`/`Me` shape and the student name.
3. A refresh after a session is older than 2 hours.
4. A deliberate 401 → one refresh → one retry.
5. Messages bootstrap and one inbox item.
6. The first real `Timetables`/`Grades` payload against the fixtures.

## Known limitations

- One Librus login = one child in this backend. The multi-child importer
  (mobile portal + `AutoLoginToken`) is a separate, opt-in follow-up.
- Messages are read-only: no compose, reply, forward, delete or attachment
  download.
- The mobile API's old password grant is not implemented.
- The first live login may require a small mapping adjustment; the tolerant
  DTOs and redacted trace are there for that.
