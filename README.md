# Supermortgage app

The Supermortgage iPhone app. This repository holds Milestone 1, **the shell** — every screen, tab, sheet and interaction of the agent prototype rebuilt natively in SwiftUI on fixture data — and, on top of it, **real accounts**: a person taps Continue with Apple, Continue with Google or Log in or sign up, and a real account exists in our database on Google Cloud, with the agent's name and onboarding state stored against it. Everything past the front door stays on fixtures until the next milestone.

The specification is the clickable prototype at `docs/prototype/Supermortgage-Agent-Prototype.html`; the build brief is `docs/SHELL-SPEC.md`, extended by `docs/SIGNUP-FOR-REAL.md` (real accounts and sign-in). Where the brief and the HTML disagree, the HTML wins.

## Open, run, walk

Requires Xcode 16.3 or later (the two Swift packages need Swift 6.1 tools; iOS 17 SDK or later, an iPhone 15 simulator). The project file is committed; Xcode resolves the two packages on first open.

```sh
open ios/Supermortgage.xcodeproj
xcodebuild -project ios/Supermortgage.xcodeproj -scheme Supermortgage -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Supermortgage.xcodeproj -scheme Supermortgage -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO test
```

The first command opens the project (press ⌘R to run on the iPhone 15 simulator). The second builds it from the command line. The third runs the unit tests (`SupermortgageTests`) and the walk (`SupermortgageUITests`, one test that signs up with an e-mail code and taps through the whole product in the order of §8 of the spec).

Debug builds talk to a local API at `http://127.0.0.1:8080` and the Firebase Auth emulator at `127.0.0.1:9099` (Release builds talk to nonprod). Start both before running the app or the walk:

```sh
cd api
docker compose up          # Postgres 16 and the Auth emulator
cp .env.example .env && npm install && npm run dev
```

With `MAIL_STUB=1` (the default in `.env.example`) the six-digit code is printed by the API instead of being e-mailed, and the walk reads it from `GET /__stub/mail/last?to=walk@example.com`.

Xcode 16 does not create an "iPhone 15" simulator by default (its stock devices are the iPhone 16 family). If the destination is not found, add one once:

```sh
xcrun simctl create "iPhone 15" "iPhone 15"
```

Sign in with Apple and Google Sign-In only work on a real device with the project's `GoogleService-Info.plist` in `ios/Supermortgage/Resources/` and a Team ID in `ios/project.yml` (`docs/SIGNUP-FOR-REAL.md` §1); in the simulator, use Log in or sign up.

## The API and the cloud

`api/` is the Cloud Run service (TypeScript, Fastify, Postgres 16): the e-mail code door, `/v1/me` (bootstrap, the agent's name, onboarding, delete). Its README covers running and testing it; `openapi.yaml` is generated from the route schemas and the iOS types are generated from that.

`infra/` is the Terraform for one environment per Google Cloud project (`supermortgage-app-nonprod` first): Cloud Run, Cloud SQL, Secret Manager, Artifact Registry, Identity Platform, a global HTTPS load balancer with a managed certificate at `api-nonprod.supermortgage.com`, and Workload Identity Federation for GitHub Actions. `infra/README.md` has the order of operations; the by-hand steps (Apple Developer identifiers, the Identity Platform providers, DNS, the e-mail API key, App Store Connect) are §1 of the brief.

Workflows: `ios.yml` (unit tests and the walk against a local API on every push; the simulator build and Appetize; on `main` a TestFlight upload once the App Store Connect secrets exist), `api.yml` (tests against Postgres and the emulator, the generated-file check, the image; on `main` a Cloud Run deploy without traffic, a readiness check, then the traffic shift) and `infra.yml` (`terraform plan` on pull requests, `apply` on `main` behind the `nonprod` environment). The cloud jobs are no-ops until the repository variables `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA` and `APPLE_TEAM_ID` are set.

## Screenshots

Every green run on `main` publishes the walk's screenshots, one per screen (the last four in dark mode), to the [`screenshots` branch](https://github.com/doug-ludlow/supermortgage-app/tree/screenshots), where they can be viewed directly on GitHub.

## Viewing it in a browser (Appetize.io)

Every CI run builds a universal simulator app (`Supermortgage-simulator-app`, an artifact on the run page). Two ways to run it in a browser on [Appetize.io](https://appetize.io):

- **By hand:** download the artifact zip from the latest run under Actions, then upload it in your Appetize dashboard (Upload → iOS). Appetize gives you a link that runs the app in a browser-hosted simulator.
- **Automatically on every push:** add an Appetize API token as the repository secret `APPETIZE_API_TOKEN` (or just `APPETIZE`) (Settings → Secrets and variables → Actions). CI then publishes the build and prints the app link as a notice on the run. To keep one stable link, also add the app's public key as the secret `APPETIZE_PUBLIC_KEY` after the first upload; later pushes update that app in place.

In Appetize the doors cannot reach a local API or the real Identity Platform (Apple and Google sign-in do not work there); TestFlight is how the app reaches a phone.

## Layout

```
docs/prototype/   the HTML prototype, copied in unchanged — the spec
docs/SHELL-SPEC.md the build brief for the shell; docs/SIGNUP-FOR-REAL.md the accounts brief
ios/project.yml   XcodeGen spec (regenerate with `xcodegen generate` from ios/)
ios/tools/gen-pbxproj.py      writes the committed ios/Supermortgage.xcodeproj
ios/Supermortgage/            the app target: App (AppModel, Auth, API, ChatEngine, Router), DesignSystem, Features, Fixtures, Resources
ios/SupermortgageTests/       unit tests: fixtures, the number, work transitions, the chat script, the session, the API client, cold start, the doors
ios/SupermortgageUITests/     the walk
api/                          the API (Node 22, Fastify, Postgres 16) and its tests
infra/                        Terraform for the cloud, bootstrap.sh, the runbook
web/                          a placeholder for a later milestone
```

## What it is not

Beyond the front door there is no agent runtime, no real connection (Plaid, servicer, credit), no push, and no full refinance application. Every vendor past sign-in is a fixture, and nothing but the account, the agent's name and the onboarding state is persisted.

Fictional data only.
