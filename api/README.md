# Supermortgage API

Accounts, households, agents and onboarding for the iPhone app (`docs/SIGNUP-FOR-REAL.md` §4). TypeScript on Node 22, Fastify, Postgres 16, plain-SQL migrations. Identity is Google Cloud Identity Platform: the app sends an Identity Platform ID token as `Authorization: Bearer` on every `/v1/me` call; the e-mail door is our own six-digit code exchanged for a custom token.

## Run it locally

```sh
docker compose up            # Postgres 16 on 5432 and the Firebase Auth emulator on 9099
cp .env.example .env
npm install
npm run dev                  # migrates, then listens on http://127.0.0.1:8080
```

Without Docker: any Postgres 16 (`DATABASE_URL`) and `npm run emulator` for the Auth emulator.

With `MAIL_STUB=1` the code is logged instead of sent, and `GET /__stub/mail/last?to=<address>` returns the last message (with `code`) so the iOS walk can sign in. The stub route only exists when the stub is on, and the stub is refused when `ENVIRONMENT=prod`.

## Routes

| Route | Auth | Answer |
|---|---|---|
| `GET /health` | none | `{ok, version, db}` (503 when the database is down) |
| `POST /v1/auth/email/start` `{email}` | none | always `200 {}` — over the limits (5 per address, 20 per IP, per hour) and for unknown addresses alike |
| `POST /v1/auth/email/verify` `{email, code}` | none | `200 {customToken}`, `400 code_invalid`, `410 code_expired_or_burned` (the fifth miss burns the code) |
| `POST /v1/me/bootstrap` | Bearer | `Me` — creates the user, household, agent and onboarding rows if missing |
| `GET /v1/me` | Bearer | `Me`, or `404 not_bootstrapped` |
| `PATCH /v1/me/agent` `{name}` | Bearer | `Me` — 1–24 characters, trimmed; sets `namedAt` and completes onboarding |
| `PATCH /v1/me/onboarding` `{stage}` | Bearer | `Me` — `know`, `setup` or `chat` |
| `DELETE /v1/me` | Bearer | `204` — rows deleted, the user soft-deleted without PII, the Identity Platform user deleted |

Every Bearer route verifies the token with `checkRevoked`, checks `aud` and `iss` against `GOOGLE_CLOUD_PROJECT`, and never reads a uid from a body. Logs carry the request id, route, status and latency — no bodies, no e-mail addresses.

`openapi.yaml` is generated from the route schemas (`npm run openapi`, also at build). The iOS types are generated from it: `npm run gen:swift` writes `ios/Supermortgage/App/API/Generated.swift` and the example JSON the iOS tests decode. CI fails when either is stale.

## Tests

```sh
npm run emulator             # in another terminal, or docker compose up
npm test
```

Vitest runs against a real Postgres (`TEST_DATABASE_URL`, default `postgresql://app:app@127.0.0.1:5432/app_test`, schema recreated per run) and the Auth emulator (`FIREBASE_AUTH_EMULATOR_HOST`, default `127.0.0.1:9099`). Covered: start/verify, expiry, the fifth miss, both rate limits, enumeration, bootstrap idempotence, agent-name validation, onboarding, delete, and 401 for missing, malformed, wrong-project and revoked tokens.

## Configuration

| Variable | Meaning |
|---|---|
| `PORT` | Cloud Run sets it (8080) |
| `DATABASE_URL` | TCP locally; the Cloud SQL socket form in the cloud (Secret Manager) |
| `GOOGLE_CLOUD_PROJECT` | The Identity Platform project; tokens for any other project are rejected |
| `FIREBASE_AUTH_EMULATOR_HOST` | Local only |
| `ENVIRONMENT` | `local`, `test`, `nonprod`, `prod` |
| `MAIL_STUB` | `1` logs codes instead of sending them (never in prod) |
| `EMAIL_API_KEY`, `MAIL_FROM` | Resend, when the stub is off |
| `EMAIL_CODE_PEPPER` | Mixed into every code hash (Secret Manager in the cloud) |

The image (`Dockerfile`) runs migrations at start under an advisory lock, forward-only, from `migrations/`. Deployment is `.github/workflows/api.yml`: tests on every push, then on `main` a build, a push to Artifact Registry, `gcloud run deploy --no-traffic`, a readiness check and the traffic shift. The custom-token signer needs `roles/iam.serviceAccountTokenCreator` on the service account itself (`infra/terraform/run.tf`).
