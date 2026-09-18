# Supermortgage app — Sign-up, for real

This document replaces `SHELL-ADDENDUM-1-signup.md` and `MILESTONE-2-real-accounts.md`. Delete both. Nothing about the front door is a fixture any more: a person taps Continue with Apple, Google or Log in or sign up, and a real account exists in our database on Google Cloud, with the agent's name and onboarding state stored against it. Everything past the front door (the mortgage, the number, Work, Feed, Goals, Artifacts) stays on fixtures until the next milestone.

The screens are already in `docs/prototype/Supermortgage-Agent-Prototype.html` (the sign-up state of the "Here's how I work:" page, the e-mail sheet, the **Check your email** code sheet, the **Account** section in Settings). Copy comes from it verbatim.

Build in this order: **A** the API against the emulator locally → **B** the iOS wiring against the emulator → **C** the cloud, then point the app at it. Doug's checklist (§1) gates step C and the on-device Apple/Google tests, not A or B.

---

## 1. What only Doug can do (in this order)

1. **Apple Developer Program** — enrolled as the company. Note the **Team ID** (Membership page).
2. **Google Cloud project** `supermortgage-app-nonprod`, billing linked. Enable **Identity Platform** (Console → Marketplace → "Identity Platform" → Enable; accept terms). Everything else is Terraform.
3. **Apple identifiers** (developer.apple.com → Certificates, Identifiers & Profiles):
   - **App ID** `com.supermortgage.app`, capability **Sign in with Apple** (Enable as a primary App ID).
   - **Services ID** `com.supermortgage.app.web`, Sign in with Apple enabled, primary App ID = the above, domain `supermortgage-app-nonprod.firebaseapp.com`, return URL `https://supermortgage-app-nonprod.firebaseapp.com/__/auth/handler`. (Identity Platform needs this for token verification and revocation; the app itself signs in natively.)
   - **Key** with Sign in with Apple enabled, primary App ID = the above. Download the `.p8` once (Apple won't show it again), note the **Key ID**.
4. **Identity Platform → Providers** (console.cloud.google.com → Identity Platform):
   - Add **Apple**: Services ID `com.supermortgage.app.web`, Team ID, Key ID, paste the `.p8` contents. Under the iOS section, add bundle ID `com.supermortgage.app`.
   - Add **Google**: accept the auto-created web client. Then, under **Settings → Security**, turn on e-mail enumeration protection; under **Providers**, do not enable Email/Password or Anonymous.
   - **Firebase console** (console.firebase.google.com, same project): Project settings → Your apps → add an iOS app with bundle `com.supermortgage.app` → download `GoogleService-Info.plist`. Commit it to `ios/Supermortgage/Resources/` — it holds public client identifiers only, not secrets.
5. **Google OAuth consent screen** (Cloud Console → APIs & Services → OAuth consent screen): External, app name "Supermortgage", support e-mail, developer e-mail, and the privacy-policy and terms URLs below. Publish it (Testing mode limits sign-in to listed users).
6. **Privacy policy and terms pages** live on supermortgage.com. Both Apple and Google check they exist; the terms line on our page links to them.
7. **Transactional e-mail** account (Resend or Postmark), verified sending domain `mail.supermortgage.com` (one TXT + two CNAMEs at GoDaddy), an API key.
8. **DNS**: when Terraform prints the load balancer IP, an A record `api-nonprod.supermortgage.com` at GoDaddy.
9. **App Store Connect**: create the app record for `com.supermortgage.app` (TestFlight needs it). Create an App Store Connect API key (Users and Access → Integrations) for CI uploads; note Issuer ID, Key ID, download the `.p8`.

Secrets (Apple `.p8`, e-mail API key, App Store Connect `.p8`) go into GCP Secret Manager or GitHub encrypted secrets as §7 and §8 say. Never into the repo.

---

## 2. Architecture (settled)

- **Identity provider:** Google Cloud Identity Platform (Firebase Authentication with the GCP SLA). Apple and Google sign in through it natively; the e-mail door is our own six-digit code exchanged for an Identity Platform **custom token**. Tokens are minted, refreshed and revoked by Identity Platform.
- **Our API:** one Cloud Run service, TypeScript on Node 22, Fastify, Postgres 16 on Cloud SQL, plain-SQL migrations. It verifies Identity Platform ID tokens with the Admin SDK and owns users, households, agents and onboarding.
- **Session:** the iOS app sends the Identity Platform ID token as `Authorization: Bearer` on every call. No session table, no cookies; the SDK refreshes the token; the API checks revocation.
- **iOS dependencies, exactly two,** via Swift Package Manager, pinned: `firebase-ios-sdk` (product `FirebaseAuth` only) and `GoogleSignIn-iOS` (products `GoogleSignIn`, `GoogleSignInSwift`). Apple sign-in uses the system `AuthenticationServices`. Update `CLAUDE.md`: these two are the only allowed dependencies; the app may talk only to our API, Identity Platform and Google Sign-In.
- **Cloud:** new GCP project per environment (`supermortgage-app-nonprod` now, `-prod` later). Cloud Run, Cloud SQL, Secret Manager, Artifact Registry, a global HTTPS load balancer with a managed certificate at `api-nonprod.supermortgage.com`, all Terraform, deployed from GitHub Actions through Workload Identity Federation (no long-lived keys).

---

## 3. The page and the doors (iOS)

The sign-up state of the **Here's how I work:** page, exactly as the HTML draws it: back chevron top-left (our `icon-button` in `chrome`), the mark, the heading **Setup your home assistant**, and at the bottom three doors (`.ag-door`: 52pt, 16pt radius, `surface` fill, `cardLine` border, body size weight 600, icon and label centered, 10pt apart) over the terms line:

- **Continue with Apple** — inverted (`text` fill, `paper` label, the Apple logo). Use the system `SignInWithAppleButton(.continue)`, `.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)`, clipped to 16pt, so Apple's review sees Apple's button.
- **Continue with Google** — the four-color G (the `GOOGLE` SVG from the HTML as an asset).
- **Log in or sign up** — the envelope icon (the `mail` path).

While any door is in progress all three disable and the tapped one shows the spinner and "Continuing with Apple…" / "Continuing with Google…" (from the HTML). Cancel (`ASAuthorizationError.canceled`, `GIDSignInError.canceled`) re-enables silently. Any other error → toast with the provider's message shortened to one line, buttons re-enabled.

### 3.1 Apple
```swift
// on tap (onRequest)
let rawNonce = randomNonce(32)              // CSPRNG, base64url
request.requestedScopes = [.fullName, .email]
request.nonce = sha256Hex(rawNonce)

// onCompletion(.success(auth)) with an ASAuthorizationAppleIDCredential
let idToken = String(data: credential.identityToken!, encoding: .utf8)!
let cred = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: credential.fullName)
let result = try await Auth.auth().signIn(with: cred)
```
Apple sends `fullName` and `email` only on the first authorization; the e-mail may be a `privaterelay.appleid.com` address — accept it, never ask for another. Entitlement: `Supermortgage.entitlements` with `com.apple.developer.applesignin = [Default]`, wired in `project.yml` (`CODE_SIGN_ENTITLEMENTS: Supermortgage/Supermortgage.entitlements`, `DEVELOPMENT_TEAM` from a build setting, automatic signing).

### 3.2 Google
```swift
let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
let cred = GoogleAuthProvider.credential(withIDToken: result.user.idToken!.tokenString,
                                         accessToken: result.user.accessToken.tokenString)
let user = try await Auth.auth().signIn(with: cred)
```
`FirebaseApp.configure()` in the app's `init` (reads `GoogleService-Info.plist`). Info.plist (via `project.yml` `INFOPLIST_KEY_*` or an `Info.plist` file): `GIDClientID` = the plist's `CLIENT_ID`; `CFBundleURLTypes` with the plist's `REVERSED_CLIENT_ID`. Handle the callback with `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }`.

### 3.3 E-mail code
1. **Log in or sign up** → the e-mail sheet (from the HTML). Continue → `POST /v1/auth/email/start {email}` → the **Check your email** sheet.
2. Code Continue → `POST /v1/auth/email/verify {email, code}` → response `{customToken}` → `try await Auth.auth().signIn(withCustomToken: token)`.
3. **Send a new code** → start again. Fewer than six digits → toast "Six digits" (no request). Wrong code → the API's 400 → toast "That code didn’t work" and keep the sheet; after the fifth wrong attempt the API burns the code and returns 410 → toast "Ask for a new code".

### 3.4 After any door
```
POST /v1/me/bootstrap   →   Me { user, household, agent, onboarding }
```
Then route: `onboarding.completedAt != nil` → straight to Chat with the saved agent name in the pill and the saved greeting; else → **Setting up your agent** → the chat intro, as today.

### 3.5 What else changes in the app
- `AuthSession` (`@Observable`): wraps `Auth.auth().addStateDidChangeListener`; exposes `state ∈ signedOut | signingIn(provider) | signedIn(User)`, `idToken()` (async; the SDK refreshes), `signOut()`, `deleteAccount()`.
- `APIClient`: base URL from the build configuration (`API_BASE_URL`; Debug points at the emulator/local API, TestFlight at nonprod), Bearer token on every call, generated types from `api/openapi.yaml`, 401 → sign out.
- `AppModel` stops owning `name`, `stage` persistence and `account`: the server is the source of truth. Cold start shows Welcome (with its spinner) while `GET /v1/me` resolves — the first paint is unchanged. No Firebase user → Welcome → Here's how I work as today.
- Naming Hazel/Reed/typed → `PATCH /v1/me/agent {name}` (optimistic; revert with a toast on failure). Starting the chat intro → `PATCH /v1/me/onboarding {stage: "chat"}`.
- Settings → **Account** (from the HTML): "Signed in with Apple / Google / e-mail · {email}" from `Me.user`, **Sign out** → `Auth.auth().signOut()` → Welcome, toast "Signed out".
- Settings → Your data → **Delete**: a confirmation sheet, then: if the account has the Apple provider, run a fresh Sign in with Apple request (Apple's authorization codes live minutes, so we get a new one at deletion time) and call `Auth.auth().revokeToken(withAuthorizationCode:)`; then `DELETE /v1/me`; then sign out → Welcome. Apple requires in-app deletion with token revocation for any app offering Sign in with Apple.

---

## 4. The API (`api/`)

```
api/
  package.json  tsconfig.json  Dockerfile  vitest.config.ts
  src/server.ts            Fastify, health, OpenAPI from route schemas (zod), structured JSON logs
  src/auth/verify.ts       Bearer → firebase-admin getAuth().verifyIdToken(token, true); project check; upsert users
  src/auth/email.ts        /v1/auth/email/start + /verify; codes, limits, custom token
  src/me/routes.ts         /v1/me/bootstrap, /v1/me, /v1/me/agent, /v1/me/onboarding, DELETE /v1/me
  src/db/pool.ts, migrate.ts
  src/mail/sender.ts       one HTTP call to the e-mail API; a logging stub when MAIL_STUB=1
  migrations/0001_users.sql …
  test/                    Vitest against Postgres + the Firebase Auth emulator
  openapi.yaml             generated at build; the iOS client is generated from it
```

### 4.1 Schema (uuid ids, timestamptz)
```
users             id, firebase_uid unique, email citext unique null, email_verified bool, display_name,
                  providers text[], created_at, last_seen_at, deleted_at
households        id, owner_user_id → users, created_at
household_members household_id, user_id, role ('owner'), pk (household_id, user_id)
agents            household_id unique, name null, named_at
onboarding        user_id unique, stage ('know'|'setup'|'chat'), completed_at
email_codes       id, email citext, code_hash, attempts int default 0, expires_at, consumed_at, created_at
audit_log         id, user_id null, event, detail jsonb, ip inet, created_at
```

### 4.2 Routes
- `GET /health` → `{ok, version, db}`.
- `POST /v1/auth/email/start {email}` → always `200 {}`. Normalize (trim, lowercase, NFKC). Code: six digits from a CSPRNG. Store `sha256(pepper + email + code)`, `expires_at = now()+10 min`, invalidate earlier open codes for the address. Send the mail: subject "Your Supermortgage code", body "Your Supermortgage code is 482913. It expires in 10 minutes. If you didn’t ask for it, ignore this e-mail." Limits: 5 starts / e-mail / hour, 20 / IP / hour → still `200`.
- `POST /v1/auth/email/verify {email, code}` → `200 {customToken}` | `400 code_invalid` | `410 code_expired_or_burned`. Constant-time compare; `attempts += 1`; the fifth miss consumes the code. On success: consume; `getUserByEmail` or `createUser({email, emailVerified: true})`; `createCustomToken(uid)`; audit `signin.email`.
- `POST /v1/me/bootstrap` (Bearer) → upsert `users` by `firebase_uid` (email, email_verified, display_name, providers from the token's `firebase.sign_in_provider` and the user record), create `households` + `household_members` + `agents` + `onboarding{stage:'know'}` if missing, set `last_seen_at`, return `Me`.
- `GET /v1/me` → `Me`. `PATCH /v1/me/agent {name}` (1–24 chars, trimmed; sets `named_at` and `onboarding.completed_at`). `PATCH /v1/me/onboarding {stage}`.
- `DELETE /v1/me` → delete household, members, agent, onboarding, codes; soft-delete `users` (`deleted_at`); `getAuth().deleteUser(uid)`; `204`; audit.
- Every Bearer route: `verifyIdToken(token, /*checkRevoked*/ true)`, reject if `aud`/`iss` aren't this project, never read a `uid` from the body. Logs carry request id, route, status, latency — no bodies, no e-mail addresses.

### 4.3 Runtime notes that bite
- Custom tokens on Cloud Run: the service account needs `roles/iam.serviceAccountTokenCreator` **on itself** (the Admin SDK signs with IAM when there's no key file). Set `GOOGLE_CLOUD_PROJECT`.
- Migrations run at container start under an advisory lock; forward-only; the first migration creates `citext`.
- Local: `docker compose up` → Postgres 16 + `firebase-tools` Auth emulator; `FIREBASE_AUTH_EMULATOR_HOST=localhost:9099`, `MAIL_STUB=1` (the code is logged, and the emulator's REST API exposes users for tests).

---

## 5. Cloud (Terraform, `infra/terraform`)

Follow the platform's conventions: one module, `envs/nonprod.tfvars`, a `bootstrap.sh` that creates the state bucket, outputs that print the DNS line.

- Enable: run, sqladmin, secretmanager, artifactregistry, identitytoolkit, iam, iamcredentials, compute, certificatemanager, cloudresourcemanager, servicenetworking, vpcaccess.
- **Identity Platform** in Terraform where it can be (`google_identity_platform_config` — authorized domains, enumeration protection; `google_identity_platform_default_supported_idp_config` for Google). The Apple provider is configured by hand in §1.4 because the private key is a paste; document that.
- **Cloud SQL** Postgres 16 `db-g1-small`, private IP, automated backups, PITR, deletion protection; database `app`, user `api`, password generated into Secret Manager.
- **Cloud Run** `supermortgage-app-api`: min 1 / max 10, 512 MB, Cloud SQL connector, dedicated service account with `cloudsql.client`, `secretmanager.secretAccessor`, `firebaseauth.admin`, and `iam.serviceAccountTokenCreator` on itself. Env: `DATABASE_URL` (secret), `EMAIL_API_KEY` (secret), `GOOGLE_CLOUD_PROJECT`, `ENVIRONMENT`, `MAIL_FROM=Supermortgage <code@mail.supermortgage.com>`.
- **Artifact Registry** `api`; **WIF** pool + provider for `doug-ludlow/supermortgage-app`; deploy service account with `run.admin`, `artifactregistry.writer`, `iam.serviceAccountUser`.
- **Load balancer**: global external HTTPS, serverless NEG → Cloud Run, managed certificate `api-nonprod.supermortgage.com`, HTTP→HTTPS redirect, Cloud Armor rate limit 600 req/min/IP with the preconfigured WAF rules in preview.

---

## 6. Tests

- **API (Vitest):** start/verify happy path; expiry; the fifth miss burns; both rate limits; bootstrap idempotent; agent-name validation; delete flow; 401 for missing, malformed, wrong-project and revoked tokens; enumeration (start returns 200 for unknown and known addresses alike).
- **iOS unit tests:** `AuthSession` state machine against a fake `Auth`; `APIClient` decoding against the OpenAPI examples; cold-start routing (no user → Welcome; user + incomplete → Setup; user + complete → Chat with the saved name).
- **The walk** (UI test, CI): unchanged to "Get started", then **Log in or sign up** → e-mail `walk@example.com` → the code read from the Auth emulator / stub log → Continue → Setting up → Chat → the rest as before. Apple and Google can't run in CI; §9 covers them by hand.

---

## 7. CI/CD (`.github/workflows`)

- `api.yml`: on push/PR — Vitest with Postgres and the emulator as services; on `main` — build the image, push to Artifact Registry, `gcloud run deploy --no-traffic`, hit `/health` on the new revision, then shift traffic. Auth via WIF (`google-github-actions/auth`).
- `infra.yml`: `terraform plan` on PR (comment the plan), `terraform apply` on `main` behind a GitHub environment approval.
- `ios.yml`: existing unit tests and walk, plus on `main` a **TestFlight** job: `xcodebuild archive` (automatic signing with the App Store Connect API key: `-allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`), `exportArchive` with `method: app-store`, `xcrun altool --upload-app`. GitHub secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64), `APPLE_TEAM_ID`. TestFlight is how the app reaches a phone; Appetize stays for browser demos (Apple and Google sign-in do not work in Appetize).

---

## 8. Secrets and config, where each lives

| Item | Where |
|---|---|
| Apple `.p8` for Sign in with Apple, Key ID, Team ID, Services ID | Identity Platform's Apple provider (console, §1.4) |
| `GoogleService-Info.plist` | committed at `ios/Supermortgage/Resources/` (public identifiers) |
| E-mail API key, DB password | GCP Secret Manager → Cloud Run env |
| App Store Connect API key | GitHub encrypted secrets (`ASC_*`) |
| `DEVELOPMENT_TEAM` | `ios/project.yml` build setting (a public Team ID) |
| Terraform state | GCS bucket from `infra/bootstrap.sh` |

---

## 9. Definition of done

- On a real iPhone (TestFlight): sign up with Apple, with Google, and with an e-mail code. Each lands in `users` with the right provider, creates a household and an agent, and reaches the chat intro.
- Name the agent, kill the app, reopen: the pill says Hazel and the chat greets by name. Sign in on a second device: same.
- Sign out returns to Welcome; signing back in resumes where you were. Delete removes the account (Identity Platform user gone, Apple token revoked, rows gone) and returns to Welcome.
- Wrong, expired and burned codes and both rate limits behave as §4.2; no response reveals whether an address exists.
- `terraform apply` builds the environment from an empty project; `api.yml` deploys on push to `main`; `https://api-nonprod.supermortgage.com/health` is green.
- No secret in the repo; no PII in logs; the two dependency exceptions are the only dependencies; every visible string is the HTML's.

Not in scope: household data beyond the agent's name, any connection (Plaid, servicer, credit), the number, push notifications, the browser worker.
