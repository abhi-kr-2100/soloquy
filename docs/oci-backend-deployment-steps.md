# Soloquy Backend — Deployment Guide (for implementation)

A Spring Boot **GraalVM native image**, built reproducibly with **Nix**, shipped to
**OCIR**, and run on an OCI **Ampere A1** Always-Free VM via an **Instance Principal**.
Each step is small and ends with a **verification command** you can run on its own — no
step depends on a later one to confirm success.

## Core rule

- **Allowed manual action:** create the OCI account (phase 3, step 1).
- **Forbidden manual actions:** VCN, security list, A1 instance, OCIR repo, IAM.
- Terraform is the **only** thing that creates/destroys those. Keep this so the setup
  stays reproducible and tear-down is one command.

---

## Phase 1 · Local prerequisites

### 1.1 Decide how infra is owned
**Why:** The only manual action is creating the OCI account. Every piece of infra below is
created by Terraform — you never click-create the A1 VM, OCIR repo, or network in the
Console.

```
# Allowed manual action : create the OCI account (phase 3, step 1).
# Forbidden manual actions : VCN, security list, A1 instance, OCIR repo, IAM.
#   Terraform is the only thing that creates/destroys those.
```

**Verify (independent):** No check needed yet — just commit to the rule.

### 1.2 Install Nix with flakes enabled
**Why:** The whole build is defined in `flake.nix` (GraalVM 25, Gradle 9, dockerTools).
Without Nix + flakes you cannot reproduce the image.

```sh
sh <(curl -L https://nixos.org/nix/install) --daemon
```

**Verify (independent):**
```sh
nix --version   # expect >= 2.4
nix flake --help   # confirms "flake" experimental command is available
```

### 1.3 Confirm experimental features & unfree allowed
**Why:** `graalvm-oracle_25` is unfree and `flake.nix` needs the flake command.

```sh
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes
allow-unfree = true' > ~/.config/nix/nix.conf
```

**Verify (independent):**
```sh
nix config show | grep -E 'experimental-features|allow-unfree'
```

### 1.4 Clone the repo and enter the dev shell
**Why:** The dev shell provides `docker`, `oci-cli`, `terraform`, and `GRAALVM_HOME` —
everything the steps below use.

```sh
git clone <your-repo-url> soloquy && cd soloquy
nix develop
```

**Verify (independent):**
```sh
ls flake.nix
which docker oci terraform   # all resolve inside the shell
```

> Stay inside `nix develop` for every step that uses docker / oci / terraform.

---

## Phase 2 · Build & test the image locally

### 2.1 Build the backend Docker image
**Why:** `nix build .#backend` compiles the GraalVM native binary (`nativeCompile`) and
packages it into a JDK-free image exposed on 8080.

```sh
nix build .#backend
```

**Verify (independent):**
```sh
ls -la result   # a Docker image archive (tar)
```

### 2.2 Load the image into Docker
**Why:** `result` is an archive; Docker needs it imported before you can run a container.

```sh
docker load -i result
docker tag soloquybackend:latest soloquybackend:local
```

**Verify (independent):**
```sh
docker images | grep soloquybackend
```

### 2.3 Run the container
**Why:** Confirms the native binary actually boots and listens on 8080 before paying for anything.

```sh
docker run -d -p 8080:8080 --name sq soloquybackend:local
```

**Verify (independent):**
```sh
docker ps --filter name=sq   # STATUS Up
```

### 2.4 Smoke-test the endpoint
**Why:** Proves the binary serves `/hello` — the exact request the live VM will receive.

```sh
curl http://localhost:8080/hello
```

**Verify (independent):**
```sh
# response body should contain "hello"
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/hello   # expect 200
```

> Stop the container when done: `docker rm -f sq`.

---

## Phase 3 · OCI account & CLI setup

### 3.1 Create an OCI account (Always Free)
**Why:** The A1 VM and OCIR live in a tenancy. The Always-Free tier includes Ampere A1
capacity (4 ARM cores) + OCIR storage. You only sign up here — you do **not** create the
VM, repo, or network by hand; Terraform does, later in phase 6.

```
Sign up at cloud.oracle.com → choose "Always Free"
```

**Verify (independent):** You can open the Console and see "Tenancy" in the top-right menu.

### 3.2 Configure the OCI CLI
**Why:** The CLI is already in the dev shell. Later `oci` verify commands and the OCIR login
read your tenancy, region, and namespace from this config — you do **not** copy those values
into notes or env vars. The A1 VM itself authenticates via Instance Principal (no CLI needed
on it).

```sh
oci setup config   # follow prompts; needs a user + API key
```

**Verify (independent):**
```sh
oci iam region list   # returns JSON of regions
```

---

## Phase 4 · PoC GitHub Action — build, tag, release

### 4.1 Create a PoC action that builds, tags & publishes a release
**Why:** Before touching Terraform, prove the image builds reproducibly in CI and is
shippable. This action runs on an **ARM64 runner** (GitHub's free x86_64 runners can't emit
the A1 native binary) whenever code is pushed to the `release` branch, builds with Nix, tags
the image, and publishes it as a downloadable GitHub **Release** asset (a `docker save` tar).

Create `.github/workflows/build-image.yml`:

```yaml
on:
  push: { branches: [release] }   # PoC: run on push to the release branch
jobs:
  build:
    runs-on: arm64                  # self-hosted ARM64 runner
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
      - run: nix build .#backend
      - run: |
          docker load -i result
          docker tag soloquybackend:latest soloquybackend:${{ github.sha }}
          docker save soloquybackend:${{ github.sha }} -o soloquybackend.tar
      - uses: softprops/action-gh-release@v2
        with:
          tag_name: poc-${{ github.sha }}
          prerelease: true
          files: soloquybackend.tar
```

**Verify (independent):**
```sh
git push origin release
# A GitHub Release "poc-<sha>" appears with asset soloquybackend.tar
gh release view "poc-$(git rev-parse HEAD)" --json assets | grep soloquybackend.tar
```

> This PoC publishes a tar to a GitHub Release. Pushing the live image to OCIR is a separate
> step (phase 7) — the VM pulls from OCIR, not from GitHub Releases.

---

## Phase 5 · Separate backend & frontend Terraform workspaces

### 5.1 Split infra into independent backend & frontend workspaces
**Why:** Keep the always-free backend (VM + OCIR + IAM) in its own state, separate from the
frontend (optional load balancer / HTTPS). That way the frontend can change or be torn down
without recreating the backend, and vice-versa.

Create:

```
terraform/backend/   ← owns VCN, security list, A1 instance,
                         OCIR repo, instance-principal IAM
  backend.tf      (state: e.g. backend/terraform.tfstate)
  providers.tf    (oci provider, region from env / .tfvars)
  vcn.tf          (oci_core_vcn + internet gateway + subnet)
  sec.tf          (oci_core_security_list: ingress 8080, egress to OCIR)
  instance.tf     (oci_core_instance A1 + user_data → podman quadlet)
  ocir.tf         (oci_artifacts_container_repository)
  iam.tf          (oci_identity_dynamic_group + pull policy)

terraform/frontend/  ← owns ONLY the optional edge (HTTPS/443)
  backend.tf      (separate state)
  lb.tf           (oci_load_balancer reading backend outputs,
                  e.g. via terraform_remote_state or passed vars)
```

**Verify (independent):**
```sh
terraform -chdir=terraform/backend  workspace list   # shows: default *
terraform -chdir=terraform/frontend workspace list   # shows: default *
# two separate states exist; "default" workspace selected in each
```

> The A1 VM is defined in `terraform/backend/instance.tf` — that is the **only** place the VM
> is ever created.

---

## Phase 6 · Author the backend Terraform config

### 6.1 Author the backend Terraform config
**Why:** These files define the A1 VM, OCIR repo, network and IAM. You only **write** them
under `terraform/backend/` (split in phase 5) — you do **not** run `terraform apply`
yourself. The deploy action in phase 7 runs `terraform apply` automatically on push to
`release`.

Create under `terraform/backend/`:

```
- providers.tf   (oci provider; tenancy/region/user from the CLI config or .tfvars)
- vcn.tf         (oci_core_vcn + internet gateway + subnet)
- sec.tf         (oci_core_security_list: ingress 8080, egress to OCIR)
- instance.tf    (oci_core_instance A1 + user_data pulling image + podman quadlet)
- ocir.tf        (oci_artifacts_container_repository)
- iam.tf         (oci_identity_dynamic_group + policy for Instance Principal)
- outputs.tf     (instance_public_ip, instance_id, security_list_id,
                  pull_policy_id, tenancy_ocid — read by later oci checks)
```

**Verify (independent):**
```sh
terraform -chdir=terraform/backend fmt -check && terraform validate   # parses & validates, no apply
```

> Authoring is the only human action here; provisioning is automated by CI in phase 7.

### 6.2 Confirm the security list (8080 in, no SSH)
**Why:** The VM must accept inbound 8080 and nothing else (no SSH). A wrong rule is the most
common "it won't connect" bug. This is a read-only check you can run after CI has applied (or
fold it into phase 7's provisioning confirmation).

```sh
terraform output -raw security_list_id   # note the OCID
# In Console: VCN → Security Lists → confirm ingress 8080, no 22
```

**Verify (independent):**
```sh
oci network security-list get --security-list-id "$(terraform output -raw security_list_id)" \
  | grep -E '8080|22'   # 8080 present, 22 absent
```

---

## Phase 7 · Deploy via the release-branch GitHub Action

### 7.1 Extend the action to build, push & deploy
**Why:** Now that the Terraform files exist (phase 5–6), a push to `release` must do the
whole deploy: build the image, run `terraform apply` to create the OCIR repo and the A1 VM
(whose first boot will find no image yet), then push the image to OCIR and `SOFTRESET` so the
VM re-pulls the freshly pushed image. After this, you perform **zero** manual deploy steps.

Edit `.github/workflows/build-image.yml` (extend the PoC from phase 4):

```yaml
on:
  push: { branches: [release] }
jobs:
  deploy:
    runs-on: arm64            # self-hosted ARM64 runner (builds the native image)
    env:                      # OCI creds supplied as GitHub secrets
      TF_VAR_tenancy_ocid: ${{ secrets.OCI_TENANCY_OCID }}
      TF_VAR_user_ocid:     ${{ secrets.OCI_USER_OCID }}
      TF_VAR_region:        ${{ secrets.OCI_REGION }}
      TF_VAR_api_key:       ${{ secrets.OCI_API_KEY }}
      TF_VAR_fingerprint:   ${{ secrets.OCI_FINGERPRINT }}
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
      - run: nix build .#backend
      - run: docker load -i result
      - run: |
          terraform -chdir=terraform/backend init -input=false
          terraform -chdir=terraform/backend apply -auto-approve
      - run: |
          NS=$(oci os ns get --query 'data' --raw-output)
          REGION=$(oci iam tenancy get --query 'data.home-region-key' --raw-output)
          docker login "${REGION}.ocir.io" -u "${NS}/${{ secrets.OCI_USER }}" -p "${{ secrets.OCIR_AUTH_TOKEN }}"
          docker tag soloquybackend:latest "${REGION}.ocir.io/${NS}/soloquybackend:latest"
          docker push "${REGION}.ocir.io/${NS}/soloquybackend:latest"
      - run: |
          ID=$(terraform -chdir=terraform/backend output -raw instance_id)
          oci compute instance action --instance-id "$ID" --action SOFTRESET
```

**Verify (independent):**
```sh
git push origin release
# CI run is green; afterwards (locally, against the remote state):
terraform -chdir=terraform/backend output instance_public_ip   # populated by CI apply
oci artifacts container image list -c "$(terraform output -raw tenancy_ocid)" --repository-name soloquybackend
```

> Order matters: `terraform apply` creates the OCIR repo + VM first; the post-push SOFTRESET
> makes the VM re-pull the freshly pushed image (`Restart=always` is the fallback if the first
> boot pulled too early).

### 7.2 Confirm the backend is provisioned
**Why:** Read-only checks that CI's apply actually created what the files describe. None of
these create anything — they only inspect what the deploy action produced.

```sh
# 1) VM is running
oci compute instance list -c "$(terraform output -raw tenancy_ocid)" --lifecycle-state RUNNING
# 2) Instance-Principal pull policy exists
oci policy get --policy-id "$(terraform output -raw pull_policy_id)"
# 3) Quadlet installed by user_data (via OCI Console serial/cloud-shell, no SSH)
#    systemctl status soloquybackend.service  → active (running)
```

**Verify (independent):** policy allows the dynamic group to read repos / use artifacts; unit
active (running).

> The security-list check (8080 in, no 22) is phase 6, step 2 — also a read-only inspection of
> CI's apply.

---

## Phase 8 · End-to-end verification

### 8.1 Hit the live endpoint
**Why:** The whole point — proves image, network, quadlet, and Instance-Principal pull all
worked together.

```sh
IP="$(terraform output -raw instance_public_ip)"
curl "http://${IP}:8080/hello"
```

**Verify (independent):**
```sh
curl -s -o /dev/null -w '%{http_code}\n' "http://${IP}:8080/hello"   # expect 200
```

### 8.2 Verify crash recovery
**Why:** `Restart=always` should bring the service back. A reboot is the safest test.

```sh
oci compute instance action --instance-id "$(terraform output -raw instance_id)" --action SOFTRESET
```

**Verify (independent):**
```sh
# wait ~60s, then:
curl -s -o /dev/null -w '%{http_code}\n' "http://${IP}:8080/hello"   # still 200
```
