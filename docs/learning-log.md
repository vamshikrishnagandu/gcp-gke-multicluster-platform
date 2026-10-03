# Learning Log

Every command run during the project: **what it does, why we ran it, and what happened.**
Format per entry: Command -> Explanation -> Result -> Lesson.

---

## Phase 0 - Tooling setup (macOS 11.7 Big Sur, Intel x86_64)

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
