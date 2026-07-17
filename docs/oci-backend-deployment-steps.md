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
**Why:** The build system requires Nix with flakes to support reproducible builds and dependencies.
Ensure flakes are available before proceeding.

**Verify (independent):**
The command should resolve to a valid Nix binary and confirm flakes support.

### 1.3 Configure Nix with required features
**Why:** The build needs experimental Nix features and access to unfree packages for GraalVM.

**Verify (independent):**
The configuration should be present and correctly configured.

### 1.4 Clone the repo and enter the development environment
**Why:** The development environment provides all necessary tooling including containerization,
cloud orchestration, and build system components.

**Verify (independent):**
Key tools should be available for later steps.

---

## Phase 2 · Build & test the image locally

### 2.1 Build the backend Docker image
**Why:** The build creates a ready-to-deploy container image using the native GraalVM binary.

```sh
nix build .#backend
```

**Verify (independent):**
Verify the container image archive is successfully created.

### 2.2 Load the image into Docker
**Why:** The build produces a container archive that must be loaded into Docker's local registry.

```sh
docker load -i result
docker tag soloquybackend:latest soloquybackend:local
```

**Verify (independent):**
Confirm the image is available in the local Docker repository.

### 2.3 Run the container
**Why:** This action tests that the image starts successfully and binds to port 8080, confirming the backend is operational before incurring infrastructure costs.

```sh
docker run -d -p 8080:8080 --name sq soloquybackend:local
```

**Verify (independent):**
Check that the Docker container is running and using the allocated port.

### 2.4 Smoke-test the endpoint
**Why:** This basic test confirms that the running backend can handle HTTP requests as expected by production workloads.

```sh
curl http://localhost:8080/hello
```

**Verify (independent):**
Ensure the service responds with the correct HTTP status and content.

> Stop the container when done: `docker rm -f sq`.

---

## Phase 3 · OCI account, API key & CLI setup

### 3.1 Create an OCI account (Always Free)
**Why:** The A1 VM and OCIR live in a tenancy. The Always-Free tier includes Ampere A1
capacity (4 ARM cores) + OCIR storage. You only sign up here — you do **not** create the
VM, repo, or network by hand; Terraform does, later in phase 6.

```
Sign up at cloud.oracle.com → choose "Always Free"
```

**Verify (independent):** You can open the Console and see "Tenancy" in the top-right menu.

### 3.2 Create an API key and configure HCP Terraform variables
**Why:** Terraform runs remotely on HCP Terraform (triggered by GitHub Actions). It
authenticates to OCI via an API key — not via the OCI CLI and not via `~/.oci/config`.
Create an API key for your user in the OCI Console, then set these as workspace variables
in the `soloquy-backend` HCP Terraform workspace (mark `private_key` as sensitive):

- `tenancy_ocid`
- `user_ocid`
- `fingerprint`
- `private_key` (full PEM, with real newlines)
- `region` (e.g. `ap-mumbai-1`)

The A1 VM itself authenticates via Instance Principal at boot (no API key or CLI on the VM).

**Verify (independent):**
All five variables are present in the HCP workspace and a speculative plan succeeds.

### 3.3 Configure the OCI CLI (local verification only)
**Why:** The CLI is already in the dev shell. Post-deploy verification commands in later
phases (`oci network security-list get`, `oci compute instance list`, etc.) read from
`~/.oci/config` on your machine. This is separate from Terraform auth, which uses the HCP
workspace variables above.

**Verify (independent):**
`oci iam region get` succeeds using your local config.

---

## Phase 4 · PoC GitHub Action — build, tag, release

### 4.1 Create a PoC action that builds, tags & publishes a release
**Why:** Before touching Terraform, prove the image builds reproducibly in CI and is
shippable. This action runs on an **ARM64 runner** (GitHub's free x86_64 runners can't emit
the A1 native binary) whenever code is pushed to the `release` branch, builds with Nix, tags
the image, and publishes it as a downloadable GitHub **Release** asset (a compressed image).

Create a CI workflow that orchestrates building, tagging, and releasing the container image.
The workflow will execute automatically when code is pushed to the specified branch.

**Verify (independent):**
Push the code to the target branch and confirm that a release asset is generated, validating that the build produces a deployable artifact.

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
Split the infrastructure into two separate workspaces:
- **Backend workspace**: Owns VCN, security list, A1 instance, OCIR repo, and instance-principal IAM
- **Frontend workspace**: Owns ONLY the optional edge (HTTPS/443) that may depend on backend outputs
```

**Verify (independent):**
```sh
terraform -chdir=terraform/backend  workspace list   # shows separate states
terraform -chdir=terraform/frontend workspace list   # shows separate states
# two separate states exist; "default" workspace selected in each
```

> The A1 VM is defined in the backend workspace — that is the **only** place the VM
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
Create a set of Terraform configuration files that define the complete backend infrastructure
including:
- The OCI provider configuration linked to your tenancy (using API key credentials from HCP workspace variables)
- A VCN with internet gateway and subnet for network connectivity
- Security rules allowing only port 8080 and blocking SSH (port 22)
- An A1 Ampere VM instance with user_data that starts the podman container
  using the built GraalVM image
- An OCIR container repository for image storage
- IAM dynamic group and policy enabling Instance Principal authentication
- Output variables providing instance details (IP, ID) and security list ID
  for later verification steps
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

Extend the CI workflow to orchestrate the complete deployment pipeline. This includes building
the container image, provisioning infrastructure, pushing the image, and triggering a service restart.

The workflow should be configured with OCI credentials in GitHub secrets and execute automatically
upon code pushes to the release branch.

**Verify (independent):**
Push the code to the release branch and confirm that a CI job runs successfully,
validating that the deployment pipeline works end-to-end.

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
**Why:** This critical test validates the entire deployment pipeline — confirming that the container image, network configuration, service orchestration, and Instance-Principal authentication all work together correctly.

The workflow should retrieve infrastructure details (like instance IP) and perform a live endpoint test to prove the backend is accessible and functional.

**Verify (independent):**
Execute a live endpoint test to confirm the HTTP service responds with the expected status code and content.

### 8.2 Verify crash recovery
**Why:** Service resilience is critical. The `Restart=always` mechanism should automatically restart and restart the service after system events, ensuring high availability.

Tests should simulate system reboots or service failures to validate that recovery mechanisms work as expected.

**Verify (independent):**
After triggering a service action, verify that the endpoint remains accessible and functional, confirming the recovery mechanism works correctly.
