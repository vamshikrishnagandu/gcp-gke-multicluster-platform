# Learning Log

Every command run during the project: **what it does, why we ran it, and what happened.**
Format per entry: Command -> Explanation -> Result -> Lesson.

---

## Current workstation - macOS 26.6, Apple Silicon arm64 (2026-10-03)

This addendum is the current setup. The Phase 0 and M13 notes below describe the previous macOS 11.7 Intel machine and are historical; do not apply their OS-specific workarounds to this Mac.

### Tool installation
| Command | Explanation | Result | Lesson |
|---|---|---|---|
| `sw_vers -productVersion`; `uname -m` | Check macOS version and CPU architecture before choosing binaries | macOS 26.6, `arm64` | Use native Apple Silicon builds; old Intel/Big Sur constraints do not apply |
| Homebrew's official installer | Install the macOS package manager | Homebrew installed under `/opt/homebrew` | Homebrew is the base for installing and updating local tools |
| `brew install tfenv kubectl python@3.12 pipx gh terraform-linters/tap/tflint` | Install Terraform version management, Kubernetes CLI, app Python, isolated Python CLI installs, GitHub CLI, and Terraform linting | `kubectl` 1.37.1, Python 3.12.15, `gh` 2.102.0, TFLint 0.64.0; pipx 1.17.10; tfenv 3.2.2 | TFLint is now distributed through the Terraform-Linters tap, not Homebrew core |
| `tfenv install 1.16.5`; `tfenv use 1.16.5` | Install and select the current Terraform release used by this checkout | Terraform 1.16.5; SHA256 matched | Use the same Terraform version locally and in CI |
| `brew install --cask google-cloud-sdk`; `gcloud components install gke-gcloud-auth-plugin` | Install Google Cloud CLI and the `kubectl` credential plugin | gcloud 587.0.0; GKE auth plugin 0.5.19 | Set `CLOUDSDK_PYTHON` to Homebrew Python 3.12 because macOS's Python 3.9 is too old for this gcloud release |
| `brew install --cask docker`; `open -a Docker` | Install and start Docker Desktop, which provides the local container engine | Docker client/server 29.8.1; `docker info` reports `aarch64` | The Docker CLI alone is not the engine; Docker Desktop must be running for builds |
| `pipx install checkov --python /opt/homebrew/bin/python3.12` with `PIPX_HOME="$HOME/.local/pipx"` | Install the IaC security scanner in an isolated environment | Checkov 3.3.22 | Keep pipx environments out of paths containing spaces so generated launchers work |
| `python3.12 -m venv apps/.venv`; `apps/.venv/bin/python -m pip install -r apps/requirements.txt ruff` | Create an app-local Python environment and install pinned dependencies plus the CI linter | Installed under the Git-ignored `apps/.venv/` | Keep project packages isolated from macOS Python |

### Terraform and validation
- Removed the Big Sur-only `random` provider cap in the production environment and its data/security modules; `~> 3.6` now permits current compatible v3 releases. `terraform init -backend=false -upgrade` selected `random` 3.9.1 and Google provider 6.50.0.
- Updated both Terraform GitHub Actions jobs from Terraform 1.12.2 to 1.16.5.
- `terraform validate` passed for production and bootstrap; `terraform fmt -check -recursive terraform` passed.
- TFLint passed; both Helm charts linted/rendered and passed Kubernetes server-side dry-runs; Ruff and both apps' Flask smoke tests passed.
- The initial Checkov run reported 178 passes and 18 failures because its static parser could not see Cloud SQL flags emitted by dynamic blocks, and did not recognize the dynamic Cloud Armor CVE rule. The flags were made explicit without changing values, and the `cve-canary` rule was made explicit at Cloud Armor's default sensitivity. The final scan reports 195 passed and 0 failed; `CKV_GCP_125` is documented as a scanner interpolation exception for the exact repository/subject-restricted WIF condition.
- `gcloud auth login` and `gcloud auth application-default login` completed for local CLI and Terraform credentials; the ADC quota project and gcloud default were set to the existing platform project.
- Confirmed the existing GCS state bucket and `envs/prod/default.tfstate`; initialized the production backend without migrating or changing state.
- The first partial production apply exposed two issues: fleet/security IAM ran before the GKE Workload Identity pool existed, and Memorystore read replicas rejected the configured 1 GB size (minimum 5 GB). Split the GKE/Binary Authorization dependency from Workload Identity IAM, and disabled optional Redis read replicas while retaining the 1 GB Standard HA cache.
- The final production apply completed: 101 resources added overall, 0 changed, 0 destroyed. Both clusters are active; Gateway IP is `34.111.154.24`. The Terraform output reported Redis at `10.100.46.220` and registry `us-docker.pkg.dev/gke-mc-platform-100324148/apps`.
- On Apple Silicon, built and pushed `app1` and `app2` as `manual-1` with `--platform linux/amd64`. The deployment script stopped because neither cluster had the `net.gke.io` ServiceExport API. Applied the remaining app manifests without ServiceExport to both clusters: all four deployments reached 3/3 replicas, and health/root routes returned HTTP 200 in every cluster.
- MCS was `ACTIVE` and both memberships were `OK`, but the `ServiceExport`/`ServiceImport` APIs and importer pods were initially absent. Enabled Connect Gateway and created the MCS, GKE Hub, and Connect Gateway service identities with their documented roles; corrected the importer principal to the documented Workload Identity form. MCS later reconciled in both clusters (see the next entry).
- MCS later reconciled in both clusters. `ServiceExport` conditions are initialized/exported, ServiceImports exist for both apps in both regions, and the global Gateway is programmed at `34.111.154.24` with both HTTPRoutes attached. Public `/app1/` and `/app2/` requests returned HTTP 200; `/app2/orders` returned HTTP 200 and called app1 in `us-east1` from app2 in `us-central1`.
- Verified all four application HPAs report CPU metrics and maintain 3 replicas; app1 and app2 Gateway NEGs report healthy endpoints in both regions; Cloud Logging receives app request logs and BigQuery export tables exist.
- Added multiregion uptime checks for `/app1/healthz` and `/app2/healthz`, alert policies, and an email notification channel for `vamshik@gmail.com`. The channel exists but is not verified yet; complete the verification link from Google's email before relying on notifications.
- Binary Authorization is enforced. Both `manual-1` image digests passed remote scanning with zero CRITICAL findings and have attestations from `build-attestor`; temporary user KMS signing access was removed afterward.
- Added a regional `us-east1` Artifact Registry recovery repository with immutable tags and retention policies. Mirrored both signed `manual-1` images into it. CI now builds, mirrors, and attests future images in the primary and recovery registries.
- The GitHub WIF provider now restricts subjects to this repository's `pull_request` and `environment:prod` jobs; the live provider and bootstrap source were both updated.
- Connected Grafana Cloud stack `mellowbookcase167` to BigQuery using a credential-only key that impersonates `grafana-reader`; the data source Save & test succeeded. Imported `grafana/dashboards/platform-overview.json`, mapped `DS_BIGQUERY`, set the project variable to `gke-mc-platform-100324148`, and saved that value as the dashboard default.
- Corrected Grafana SQL field paths to match the live BigQuery sink schema: application `httpRequest.status` is top-level, and load-balancer Cloud Armor fields live in `jsonpayload_type_loadbalancerlogentry`. BigQuery dry-runs validated the corrected paths and affected Grafana panels now return series. Kubernetes resources are managed with Helm.
- Bootstrap now declares the Connect Gateway API and uses the Google Beta provider's service-identity resource for Connect Gateway, GKE Hub, and MCS. Bootstrap validation passed; no bootstrap apply was run because this clone has no bootstrap state.
- CI is configured to scan, sign, mirror, and deploy future release images; the current `manual-1` images were scanned and attested manually in both registries. The platform remains deployed and may incur ongoing GCP charges.
- Migrated Kubernetes source of truth from Kustomize to Helm 4.3.0 charts (`charts/app`, `charts/gateway`). Server-side dry-runs passed in both clusters. The first adoption hit a server-side apply field-manager conflict on a NetworkPolicy; `--take-ownership --force-conflicts` resolved it, all five Helm releases report `deployed`, all four app rollouts are healthy, and `/app2/orders` still returns HTTP 200 across regions.
- Updated `scripts/deploy.sh` and the apps workflow to use Helm, lint/render both charts in CI, configure both Artifact Registry hosts, and preinstall the gcloud `local-extract` component before remote scans. Removed the superseded Kustomize manifest files to leave one Kubernetes source of truth.
- Fixed the first GitHub Actions runs: GitHub's immutable OIDC subject format required trust checks on repository/owner IDs and event/ref/environment claims; Terraform CI needed `cloudkms.publicKeyViewer` to read the attestor key; app CI needed the gcloud `beta` component for attestation. Terraform plan errors had been masked by `tee`, so `pipefail`, required-input checks, and a no-deletions guard now prevent incomplete or destructive plans from reaching apply. Configured `GATEWAY_IP` as a repository variable and `ALERT_EMAIL` as an encrypted repository secret. Cloud credentials are restricted to `main` jobs in the `prod` environment; PRs run static checks only because OIDC `pull_request` claims cannot distinguish fork PRs.
- Enabled managed Cloud Service Mesh with automatic control-plane management on both Fleet memberships. Added managed-mesh API and GKE Hub IAM prerequisites to bootstrap. Updated Helm app namespaces for sidecar injection and corrected the legacy `preStop` hook to a valid exec handler. The mesh does not create an Envoy cluster for `.svc.clusterset.local`; `deploy.sh` now reads the MCS `derived-service` annotation and passes the mesh-compatible ServiceImport hostname to app2. CI-deployed app1/app2 pods are 2/2 ready in both clusters; `/app2/orders` returns HTTP 200. Managed mesh is billed per client (currently about $0.50/client-month under standalone pricing; check Cloud Billing for the applicable plan).
- Added a Google Cloud Monitoring datasource to Grafana using the credential-only JWT identity with `grafana-reader` impersonation. Grafana Save & test succeeded, and the overview dashboard now includes Managed Prometheus PromQL panels for request rate, 5xx rate, and p95 latency alongside the BigQuery panels.
- Final app workflow for commit `6393ea4` passed tests, chart lint/render, image builds, scans (zero CRITICAL findings), Binary Authorization attestations, and deployment. Both clusters show all app Deployments at 3/3 ready; the app pods are 2/2 with Envoy sidecars, all Helm releases are deployed, and public `/app1/items` and `/app2/orders` routes return HTTP 200.
- Memorystore remains a 1 GB regional `STANDARD_HA` primary with zonal failover. Added a Cloud Scheduler export every 12 hours to a versioned US multi-region bucket with 30-day archived-generation retention, plus an opt-in `us-east1` cold-restore instance. No always-on secondary cache is provisioned. RPO is up to 12 hours after a successful export; restore RTO is provisioning plus import and is not yet measured. The apps currently do not consume Redis.
- Enabled Cloud Scheduler and deployed the Redis RDB export job, versioned US bucket, and export-only service identity. The first export exposed a missing bucket metadata permission; added `roles/storage.bucketViewer` for the Memorystore persistence identity. Both a manual export and a Scheduler-triggered export then completed; two 225-byte generations are retained because the current app workloads do not populate Redis. The `us-east1` restore instance remains disabled, and a post-apply Terraform plan reported no changes.
- Resent the Google Cloud Monitoring notification-channel verification email through the API. The channel remains enabled and attached to all four alert policies, but the recipient still needs to click Google's verification link.

## Phase 0 - Tooling setup (historical: macOS 11.7 Big Sur, Intel x86_64)

### 0.1 Check what is installed
```bash
for t in brew gcloud terraform docker kubectl gh tflint checkov git; do
  printf "%-10s " $t
  (command -v $t >/dev/null && ($t --version 2>/dev/null | head -1)) || echo "NOT INSTALLED"
done
uname -m
```
- `command -v X` - is program X on the PATH (the folders the shell searches)?
- `X --version | head -1` - print only the first line of the version output.
- `uname -m` - CPU architecture. `x86_64` = Intel, `arm64` = Apple Silicon.
- **Result:** brew, docker, kubectl OK; terraform crashed; gcloud, gh, tflint, checkov missing. CPU is x86_64.
- **Lesson:** x86_64 matches GKE nodes (amd64), so local Docker images would run on GKE as-is.

### 0.2 Old Terraform crashed
```bash
terraform version   # -> fatal error: MSpanList_Insert
sudo rm /usr/local/bin/terraform
```
- The binary was compiled with an old Go version that is incompatible with newer macOS.
- `sudo` = run as administrator (needed because `/usr/local/bin` is protected).

### 0.3 Homebrew repair
```bash
brew tap hashicorp/tap           # failed: homebrew-core is a shallow clone
brew untap --force homebrew/core # remove stale local copy of the package index
brew update                      # Homebrew 7.x now uses its JSON API instead
```
- A **tap** = an extra package repository for Homebrew.
- A **shallow clone** = a git copy without full history; GitHub asked Homebrew to stop updating these.

### 0.4 Discovering the macOS version limit
```bash
brew install hashicorp/tap/terraform  # installs 1.16, but: dyld: Symbol not found ... built for Mac OS X 12.0
sw_vers                                # ProductVersion: 11.7.11
```
- **dyld** = the macOS dynamic linker; it loads system libraries when a program starts.
  "Symbol not found" = the program calls an OS function that does not exist in macOS 11.
- Homebrew no longer builds packages on macOS 11 (Tier 3 = unsupported).
- **Lesson:** every binary has a minimum OS version. Check it before installing:
```bash
otool -l <binary> | grep minos   # minos 10.13 / 11.0 = OK on Big Sur; 12.0+ = will fail
```

### 0.5 Installing macOS-11-compatible versions
```bash
# Terraform 1.12.2 straight from HashiCorp (zip = single binary)
curl -sSLO https://releases.hashicorp.com/terraform/1.12.2/terraform_1.12.2_darwin_amd64.zip
unzip terraform_1.12.2_darwin_amd64.zip && mv terraform /usr/local/bin/

# GitHub CLI 2.65.0
curl -sSLO https://github.com/cli/cli/releases/download/v2.65.0/gh_2.65.0_macOS_amd64.zip
unzip gh_2.65.0_macOS_amd64.zip && mv gh_2.65.0_macOS_amd64/bin/gh /usr/local/bin/

# tflint 0.50.3
curl -sSLO https://github.com/terraform-linters/tflint/releases/download/v0.50.3/tflint_darwin_amd64.zip
unzip tflint_darwin_amd64.zip && mv tflint /usr/local/bin/
```
- `curl -sSLO` - download: `-s` silent, `-S` show errors, `-L` follow redirects, `-O` keep remote filename.

### 0.6 Google Cloud CLI
```bash
curl -sSLO https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-x86_64.tar.gz
tar -xzf google-cloud-cli-darwin-x86_64.tar.gz      # x=extract z=gunzip f=file
export CLOUDSDK_PYTHON=/usr/local/bin/python3.12    # default python3 (3.6) is broken
~/google-cloud-sdk/install.sh --quiet --path-update=true --rc-path="$HOME/.bash_profile"
echo 'export CLOUDSDK_PYTHON=/usr/local/bin/python3.12' >> ~/.bash_profile
```
- gcloud is written in Python; `CLOUDSDK_PYTHON` tells it which interpreter to use.
- `~/.bash_profile` runs on every new terminal, making the setting permanent.

### 0.7 GKE auth plugin (kubectl -> GKE login)
```bash
gcloud components install gke-gcloud-auth-plugin   # current build needs macOS 12
# replaced with the Jan-2025 build (minos 11.0):
curl -sSL https://dl.google.com/dl/cloudsdk/channels/rapid/components/google-cloud-sdk-gke-gcloud-auth-plugin-darwin-x86_64-20250117151628.tar.gz | tar -xz
cp bin/gke-gcloud-auth-plugin ~/google-cloud-sdk/bin/
```
- ⚠️ `gcloud components update` would restore the incompatible version - re-apply this if it happens.

### 0.8 checkov (IaC security scanner) in a virtual environment
```bash
python3.12 -m venv ~/.venvs/checkov
~/.venvs/checkov/bin/pip install checkov
ln -sf ~/.venvs/checkov/bin/checkov /usr/local/bin/checkov
```
- **venv** = an isolated folder of Python packages so tools don't conflict.
- `ln -sf` = create a symbolic link (shortcut) so `checkov` works from anywhere.

### 0.9 Authentication
```bash
gcloud auth login                       # YOU -> gcloud commands
gcloud auth application-default login   # ADC: credentials file Terraform reads
gh auth login                           # GitHub CLI
gcloud billing accounts list            # find billing account ID for Terraform
```
- **ADC (Application Default Credentials)** = a well-known credential file
  (`~/.config/gcloud/application_default_credentials.json`) that Google client libraries, including the
  Terraform Google provider, pick up automatically.

### 0.10 Repository
```bash
git init -b main                                   # create local repo, default branch "main"
gh repo create vamshikrishnagandu/gcp-gke-multicluster-platform --public --source=. --remote=origin
gh label create issue-encountered --color D93F0B   # labels used to categorise Issues
```
- `.gitignore` excludes Terraform state, `*.tfvars` and key files - they can contain secrets.
- `.terraform.lock.hcl` **is** committed: it pins exact provider versions for reproducible builds.

---

## Phase 1 - Writing the code (all roles)

### Mistakes caught during design / code review
| # | Mistake | Why it was wrong | Fix | Lesson |
|---|---|---|---|---|
| M1 | Logged `deny-all` firewall with no internal allow rule | GKE only opens a cluster's **own** pod range; app2 in us-central1 -> app1 pod in us-east1 (MCS) would be silently dropped | `allow-internal` rule for all node + pod CIDRs | A "secure default" can break features; trace every flow through the firewall |
| M2 | Assumed `sort(["usc1","use1"])` gives `use1` first | Strings compare character by character: `c` < `e`, so `usc1` comes first | Config cluster = `gke-usc1`; `deploy.sh` can override it with `CONFIG_CLUSTER` | Check assumptions with `terraform console` (`> sort(["usc1","use1"])`) |
| M3 | Wrote Kustomize JSON-patch "templating" for two apps | Hard to read and fragile (patch paths break when the YAML changes) | Explicit manifests per app | Optimise for readability; two copies beat a clever abstraction |
| M4 | Catch-all Flask `errorhandler(Exception)` | It also caught `NotFound`, so 404s became 500s and fake errors showed up in Error Reporting | Pass `HTTPException` through | Test the unhappy paths (the CI smoke test now asserts that a missing page returns 404) |
| M5 | gunicorn `--access-logformat ''` | Printed blank lines; the app already writes JSON access logs | Removed the flag | One log line per request, in one format |
| M6 | Passed `psa_connection` into a module and used `depends_on = [var.x]` | `depends_on` only accepts resources/modules, not variables | `depends_on = [module.network]` at the caller | Module-level `depends_on` is the tool for ordering across modules |
| M7 | Grafana resource panel planned on log data | Logs contain no CPU/memory samples | Enabled GKE usage metering -> BigQuery `gke_usage` | Make sure the data exists before designing the panel |
| M8 | Alert policy written in MQL | MQL is deprecated for new alert policies | Rewritten in PromQL | Check deprecation notices in the provider docs |
| M9 | LB health check left at the default `GET /` | The apps answer `/` with 404, so every backend looked UNHEALTHY and the LB returned 502s | `HealthCheckPolicy` pointing at `/appN/healthz` | Health check path = a path the app actually serves |
| M10 | CI SA lacked `ondemandscanning` + `compute.viewer` | Vulnerability gate and Gateway IP lookup would get 403 | Roles added in bootstrap | List every gcloud call a pipeline makes and map it to a role |
| M11 | Added a new argument to `module "gke"` by hand, so the `=` signs no longer lined up | CI runs `terraform fmt -check`, so the first push would have failed on whitespace alone | Realigned (normally: run `terraform fmt -recursive terraform` before every commit) | Run the formatter locally before committing; better still, add a pre-commit hook |
| M12 | GCP jobs in CI ran before bootstrap existed | The first push would fail with "workload_identity_provider is required", a red build that tells you nothing | Jobs that need GCP now run only `if: vars.GCP_WIF_PROVIDER != ''`; lint and tests still run on every push | Make CI degrade gracefully when its prerequisites don't exist yet |

### Concepts learned
- **NEG (Network Endpoint Group):** the LB targets pod IPs directly, skipping node ports and an extra hop.
- **Fleet:** a group of clusters treated as one. Same namespace + same name = the same service ("namespace sameness").
- **ServiceExport / ServiceImport:** exporting a Service makes `<svc>.<ns>.svc.clusterset.local` resolve to pods in every cluster.
- **Binary Authorization:** an admission check. A pod is allowed only if its image *digest* carries a valid signature from our attestor.
- **Partitioned log tables:** BigQuery only scans the days in the query's time range, which keeps cost proportional to what you ask for.
- **etcd backups on GKE:** Google manages etcd, so you can't reach it directly. Backup for GKE is the supported equivalent.

---

## Phase 2 - Apply to GCP
_Append entries here while running the [setup guide](devops/setup-guide.md): command -> what it did -> result -> lesson. Open an `issue-encountered` GitHub Issue for every error._

### 2.1 Bootstrap (2026-10-03)
| Step | Command | Result |
|---|---|---|
| Billing account | `gcloud billing accounts list` | `01FE8D-...` is OPEN and billed in USD, so `budget_currency = "USD"` |
| Plan | `terraform plan -out tfplan` | 65 to add (project, 34 APIs, state bucket, WIF, 2 CI SAs + 21 roles, budget) |
| Apply | `terraform apply tfplan` | Project `gke-mc-platform-100324148` created |
| GitHub variables | `terraform output -raw gh_variable_commands \| bash` | 5 repo variables set, so the GCP jobs in CI are now active |

### 2.2 Prod env plan
| # | What went wrong | Symptom | Fix | Lesson |
|---|---|---|---|---|
| M13 (historical Big Sur issue; resolved for current macOS) | `random ~> 3.6` resolved to v3.9.1, which needs **macOS 12+**; the previous laptop ran macOS 11.7 | On Big Sur, `terraform validate` failed to load plugin schemas and the provider binary reported a missing Security.framework symbol | Temporarily pinned `random` to `~> 3.6.0` (v3.6.3); on macOS 26.6 this cap is removed and v3.9.1 validates | Provider OS requirements matter; keep compatibility workarounds only as long as the supported machines need them. Commit `.terraform.lock.hcl` so CI and developers use reproducible provider builds |

Result after the fix: `Plan: 101 to add, 0 to change, 0 to destroy.`
