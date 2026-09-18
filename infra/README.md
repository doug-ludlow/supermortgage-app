# Cloud environment

Terraform for one Supermortgage environment, §5 of `docs/SIGNUP-FOR-REAL.md`. One GCP project per environment: `supermortgage-app-nonprod` now, `-prod` later with a second tfvars file.

```
infra/bootstrap.sh              creates the state bucket, prints the init and apply lines
infra/terraform/                the root module (applied once per project)
infra/terraform/envs/*.tfvars   the per-environment values
.github/workflows/infra.yml     plan on pull requests, apply on main behind an approval
```

## What it builds

| File | Resources |
|---|---|
| `apis.tf` | The APIs of §5, plus `sts.googleapis.com` for Workload Identity Federation. Never disabled on destroy. |
| `network.tf` | A VPC and a subnet for Cloud Run's Direct VPC egress; the reserved range and the private services peering Cloud SQL's private IP lives on. |
| `sql.tf` | Cloud SQL Postgres 16 (`db-g1-small`, private IP only, daily backups, point-in-time recovery, deletion protection), database `app`, user `api` with a generated password. |
| `secrets.tf` | Secret Manager: `db-password`, `database-url` (the unix-socket URL the API reads), `email-code-pepper` (generated), and `email-api-key` with **no version**; see below. |
| `registry.tf` | Artifact Registry Docker repository `api`. |
| `run.tf` | Cloud Run `supermortgage-app-api`: min 1 / max 10, 512 MiB, 1 CPU, the Cloud SQL volume, Direct VPC egress for private ranges, ingress from the load balancer only, its own service account with `cloudsql.client`, `secretmanager.secretAccessor` on the three secrets it reads, `firebaseauth.admin`, and `iam.serviceAccountTokenCreator` on itself (§4.3). Public `run.invoker`: the API checks its own Bearer tokens. |
| `lb.tf` | Global external HTTPS load balancer: static IP, serverless NEG, backend service, managed certificate for `api_domain`, HTTP→HTTPS 301, and a Cloud Armor policy with a 600 req/min/IP throttle (429) and the preconfigured WAF rules in preview. |
| `identity.tf` | Identity Platform: authorized domains, Email/Password and Anonymous off, sign-up allowed. The Google provider only when its OAuth client is passed in. |
| `wif.tf` | Workload Identity pool `github` and provider `github-oidc` restricted to `doug-ludlow/supermortgage-app`; the `github-deploy` service account and its roles. |
| `outputs.tf` | The load balancer IP and the DNS line, the Cloud Run name and URL, the registry path, the WIF provider name, both service account e-mails, the Cloud SQL connection name. |

The Cloud Run service is created with Google's placeholder image. `api.yml` owns the image and the traffic (`gcloud run deploy --no-traffic`, `/health` on the new revision, then the shift), so Terraform ignores the image, the traffic split, and the labels, annotations and client stamps gcloud writes.

## Before the first apply, by hand

1. The GCP project `supermortgage-app-nonprod` exists with billing linked (§1.2).
2. **Identity Platform is enabled** in the Marketplace (Console → Marketplace → "Identity Platform" → Enable, accept the terms). `google_identity_platform_config` initializes the project's auth configuration and is the resource that fails if this was skipped.
3. Locally: `gcloud` signed in as an owner of the project, plus `gcloud auth application-default login` for Terraform; Terraform 1.6 or newer.

Everything else, the APIs included, is the module's job.

## Run it

```sh
infra/bootstrap.sh supermortgage-app-nonprod          # state bucket supermortgage-app-nonprod-tfstate, versioned
cd infra/terraform
terraform init  -backend-config="bucket=supermortgage-app-nonprod-tfstate"
terraform plan  -var-file=envs/nonprod.tfvars -var state_bucket=supermortgage-app-nonprod-tfstate
terraform apply -var-file=envs/nonprod.tfvars -var state_bucket=supermortgage-app-nonprod-tfstate
```

`state_bucket` is what grants the deploy service account access to the state for CI; the first apply is yours, later ones are the workflow's.

**The `email-api-key` secret has no version until you add one**, and Cloud Run refuses to start a revision whose secret has no version. So the first apply creates everything up to the Cloud Run service and then stops there. Add the version and apply again:

```sh
printf '%s' 'the-api-key' | gcloud secrets versions add email-api-key --project supermortgage-app-nonprod --data-file=-
terraform apply -var-file=envs/nonprod.tfvars -var state_bucket=supermortgage-app-nonprod-tfstate
```

(To avoid the failed first pass: `terraform apply -target=google_secret_manager_secret.email_api_key …`, add the version, then the full apply.)

## First deploy, in order

1. `bootstrap.sh` → `init` → `apply` → add the `email-api-key` version → `apply` again (above). Note the outputs.
2. In the GitHub repository, add the **repository variables** the workflows read (Settings → Secrets and variables → Actions → Variables):
   - `GCP_PROJECT_ID` = `supermortgage-app-nonprod`
   - `GCP_WIF_PROVIDER` = the `workload_identity_provider` output (`projects/…/locations/global/workloadIdentityPools/github/providers/github-oidc`)
   - `GCP_DEPLOY_SA` = the `deploy_service_account` output (`github-deploy@supermortgage-app-nonprod.iam.gserviceaccount.com`)

   and a **GitHub environment** named `nonprod` (Settings → Environments) with yourself as a required reviewer: that review is the approval `infra.yml` waits for before `terraform apply` on `main`. Until `GCP_WIF_PROVIDER` exists both workflows' cloud jobs skip themselves.
3. Push to `main`: `api.yml` builds the image, pushes it to `us-central1-docker.pkg.dev/supermortgage-app-nonprod/api`, deploys it without traffic, checks `/health`, shifts traffic.
4. DNS: the `dns_line` output, an A record for `api-nonprod.supermortgage.com` at GoDaddy (§1.8).
5. Wait for the managed certificate. It is issued only once the name resolves to the load balancer, typically within the hour; until then HTTPS handshakes fail (HTTP already answers with the redirect).
   ```sh
   gcloud compute ssl-certificates describe api-api-nonprod-supermortgage-com --global --format='value(managed.status,managed.domainStatus)'
   ```
   `ACTIVE` is done.
6. `curl https://api-nonprod.supermortgage.com/health` → `{ok, version, db}`.

## Still by hand, on purpose

- **Apple provider** (§1.4): Services ID, Team ID, Key ID and the pasted `.p8`, in Identity Platform → Providers. The key is a paste, so it is not in Terraform.
- **Google provider** (§1.4): add Google under Providers and accept the auto-created web client. To bring the provider under Terraform afterwards, pass that client's id and secret: `TF_VAR_google_oauth_client_id=… TF_VAR_google_oauth_client_secret=… terraform apply …`. Never put them in a committed file.
- **E-mail enumeration protection** (§1.4, Settings → Security): the provider has no field for it, so it stays a console switch.
- **The `email-api-key` version** (above).
- **The DNS A record** (above).
- **The GitHub variables and the `nonprod` environment** (above).
- The OAuth consent screen (§1.5), the Firebase iOS app and `GoogleService-Info.plist` (§1.4) and everything Apple-side are not cloud infrastructure.

## What `infra.yml` does

- On a pull request that touches `infra/`: `terraform fmt -check`, `init` against `<GCP_PROJECT_ID>-tfstate`, `validate`, `plan -var-file=envs/nonprod.tfvars`, and the plan as one comment on the pull request, updated on every push (cut to 60 000 characters, head and tail kept).
- On a push to `main` that touches `infra/`: `terraform apply -auto-approve` in the `nonprod` GitHub environment, so the environment's required reviewer approves each apply.
- Both authenticate with `google-github-actions/auth` through Workload Identity Federation as `github-deploy`; there is no key anywhere.

### The deploy account's roles, and why

`api.yml` needs `roles/run.admin`, `roles/artifactregistry.writer` and `roles/iam.serviceAccountUser` on the runtime account (§5). Running `terraform plan` and `apply` from CI needs more, and `roles/owner` would be more than that. The module therefore also grants, on the project: `roles/editor` (create and change the resources), `roles/iam.securityAdmin` and `roles/resourcemanager.projectIamAdmin` (the IAM bindings this module sets on the project, the service accounts, the secrets, the bucket and the Cloud Run service, which editor cannot), `roles/secretmanager.admin` (secrets and their IAM), `roles/iam.workloadIdentityPoolAdmin` (the pool and provider); and `roles/storage.objectAdmin` on the state bucket. Some of these overlap; each is named so the intent is readable. An account that can change IAM is powerful, which is what the `nonprod` environment's approval is for.

## Notes

- Providers are pinned with `~>` to the `google`/`google-beta` 7.x major (validated against 7.46.1) and `random` 3.x; `.terraform.lock.hcl` carries the checksums for Linux (CI) and macOS. If `terraform init` on another platform rejects the lock file, extend it: `terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64`. `google-beta` is declared but nothing uses it yet.
- Cloud Run reaches Cloud SQL through Direct VPC egress on the module's subnet; there is no Serverless VPC Access connector (the `vpcaccess` API is still enabled, as §5 lists it).
- Tearing an environment down is deliberately hard: the Cloud SQL instance carries both Terraform's `deletion_protection` and Cloud SQL's own `deletion_protection_enabled`, and the Cloud Run service has `deletion_protection`. Set them to `false`, apply, then destroy. The private services peering can only go once the instance is gone.
- The Cloud Armor WAF rules (`sqli`, `xss`, `lfi`, `rce`, `rfi`, `scannerdetection`, `protocolattack`, all `v33-stable`) log in preview; switch `preview` off per rule once the logs show no false positives. The throttle is live from the start.
- If the project sits under an organization with domain-restricted sharing, `roles/run.invoker` for `allUsers` is refused by policy; the load balancer then needs another way to invoke the service. A standalone project has no such policy.
- The Cloud SQL instance name (`supermortgage-app-db`) cannot be reused for about a week after a deletion; another reason not to delete it.
