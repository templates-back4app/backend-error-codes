# Why Does the API Return 101, 119, 142 or 209? Every Backend Error Code, Reproduced

[![Deploy on Back4app](https://img.shields.io/badge/Deploy%20on-Back4app-1568B8?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iI2ZmZiIgZD0iTTEyIDJMMiA3djEwbDEwIDUgMTAtNVY3eiIvPjwvc3ZnPg==)](https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes)

**One bash script that makes a backend return every error code on purpose, and prints what came back.** `reproduce.sh` fires 48 `curl` requests at a [Back4app](https://www.back4app.com/?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes) backend (a managed Parse Server) and prints one row per request: the code the article expects, the HTTP status, the numeric `code` in the body and the `error` message. Run it against your own backend and compare.

Measured on September 24, 2026, on two live backends: **43 error responses, 15 numeric codes** (101, 105, 107, 111, 119, 125, 141, 142, 200, 201, 202, 203, 204, 206, 209) plus the four HTTP-only answers (400, 401, 403, 404). Three runs per backend, identical rows every time; the raw output is in `results/`.

> **Read the article:** [Why Does the API Return 101, 119, 142 or 209? Every Backend Error Code, Reproduced](https://www.back4app.com/blog/why-does-the-api-return-101-119-142-or-209?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes)

## The lookup table

| Code | HTTP | What it means | What we did to get it |
|---|---|---|---|
| 101 | 404 | Object not found / invalid login / no session | wrong password · unknown username · made-up id · a row the ACL hides · anonymous request to a class that needs a session |
| 119 | 400 | Operation forbidden | `count` on a class whose CLP has no `count` entry · any request to a class whose CLP allows nobody · a Cloud Function refusing a non-member |
| 141 | 400 | Script failed | calling a function that is not defined · a `TypeError` thrown inside a `beforeSave` hook (the message is passed through) |
| 142 | 400 | Validation error | a `beforeSave` on `_User` rejecting the username `ab` |
| 202 / 203 | 400 | Username / e-mail already taken | signing up twice |
| 206 | 400 | Session missing | creating a `Note` with the master key: the master key bypasses the CLP, not the hook |
| 209 | 400 | Invalid session token | a made-up token · no token · the token that just logged out |
| 105 / 107 / 111 / 125 | 400 | Bad field name / bad class name / wrong type / bad e-mail | `"bad key"` · `POST /classes/bad-name` · a number in a String column · `not-an-email` |
| 200 / 201 / 204 | 400 | Username / password / e-mail missing | a signup or a reset request without the field |
| — | 401 | `unauthorized`, no code | no App ID, or an App ID that does not exist |
| — | 403 | `unauthorized`, no code | right App ID, wrong or missing key |
| — | 400 | JSON parse message, no code | a body that is not valid JSON |
| — | 404 | `{"message":"Not Found","error":{}}` | a path that does not exist |

Not reproduced, and therefore not in the article: **103** (an invalid class name answers 200 with an empty result on `GET`, and 107 on `POST`) and **205** (`POST /requestPasswordReset` for an e-mail nobody has answers `200 {}`).

## Findings from the run

- **Only code 101 is an HTTP 404.** Every other numeric code above is a 400. A wrong password is therefore a 404, because the login error reuses the object-not-found code.
- **101 covers five situations** with two messages: `Invalid username/password.`, `Object not found.` (a missing id and a row the ACL hides look the same) and `Permission denied, user needs to be authenticated.`
- **401 means the App ID is wrong or missing; 403 means the key is.** Both bodies are `{"error":"unauthorized"}` with no `code`.
- **A malformed JSON body gets no code at all**, just the parser's message. Branch on the presence of `code` before you branch on its value.
- **The master key skips the class permissions but not the hook.** A create with the master key and no session reached `beforeSave("Note")` and was refused with 206.
- **A non-Parse error inside a hook is code 141 with the raw message** (`Tried to create an ACL with an invalid permission type.`), not `Script failed`.
- **A create rejected with 105 still creates the class.** `POST /classes/ErrProbe {"bad key":1}` answered 105 and left an empty `ErrProbe` class in the schema. `reproduce.sh` deletes it afterwards.
- **`count` is its own class-level permission.** A CLP written without a `count` key is stored as `count: {}`, and then nobody may count, logged in or not: 119 for `ana`, whose `find` on the same class works.

## What is in here

- `reproduce.sh [auth|data|all]` — the 48 requests. `auth` needs any backend with `cloud/main.js` deployed; `data` needs the classes and users from `seed.sh`. Output is the table above, one row per request, with a UTC timestamp in the header.
- `seed.sh` — users `ana` and `bob`, a `moderator` role containing `bob`, a `Note` class whose class-level permissions require a session, and a `Vault` class that allows nobody. Idempotent.
- `cloud/main.js` — the hooks and functions behind 142, 206, 119, 209 and 141: a `beforeSave` on `_User`, a `beforeSave` on `Note`, `whoami` and `moderatorList`. It is the union of the two files deployed on the backends the article measured.
- `results/` — the eight runs the article quotes (three per backend with the JavaScript key, one per backend with the Client key), unedited.
- `.env.example` — the variable names. `.env` is git-ignored; the master key never leaves your machine.

## Deploy your own

1. **Create a free backend.** Sign up at [https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes](https://www.back4app.com/signup?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes), then **New App → Build your Backend**. The free plan is enough.
2. **App Settings → Security & Keys**: copy the App ID, the JavaScript key and the Master key into `.env` (`cp .env.example .env`).
3. **Cloud Code → main.js**: paste `cloud/main.js` and click **Deploy**, twice on a fresh backend (the first deploy ships nothing). Prove it: `./reproduce.sh auth` must show 142 on the `ab` row, not 201.
4. `./seed.sh`, then `./reproduce.sh data`. **Database → Note → Security → Class Level Permission** shows the lock the 101 and 119 rows come from; **Logs** shows the `TypeError` behind the 141 row.

## Run it

```bash
cp .env.example .env            # APP_ID, JS_KEY, MASTER_KEY
set -a; . ./.env; set +a
./reproduce.sh auth             # users, sessions, keys, malformed requests
./seed.sh                       # ana, bob, moderator, Note, Vault
./reproduce.sh data             # class permissions, ACLs, hooks, roles
./reproduce.sh all | tee results/$(date -u +%Y%m%dT%H%M%SZ).txt
```

Expected output (abridged, from `results/`):

```text
#    label (expected code · request · situation)                           HTTP  code  error
8    101 · POST /login · right username, wrong password                    404   101   Invalid username/password.
11   202 · POST /users · same username again                               400   202   Account already exists for this username.
13   142 · POST /users · username "ab" (beforeSave hook wants 3+)          400   142   username needs at least 3 characters.
24   209 · GET /users/me · the token that just logged out                  400   209   Invalid session token
17   206 · POST /classes/Note · master key, no session (hook needs a user)  400   206   log in to create a note.
```

## What the backend gives you

A managed Parse Server with a database, REST and GraphQL APIs, Cloud Code and three permission layers: class-level permissions, per-object ACLs and roles. Every code in the table is produced by one of them. Documentation: [https://www.back4app.com/docs?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes](https://www.back4app.com/docs?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes) · security guide: [https://www.back4app.com/docs/security/parse-server-security?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes](https://www.back4app.com/docs/security/parse-server-security?utm_source=github&utm_medium=repo&utm_campaign=backend-error-codes).

The two backends the article measured are the companion repos [user-auth-starter](https://github.com/templates-back4app/user-auth-starter) (the `_User` hook) and [lockdown-lab](https://github.com/templates-back4app/lockdown-lab) (the `Note` class, its permissions and the role).

## License

MIT
