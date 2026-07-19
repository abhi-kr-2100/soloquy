# Soloquy Backend — Deployment Guide (for implementation)

A Spring Boot **GraalVM native image**, built reproducibly with **Nix**, shipped to
**OCIR**, and run on an OCI **Always-Free VM** (`VM.Standard.E2.1.Micro`, AMD x86_64) via an
**Instance Principal**.

> **Shape change (was Ampere A1):** the original plan targeted the Ampere A1 (Arm64) Always-Free
> shape, but it is out of capacity in many regions (e.g. `ap-hyderabad-1` returns
> `Out of host capacity` on `LaunchInstance`). The Always-Free x86 replacement is
> `VM.Standard.E2.1.Micro` (1 OCPU / 1 GB, AMD, **x86_64**). This is available in the regions that
> offer Always-Free compute (e.g. `us-ashburn-1`, `eu-frankfurt-1`, `uk-london-1`). Switching to it
> changes the architecture from aarch64 to x86_64, so every Arm-specific piece below is updated:
> the Nix build runs on an x86_64 runner, the OL9 image lookup filters by an x86 shape, and the
> `docker-credential-ocir` binary is the **amd64** build. The E2.1.Micro shape does **not** require
> a `shape_config` block (unlike the A1 Flex), and the 1 GB RAM is sufficient for a single
> stateless GraalVM native container.

> This is a *plan/implementation* guide. It describes **what to build and why**, not the exact
> code. The concrete Terraform, cloud-init, and workflow YAML are written when implementing.

## Core rule

- **Nothing is built or applied from your laptop.** The image is built in a GitHub Action;
  Terraform runs remotely in **HCP Terraform Cloud**. Your machine only ever *inspects*.

---

## Phase 1 · Prerequisites & mental model

### 1.1 Create the OCI account (manual, allowed)
**Goal:** own a tenancy. The Always-Free tier includes an `VM.Standard.E2.1.Micro` (AMD x86_64,
1 OCPU / 1 GB) + OCIR storage. You only sign up — you **not** click-create the VM, repo, or network;
Terraform does that later.

> The E2.1.Micro is Always-Free **only** in the regions that list it under Always-Free compute.
> Confirm your chosen region offers it (the OCI Console "Always Free" resources list shows eligible
> shapes per region). If your region lacks E2.1.Micro, pick a region that has it — and use that
> region's identifier everywhere (3.2, 4.1).

### 1.2 Store all secrets
**Goal:** put credentials where CI/Cloud can use them, never in the repo.

- **HCP Terraform Cloud** workspace `soloquy-backend` (sensitive variables, consumed by the
  remote `terraform` runs): `tenancy_ocid`, `user_ocid`, `fingerprint`, `private_key` (deployer
  API-key PEM), `private_key_pass_phrase`, `region`.

  > **`oci_namespace` and the OL9 image OCID are fetched by Terraform, not stored.** Instead of
  > hardcoded HCP variables, use `data.oci_objectstorage_namespace` (see 3.2) for the namespace and
  > an `oci_core_images` data source filtered by OS and version for the image (see 3.2). These remove
  > the one-time console lookups. Pin to specific HCP variables only if you need byte-for-byte
  > reproducibility for the image (the namespace never changes within a tenancy, so the data source
  > is safe there).
- **GitHub** → Settings → Environments → `release` (used by the Action for the OCIR push and to
  reach HCP): `OCIR_AUTH_TOKEN`, `TF_CLOUD_TOKEN`, `OCIR_USERNAME`, and `CACHIX_AUTH_TOKEN` (so the
  Phase 4.1 `nix build` can use the `soloquy` Cachix cache, as the existing
  `.github/workflows/build-image.yml` already does).
- **GitHub** → Settings → Environments → `release` (fed into the Terraform run, see 4.2):
  `GITHUB_SHA` is passed by the workflow at run time — you do **not** store it as a secret.

> `OCIR_AUTH_TOKEN` / `OCIR_USERNAME` are the **deployer** push credentials used by the GitHub
> Action in Phase 4.1 to push the built image to OCIR. They are **not** placed on the VM — the VM
> pulls via Instance Principal (Phase 3.4) with no static token.
>
> `OCIR_USERNAME` is the **namespace-qualified** OCIR login username in the form
> `<oci_namespace>/<oci-username>` (your console username, **not** the user OCID). For a tenancy
> federated with Oracle Identity Cloud Service, use
> `<oci_namespace>/oracleidentitycloudservice/<oci-username>`. The namespace is the Object Storage
> namespace string (resolved in Terraform via `data.oci_objectstorage_namespace.this.namespace`, or
> from `oci os ns get`), **not** the tenancy display name. The push in Phase 4.1
> tags the image as `<region>.ocir.io/<oci_namespace>/soloquybackend` and logs in with this username
> plus `OCIR_AUTH_TOKEN`.

> One-time lookups you need for the HCP variables: **none remain manual.** `oci_namespace` is
> resolved at apply time via the `oci_objectstorage_namespace` data source (see 3.2), and the
> Oracle Linux 9 x86_64 image OCID is fetched via an `oci_core_images` data source (see 3.2). If
> you prefer to pin a specific image, look it up from the OCI Console / image list (filter by OS and
> version, **not** by shape) and pass it as the `ol9_x86_64_image_ocid` variable instead.

### 1.4 Region naming — two distinct identifiers (read this before Phase 3/4)
OCI uses **two different strings** for the same region, and mixing them up is the single most
common silent failure in this pipeline:

- **Region identifier** (e.g. `us-ashburn-1`, `eu-madrid-1`) — used by the Terraform OCI
  provider, the `region` HCP variable, and the `oci_core_images` data-source lookup for the OL9
  image OCID. The namespace is resolved separately via the `oci_objectstorage_namespace` data
  source.
- **Region key** (e.g. `iad`, `mad`, `phx`) — the short airport code used in the **OCIR
  registry hostname**.

OCIR registry domains accept **three** equivalent forms:

| Form | Example (Ashburn) |
| --- | --- |
| `ocir.<region>.oci.oraclecloud.com` | `ocir.us-ashburn-1.oci.oraclecloud.com` |
| `<region>.ocir.io` | `us-ashburn-1.ocir.io` |
| `<region-key>.ocir.io` | `iad.ocir.io` |

Oracle's own instance-principal credential-helper sample
(<https://github.com/oracle-devrel/oci-automation-hub/tree/main/ocir-credential-helper-sample>)
uses the **`<region-key>.ocir.io`** form (e.g. `fra.ocir.io`, `iad.ocir.io`, `phx.ocir.io`).
This guide follows that form for consistency with the `credHelpers` config and the
`docker pull` in 3.4.

**Rule for this project:** pick **one** form and use it everywhere the registry is referenced —
the GitHub Action push/login (4.1), the VM's `docker pull` (3.4), and the `credHelpers` entry
in `/root/.docker/config.json` (3.4). The Terraform `region` variable stays the **region
identifier** (`us-ashburn-1`). All three host forms resolve to the **same** registry and tenancy
namespace, so a repo created via the region identifier is the same repo reachable via the region
key — the risk of drifting between forms is **auth/config mismatch and confusion**, not a separate
logical registry. Keep the host form identical across the push, the `credHelpers` key, and the VM
pull so Docker routes the credential helper correctly.

> For this guide the examples use the **`<region-key>.ocir.io`** form. So for Ashburn the full
> path is `iad.ocir.io/<oci_namespace>/soloquybackend`. Substitute your real region key. The
> region *identifier* (`us-ashburn-1`) is still what Terraform and `oci os ns get` use.

---

## Phase 2 · PoC build in CI (already exists: `.github/workflows/build-image.yml`)

**Goal:** prove the image builds reproducibly on the **x86_64** runner and is shippable *before*
touching Terraform. The existing action builds with Nix on `ubuntu-24.04` (x86_64), tags the image,
and uploads a tar as a GitHub Release asset. **This workflow is fine to keep as-is for now** — it
validates that the Nix build produces a working image on the x86_64 runner and serves as a manual
escape hatch (the tar can be loaded on any machine). It is intentionally left untouched until the
Phase 3/4 automation is in place.

> This PoC publishes a tar to a GitHub Release. The real deploy pushes the live image to OCIR
> (Phase 4); the VM pulls from OCIR, not from GitHub Releases. The two are complementary, not
> conflicting: the PoC proves the build; Phase 4 wires the push + infra.

> **Deploy workflow (Phase 4):** the backend Terraform config (Phase 3) is **already applied**, so
> the deploy workflow just builds the image, pushes it to the existing OCIR repo, and runs
> `terraform apply` with the new `image_tag` to roll the VM. The existing `build-image.yml` PoC can
> remain as a standalone build check, or be folded into the deploy workflow later.

---

## Phase 3 · Backend Terraform config (authored locally, applied in the cloud)

> **Authoring vs. running:** you *write* these files locally, but you never `apply` from your
> laptop. Validation (`validate`/`plan`) and `apply` happen remotely in HCP Terraform Cloud when
> CI runs. Order matters only so each incremental file still parses.

### 3.1 Workspace + cloud block
**Goal:** point Terraform state at the HCP Terraform Cloud workspace `soloquy-backend` and pin
the OCI provider. Auth comes from the HCP workspace variables, not a local `~/.oci/config`.

### 3.2 Variables (only what is needed)
**Goal:** centralize the few inputs referenced by resources.

- Required: `tenancy_ocid`, `region`.
- Deployer auth (from HCP): `user_ocid`, `fingerprint`, `private_key`.
- Image tag to deploy: `image_tag` (the `${GITHUB_SHA}` fed in by the workflow at run time — see
  4.2 — **not** a stored secret). Defaults to `latest` if unset.
- SSH recovery: `ssh_public_key` (your public key, injected into `user_data`) and
  `debug_ssh_source_cidr` (your IP, used only for the Phase 5 recovery path).

> No `availability_domain` variable: the E2.1.Micro instance auto-selects the first availability
> domain in the region. Removing the explicit AD input keeps the config simple. (Unlike A1, the
> E2.1.Micro is not subject to the intermittent out-of-capacity failures that prompted this plan
> change.)

> No `compartment_id` variable: the backend compartment is **created by Terraform** (3.3), so
> resources reference the created compartment, not a free-floating variable. Removed to avoid an
> unused/confusing input.

> No `oci_namespace` variable: resolve it with the `oci_objectstorage_namespace` data source
> instead of the `oci os ns get` lookup. The namespace is stable per tenancy, so the data source is
> safe:
>
> ```hcl
> data "oci_objectstorage_namespace" "this" {}
>
> # reference as: data.oci_objectstorage_namespace.this.namespace
> ```
>
> No `ol9_x86_64_image_ocid` variable by default — fetch it with an `oci_core_images` data source
> instead of hardcoding the OCID. This matches the "filter by OS and version, not by shape" rule and
> removes the one-time console lookup:
>
> ```hcl
> data "oci_core_images" "ol9" {
>   compartment_id           = var.tenancy_ocid
>   operating_system         = "Oracle Linux"
>   operating_system_version = "9"
>   shape                    = "VM.Standard.E2.1.Micro"
>   sort_by                  = "TIMECREATED"
>   sort_order               = "DESC"
> }
> 
> # reference the newest OL9 image at apply time:
> # data.oci_core_images.ol9.images[0].id
> ```
>
> Caveats: this returns the **newest** OL9 image in the region at apply time, so the image can drift
> between applies (non-deterministic). If you need byte-for-byte reproducibility, fall back to a
> pinned `ol9_x86_64_image_ocid` HCP variable instead of the data source. The data source's
> `compartment_id` is required and uses `var.tenancy_ocid` (root) since platform images live there.

### 3.3 Resources to create (high-level)
**Goal:** every piece of infra, owned by Terraform.

- **Compartment** `soloquy-backend` (isolates all backend resources for easy teardown).
- **VCN** + **internet gateway** + **route table** (`0.0.0.0/0` → IGW) so the VM reaches OCIR and
  package repos.
- **Security list:** ingress TCP `8080` from `0.0.0.0/0`, egress `all` to `0.0.0.0/0`. **Plus a
  temporary SSH ingress (TCP 22) restricted to `debug_ssh_source_cidr`** — added only when
  debugging (see Phase 5). The subnet references this list explicitly, dropping OCI's default
  (SSH-allowing) list.

  > **Security note:** exposing TCP `8080` directly to `0.0.0.0/0` puts the backend on the public
  > internet with no WAF, rate limiting, or TLS termination in front of it. This is acceptable for an
  > initial Always-Free deployment of a stateless API, but before any production or sensitive traffic,
  > front it with an OCI Load Balancer / WAF or place it behind a reverse proxy that terminates TLS
  > and restricts source ranges. The egress `all` rule matches OCI's default and is required so the
  > VM can reach OCIR and package repos on first boot.
- **Subnet** wiring VCN + route table + security list, with a public IP (the VM must serve 8080).
- **Reserved public IP** (`oci_core_public_ip`, `lifecycle = { prevent_destroy = true }`): reserve
  a static reserved public IP and attach it to the instance's **primary private IP**. The
  `oci_core_public_ip` resource attaches via `private_ip_id` (not directly to the instance or VNIC),
  so the sequence is: create the instance → read its primary VNIC's private IP OCID (via
  `oci_core_vnic_attachment` + `oci_core_private_ip`, or the instance's `primary_private_ip`
  attribute) → create the `oci_core_public_ip` with `private_ip_id` set to that OCID. Reserving it
  keeps the backend's address stable across the instance *replacement* that happens on every
  `user_data` change (see 4.2), so DNS / clients don't see a changing IP on each deploy. The
  `oracle-terraform-modules/compute-instance/oci` module handles this wiring for you when its
  `public_ip` input is set to `RESERVED` (see its `instances_reserved_public_ip` example) — prefer
  the module over hand-rolling the attachment if you adopt it. Note: an Always-Free reserved public
  IP is free while attached; it still counts against the regional public-IP quota, so don't reserve
  more than you attach.
- **OCIR container repository** `soloquybackend`, private (created explicitly so the Phase 4.1 push
  targets an existing repo; the VM pulls via Instance Principal). This repo has **already been
  applied**, so Phase 4 simply pushes to it — the deploy just needs the image pushed before the
  `terraform apply` recreates the VM (see Phase 4).

  > **The repo name must match the push target exactly.** The GitHub Action in Phase 4.1 pushes to
  > `<region-key>.ocir.io/<oci_namespace>/soloquybackend` and the VM pulls the same path in 3.4, so
  > the Terraform-created `oci_artifacts_container_repository` **display name must be `soloquybackend`**
  > (case-sensitive). A mismatch here is the most common cause of a "repository does not exist" push
  > failure after the instance boots.
    - **Instance-principal IAM (creation order matters — see note below):** a **dynamic group**
      whose rule matches the *Terraform-created* compartment's instances, and a tenancy-level
      **policy** `Allow dynamic-group <dg> to read repos in tenancy` (the pull permission the VM
      needs). If you later want the VM to also push, widen to `manage repos in tenancy`.

      > **The IAM policy must be tenancy/root-scoped, not compartment-scoped.** The
      > `read repos in tenancy` policy is attached at the **root compartment** (`compartment_id =
      > var.tenancy_ocid`), not at `oci_identity_compartment.soloquy-backend.id`. Attaching it to the
      > backend compartment would make it a compartment-level policy and the pull permission would not
      > apply tenant-wide as required. The dynamic group, by contrast, can live in the root
      > compartment too — its rule already scopes membership to the backend compartment's instances.


     > **Explicit IAM creation order (this is easy to get wrong):** the dynamic group rule
     > references the compartment OCID that Terraform *creates* in the same config (3.3
     > "Compartment"), e.g. `All {instance.compartment.id = '<oci_identity_compartment.soloquy-backend.id>'}`,
     > interpolated in the `.tf` file — **not** a hardcoded OCID you typed by hand. The dynamic
     > group, the policy, the compartment, the repo, and the instance all live in the **same**
     > Terraform config (`terraform/backend/`), which has **already been applied**. On each deploy
     > the instance is replaced (via the `image_tag`/`user_data` change) and re-added to the dynamic
     > group. **IAM policy propagation to the new member can lag by a few minutes**, so the first
     > `docker pull` must retry (handled by the systemd `Restart=on-failure` in 3.4). Do **not**
     > expect the very first boot's pull to succeed instantly.
- **Always-Free compute instance** (`VM.Standard.E2.1.Micro`, 1 OCPU / 1 GB, AMD x86_64) —
  **no `shape_config` block needed** (unlike the A1 Flex, which required it):

  ```hcl
  shape = "VM.Standard.E2.1.Micro"
  ```

  Its `user_data` (cloud-init, 3.4) installs Docker and pulls/runs the **x86_64** image via
  Instance Principal, using the `image_tag` variable. Its `availability_domain` is taken from the
  first entry of `data.oci_identity_availability_domains` for the region (no manual AD input). Its
  `source_details` references `data.oci_core_images.ol9.images[0].id` (the data source from 3.2,
  now filtered by the E2.1.Micro shape) unless you pinned `ol9_x86_64_image_ocid`, in which case use
  that variable. Every resource sets `compartment_id = oci_identity_compartment.soloquy-backend.id`.
  Attach the reserved public IP from above.

  > **Architecture note:** the E2.1.Micro is **x86_64**, not Arm64. So the entire build/push chain
  > must produce an x86_64 image: the Nix `docker load`/`push` must run on an **x86_64** runner
  > (`ubuntu-24.04`, not `ubuntu-24.04-arm`), the GraalVM native build must target `x86_64`, and the
  > `docker-credential-ocir` binary downloaded in 3.4 step 4 must be the **amd64** build. The OL9
  > image data source is also filtered by `VM.Standard.E2.1.Micro` (see 3.2). The 1 GB RAM is enough
  > for a single stateless GraalVM native container (the native image is a small static binary); if
  > memory pressure appears, the native build should still stay comfortably under 1 GB at runtime.

> **Boot volume / disk space is sufficient.** The Always-Free E2.1.Micro instance gets a default
> ~47 GB boot volume (free within the 200 GB Always-Free block-storage allowance). The GraalVM
> native image is a single static binary (tens of MB); even with Docker + the Oracle Linux 9
> base + image layers and log churn, a 47 GB volume leaves ample headroom for our needs. No
> extra block volume is required. If desired, bump `boot_volume_size_in_gbs` to 50 for margin;
> stay well under the 200 GB Always-Free total.

> **Expose Terraform `output`s** for the values needed to inspect/debug the deployment
> (e.g. via SSH to the VM): `ocir_repo_id`, `pull_policy_id`, `instance_id`,
> `instance_public_ip`, and `compartment_id`. These are read from the created resources.
>
> TODO(subtask): add the `output` blocks for the above values to the backend Terraform config.

### 3.4 cloud-init: Docker + OCIR pull (Instance Principal, no static token)
**Goal:** on first boot the VM installs Docker and pulls/runs the image from OCIR **without any
static credential** — authentication to OCIR uses the instance's Instance Principal identity via
Oracle's `docker-credential-ocir` credential helper (see
<https://docs.oracle.com/en/learn/cred-helper/index.html>). No Auth Token, no `docker login`, no
secret in `user_data`. The IAM policy in 3.3 (`allow dynamic-group <dg> to read repos in tenancy`)
grants the pull; the credential helper turns that into a short-lived OCIR token at pull time.

This is a **well-documented, standard OCI pattern** — not a hack. Oracle's own official sample
(`ocir-credential-helper-sample`,
<https://github.com/oracle-devrel/oci-automation-hub/tree/main/ocir-credential-helper-sample>)
does exactly this. The helper is a small binary that talks to OCIR using the OCI SDK's
**Instance Principal** provider (`auth.InstancePrincipalConfigurationProvider()`). The standard
Oracle-provided `docker-credential-ocir` helper **shells out to the OCI CLI** to obtain the
short-lived OCIR token via Instance Principal, so the OCI CLI **must** be installed on the VM
(see step 3 below). If you would rather avoid the CLI dependency, build a helper from the
official sample's own source that uses the OCI SDK directly instead of invoking the CLI.

> **Do NOT build the helper from `github.com/jan-g/ip-credential`.** That is a 1-star,
> community-maintained repo and is **not** the official source. Use the prebuilt
> `docker-credential-ocir` binary that Oracle's `ocir-credential-helper-sample` publishes
> (download it from the sample's release artifacts, pinned to a specific version), or build it
> from the official sample's own source. Either way, **pin the exact version/commit** so the
> boot is reproducible. The binary must be the **amd64** build (the E2.1.Micro instance is x86_64);
> cross-arch is not a concern because it runs on the instance itself.

> **OCI CLI is required for the standard helper.** Step 3 installs it because the standard
> `docker-credential-ocir` helper shells out to the OCI CLI to perform the Instance Principal token
> exchange (`oci iam region list --auth instance_principal` is a quick proof that Instance Principal
> auth works). If you want a leaner first boot, build a helper from the official sample's own source
> that uses the OCI SDK directly and skip the CLI — but keep the CLI install if you use the standard
> helper.

Required cloud-init steps (mirroring the Oracle sample). cloud-init runs as **`root`**, and the
pull/run happen as root, so the Docker `config.json` is written to **`/root/.docker/config.json`**
only (see the root/user note below).

1. **Wait for network**, then OL9 prep: `dnf -y install git dnf-plugins-core`,
   and `dnf -y remove podman-docker || true` (avoids the podman/docker conflict on OL9).

2. **Install Docker** (OL9 uses the Docker CE repo, not the OS package):

   ```sh
   dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
   dnf -y install docker-ce docker-ce-cli containerd.io
   systemctl enable --now docker
   ```

   3. **Install the OCI CLI** (required by the standard `docker-credential-ocir` helper, which
      shells out to it for the Instance Principal token exchange — not optional for that helper):

    ```sh
    dnf -y install oraclelinux-developer-release-el9
    dnf -y install python39-oci-cli
    oci --version   # sanity check
    # proves Instance Principal auth works (no user API key on the VM):
    oci iam region list --auth instance_principal
    ```

4. **Download and install the pinned `docker-credential-ocir` binary** (amd64, from the
   official `ocir-credential-helper-sample` release artifacts — **pin the version**):

   ```sh
   # Pinned download — substitute the real pinned URL/version for your region/artifact.
   # Example shape only; confirm the exact artifact path in the official sample repo.
   curl -fSL -o /usr/local/bin/docker-credential-ocir \
     https://<pinned-url>/docker-credential-ocir-linux-amd64-<PINNED_VERSION>
   chmod 0755 /usr/local/bin/docker-credential-ocir
   which docker-credential-ocir   # -> /usr/local/bin/docker-credential-ocir
   ```

   > If you prefer to build instead of download, build from the **official sample's** source
   > (not `jan-g/ip-credential`), pinning the commit. A prebuilt, pinned binary is preferred to
   > keep first boot fast and avoid a build-on-boot failure surface.

5. **Configure Docker to use the helper, scoped to the registry** (per-registry `credHelpers`,
   never a global `credsStore` — a global `credsStore` would route Docker Hub pulls through the
   OCIR helper and break them). Use the **`<region-key>.ocir.io`** form from 1.4 as the key, and
   write it to **`/root/.docker/config.json`** (root runs the pull, so this is the only path that
   matters — see the note below):

   ```json
   {
     "credHelpers": {
       "iad.ocir.io": "ocir"
     }
   }
   ```

   (Substitute your region key. The key **must** match the registry host used by the push in 4.1
   and the `docker pull` below.)

6. **Pull and run** the image via a **systemd unit** (survives reboot, unlike a bare
   `docker run --restart=always`):

   - `docker pull iad.ocir.io/<namespace>/soloquybackend:<tag>` — authenticates automatically via
     the helper + Instance Principal; **no `docker login`**.
   - Run the container on `8080` with restart-always. Pass the image `<tag>` (the `image_tag` /
     `${GITHUB_SHA}` fed in 4.2) into `user_data` as a Terraform template variable so the unit
     pulls the exact image built in this run.
   - Make the pull/run **retry on failure** (systemd `Restart=on-failure` +
     `RestartSec=`), since the image is pushed *before* the apply (Phase 4) but IAM-policy
     propagation to the newly-replaced dynamic-group member can lag by a few minutes.

   > **Why Instance Principal instead of `docker login` with an Auth Token:** an Auth Token is a
   > long-lived static secret that would have to be baked into `user_data` (visible in instance
   > metadata/console) and rotated by re-applying. Instance Principal stores no static credential on
   > the VM and is the passwordless path Oracle documents for this scenario.

   > **Root vs. service user (important):** Docker resolves the credential helper via the
   > **pulling process's** `$HOME/.docker/config.json`. Because cloud-init runs as `root` and the
   > systemd unit runs the pull as root, only `/root/.docker/config.json` is read — there is no
   > need to write a separate `config.json` for any service account, and doing so gives a false
   > sense of coverage. Run the container as root (the binary is a static GraalVM native image with
   > no need for a dedicated user) or, if you want a non-root runtime user, ensure that user's
   > `~/.docker/config.json` is created too. The simplest correct setup is: everything as root,
   > single `/root/.docker/config.json`.

   > **Robustness note (planning for later, not blocking):** fetching the helper binary at boot
   > adds an outbound dependency on the artifact host. The cleaner long-term option is to bake a
   > **custom OL9 image** (with Docker and the pinned helper preinstalled) via Packer/Image Build,
   > and have `user_data` do only the pull/run. This is listed as a future improvement; the
   > download-at-boot approach is the initial implementation.

> **`user_data` size limit — flagged.** OCI `metadata`/`user_data` is capped at **32,000 bytes**
> total, and cloud-init's own (gzip) payload limit is ~16,384 bytes. The script above (Docker +
> tool install + download + systemd unit) plus the embedded `image_tag` stays well under this, but
> keep cloud-init minimal and avoid embedding large heredocs. If it grows past ~14 KB, offload the
> script to a file in OCI Object Storage and have `user_data` merely `curl | bash` it (the VM
> already has outbound internet via the route table in 3.3).

---

## Phase 4 · Deploy workflow (GitHub Action)

**Goal:** one push to `release` builds the image, pushes it to the **already-existing** OCIR repo,
and runs `terraform apply` so the VM picks up the latest image — all in CI, nothing local.

Trigger: `on: push: { branches: [release] }`, `environment: release`,
`runs-on: ubuntu-24.04` (x86_64, to match the E2.1.Micro VM).

### The infra already exists — this is a three-step flow

The backend Terraform config under `terraform/backend/` has **already been applied**, so the OCIR
repo (`soloquybackend`), the compartment, network, IAM, and the VM instance all exist. The old
"two-apply" ordering dance (create-repo-first, then push, then create-the-rest) is **no longer
needed**: the repo is already there to push to. The deploy is simply:

1. **Build the image** (4.1) on an x86_64 runner with Nix.
2. **Push the image** (4.1) to the existing OCIR repo.
3. **`terraform apply`** (4.2) with the new `image_tag = ${GITHUB_SHA}`. Changing `image_tag`
   changes the instance `user_data`, which replaces the VM so its cloud-init pulls and runs the
   image that was just pushed.

Because the image is pushed in step 2 *before* the apply in step 3, the recreated instance's first
boot always finds the image. Keep the **registry host form identical** across the push and the
instance pull (see 1.4).

### 4.1 Build & push the image
**Goal:** produce the **x86_64** native image (the `ubuntu-24.04` x86_64 runner matches the
E2.1.Micro VM) and push it to OCIR.

- The `ubuntu-24.04` (x86_64) GitHub-hosted runner already has Docker preinstalled, so `docker load` /
  `docker push` work without an extra setup step.
- `nix build .#backend` (with the cachix action, using the `CACHIX_AUTH_TOKEN` secret), `docker load -i result`.
- Tag as `<region-key>.ocir.io/<oci_namespace>/soloquybackend:${GITHUB_SHA}` and
  `<region-key>.ocir.io/<oci_namespace>/soloquybackend:latest`. (The Nix image is
  already tagged `soloquybackend:latest`; re-tagging under the full OCIR path is what makes the
  push work.)
- `docker login <region-key>.ocir.io` with `OCIR_AUTH_TOKEN` (a **deployer** auth
  token — this is the GitHub Action pushing to OCIR, *not* a credential on the VM); the username is
  the `OCIR_USERNAME` secret (`<oci_namespace>/<oci-username>`, **not** the user OCID; federated
  tenancies use the `.../oracleidentitycloudservice/...` form). `docker push` both tags.

> `<region-key>` is the short airport code (e.g. `iad` for Ashburn, `phx` for Phoenix). This is the
> **`<region-key>.ocir.io`** form chosen in 1.4 and must match the `credHelpers` key and the VM's
> `docker pull` exactly. The Terraform `region` variable and the `oci_core_images` data-source
> lookup for the OL9 image OCID still use the region *identifier* (`us-ashburn-1`). Pass
> `<region-key>` into the workflow as an env var so the tag, login, and push all use the same
> registry host as the VM instance pulls from.

### 4.2 Apply infra — single `terraform apply` with the new image tag
**Goal:** run `terraform apply` against the existing `terraform/backend/` config so the VM is
recreated pulling the image just pushed in 4.1.

Use the **recommended `hashicorp/tfc-workflows-github` actions**
(`upload-configuration` → `create-run` → `apply-run`), pointing at `directory: terraform/backend`
(set `CONFIG_DIRECTORY`). `create-run` plans and `apply-run` applies — the supported
non-interactive flow, so **do not** run a separate `terraform plan` step. The deployer auth for
the Terraform run comes from the HCP workspace variables (`TF_CLOUD_TOKEN` / `TF_API_TOKEN`
secret), **not** from any credential on the VM. (A raw `terraform apply` in CI works too if you
prefer, but the TFC actions match the workspace's remote-state config in `terraform.tf`.)

**Feeding the image tag into the run.** The VM must pull the exact image built in *this* workflow
run, so `${GITHUB_SHA}` must reach Terraform as the `image_tag` variable — set
`image_tag = "${{ github.sha }}"` on the run. Since `image_tag` feeds the instance `user_data`,
changing it replaces the VM, whose cloud-init then pulls `.../soloquybackend:${GITHUB_SHA}`. The
image already exists in OCIR (pushed in 4.1), so the recreated instance's first boot finds it and
serves immediately. (The cloud-init pull also retries, so a brief IAM policy-propagation delay is
absorbed.)

That is the whole deploy: **build → push → apply**. No repo-only pre-apply, no per-resource
targeting, no ordering gymnastics — the infra and repo already exist.

> **`user_data` replacement behavior:** changing `user_data` on `oci_core_instance` forces Terraform
> to **replace** (destroy + recreate) the instance. Every subsequent push to `release` that changes
> the cloud-init script (e.g. a new image tag) will therefore recreate the VM on the next apply.
> That is acceptable here (stateless backend, fresh boot pulls the new image), but be aware deploys
> are not in-place — the old instance is terminated and a new one boots. The **reserved public IP**
> (3.3) keeps the address stable across this replacement.

> **Known limitation — no in-place update on redeploy (TODO):** as described in Phase 5's TODO, the
> cloud-init/systemd unit pulls a specific image `<tag>`. Recreating the instance on `user_data`
> change re-pulls the then-current `${GITHUB_SHA}`, so a fresh apply does pick up the new image.
> However, there is **no mechanism to roll the running container to a new image without recreating
> the instance** (e.g. no `curl`-triggered `docker pull && restart`, and `user_data` changes always
> replace the instance). For now this is accepted: each deploy is a full instance replacement. A
> lighter-weight update path can be added later if needed.

---

## Phase 5 · SSH recovery path

**Goal:** a safe way to debug a failed cloud-init without abandoning the no-static-credentials
model.

- The VM is provisioned with **your SSH public key** (cloud-init `ssh_authorized_keys`). The
  public key is supplied to Terraform — e.g. a workspace variable `ssh_public_key` (or read from a
  GitHub environment secret / a local file passed in at authoring time) and injected into the
  instance `user_data`. It is the *public* key only; no private key ever lives on the VM or in
  Terraform state beyond the public half.
- A security-list **ingress for TCP 22 is added only from `debug_ssh_source_cidr`** (your IP) and
  **only while debugging**; remove it afterward (or keep it permanently scoped to your IP if you
  accept that trade-off). This is the one deliberate exception to "no SSH", and it is gated to
  your address.
- Once connected: `sudo tail -f /var/log/cloud-init-output.log` to watch provisioning;
  `docker ps` / `journalctl` to diagnose the pull/run.

> **TODO(subtask): pin the deployed image to the commit hash, not `:latest`.** The cloud-init and
> the systemd unit should pull/run `.../soloquybackend:${GITHUB_SHA}` (the `image_tag` fed in 4.2),
> not `:latest` — pass it into `user_data` as a Terraform variable/template so each apply deploys
> the exact image built in that run, avoiding drift between `:latest` and what the VM actually runs.
> Note this means `user_data` changes on every deploy, which (per the 4.2 replacement note) recreates
> the instance — that is the intended update mechanism for now.
