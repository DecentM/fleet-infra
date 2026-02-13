# Matrix Stack (Synapse + Element + Jitsi) on Kubernetes

This directory deploys a self-hosted Matrix chat stack:
- Synapse (Matrix homeserver) backed by PostgreSQL (CloudNativePG)
- Element Web (Matrix client)
- Jitsi Meet (Prosody + Jicofo + JVB + Web) for video conferencing

Namespace: `app-matrix`

---

## 1) Overview

You are deploying:
- **Synapse** at `https://matrix.testing.borooka.ee` (client + federation via Cloudflare Tunnel)
- **Element Web** at `https://element.testing.borooka.ee` (pre-configured to use the Synapse URL)
- **Jitsi Meet** at `https://meet.testing.borooka.ee` (used by Element for conferencing via `preferredDomain`)

Kubernetes resources live under `apps/base/matrix/` and are assembled with Kustomize.

---

## 2) Architecture

### Component view

```mermaid
flowchart LR
  U[User Browser] -->|HTTPS 443| CF[Cloudflare Tunnel<br/>TLS termination at edge]

  CF -->|Host: matrix.testing.borooka.ee| SVC_SYN[synapse Service :8008]
  CF -->|Host: element.testing.borooka.ee| SVC_EL[element Service :80]
  CF -->|Host: meet.testing.borooka.ee| SVC_JW[jitsi-web Service :80]

  subgraph NS[Namespace: app-matrix]
    SYN[Synapse Deployment<br/>matrixdotorg/synapse:1.147.0]
    EL[Element Deployment<br/>vectorim/element-web:v1.12.10]

    subgraph JIT[Jitsi Meet]
      PROS[Prosody Deployment<br/>jitsi/prosody:stable-10741]
      JIC[Jicofo Deployment<br/>jitsi/jicofo:stable-10741]
      JVB[JVB Deployment (hostNetwork)<br/>jitsi/jvb:stable-10741]
      JW[Jitsi Web Deployment<br/>jitsi/web:stable-10741]
    end

    DB[(PostgreSQL via CloudNativePG<br/>Cluster: matrix-db)]
    PVC[(Longhorn PVC<br/>synapse-media)]
  end

  SVC_SYN --> SYN
  SVC_EL --> EL
  SVC_JW --> JW

  SYN -->|TCP 5432| DB
  SYN -->|RWX not required<br/>RWO| PVC

  JW --> PROS
  JIC --> PROS
  JVB --> PROS

  U <-->|WebRTC UDP 10000| JVB
```

### What talks to what (high level)

- **Synapse**
  - Serves Matrix Client API and Federation API on port `8008` (behind Traefik TLS termination).
  - Stores state/events in **PostgreSQL** (`matrix-db-rw.app-matrix.svc:5432`).
  - Stores media on a **Longhorn PVC** (`synapse-media`, mounted at `/data`).

- **Element Web**
  - Static web client served via Nginx in the container.
  - Reads config from ConfigMap `element-config` (mounted to `/app/config.json`).
  - Targets Synapse base URL `https://matrix.testing.borooka.ee`.

- **Jitsi Meet (4 components)**
  - **Prosody**: XMPP server (control plane for conferences).
  - **Jicofo**: conference focus/controller.
  - **JVB**: media bridge (SFU) handling WebRTC media traffic. Uses `hostNetwork: true` and `hostPort: 10000/UDP`.
  - **Web**: Jitsi Meet UI, exposed via Traefik at `https://meet.cluster.arpa`.

### Networking / ingress

- **Cloudflare Tunnel** via `TunnelBinding` resources:
  - `matrix.testing.borooka.ee` -> `synapse` Service `:8008`
  - `element.testing.borooka.ee` -> `element` Service `:80`
  - `meet.testing.borooka.ee` -> `jitsi-web` Service `:80`

- Cloudflare handles:
  - TLS termination at the edge
  - DNS record creation (automatic via tunnel)
  - DDoS protection and caching

- Internal Traefik `IngressRoute` resources remain for `cluster.arpa` access:
  - `matrix.cluster.arpa`, `element.cluster.arpa`, `meet.cluster.arpa`

- TLS for internal access via cert-manager `Certificate` objects:
  - `synapse-tls`, `element-tls`, `jitsi-tls`
  - Issuer: `custom-ca-cluster-issuer` (cluster-specific)

### Storage layout

- **PostgreSQL**: CloudNativePG `Cluster/matrix-db`
  - StorageClass: `longhorn-local`
  - Size: `5Gi`

- **Synapse media**: PVC `synapse-media`
  - StorageClass: `longhorn-local`
  - Size: `20Gi`
  - Mounted at `/data` in Synapse

- **Element**: ephemeral (`emptyDir`) for `/var/cache/nginx` and `/var/run`
- **Jitsi**: currently ephemeral (no PVs); Prosody data uses `emptyDir`

---

## 3) Prerequisites

### Required cluster components

This base assumes these are already installed and working:

- **Traefik** (with CRDs for `IngressRoute`)
- **cert-manager**
  - A **ClusterIssuer** named `custom-ca-cluster-issuer` (adjust manifests if you use Let's Encrypt)
- **Longhorn**
  - A StorageClass named `longhorn-local`
- **CloudNativePG** operator (CNPG)
- **Sealed Secrets** controller (Bitnami)
  - In this repo it is deployed via Flux HelmRelease: `sealed-secrets-controller` in namespace `flux-system`

### DNS requirements

DNS records are **automatically created** by Cloudflare Tunnel for the public endpoints:

- `matrix.testing.borooka.ee`
- `element.testing.borooka.ee`
- `meet.testing.borooka.ee`

For internal `cluster.arpa` access (optional), create DNS records pointing to Traefik:

- `matrix.cluster.arpa`  -> Traefik external IP / LB / ingress VIP
- `element.cluster.arpa` -> Traefik external IP / LB / ingress VIP
- `meet.cluster.arpa`    -> Traefik external IP / LB / ingress VIP

Notes:
- Public access uses Cloudflare Tunnel (no inbound firewall rules needed for HTTPS)
- The `server_name` is `testing.borooka.ee` for Matrix federation purposes

### Firewall requirements

Minimum:
- No inbound firewall rules required for HTTPS (Cloudflare Tunnel handles this)
- TCP `443` to Traefik (only needed for internal `cluster.arpa` access)

For Jitsi media (required for reliable conferencing):
- UDP `10000` to the **node** running `jitsi-jvb` (because JVB uses `hostNetwork` + `hostPort`)

Federation (depending on your approach):
- If you intend to federate publicly, ensure your Synapse is reachable according to Matrix federation rules.
  - Many deployments use **HTTPS/443** with `/.well-known/matrix/server` and/or SRV records.
  - Alternatively, expose `8448/TCP` (not configured in this base) and serve federation there.

---

## 4) Pre-Deployment Steps

This base includes TODOs for secrets and key material. Do these steps *before* deploying so Synapse/Jitsi come up cleanly.

### 4.1 Generate the Synapse signing key

The signing key is your homeserver's identity. If you lose it and regenerate, other servers will treat you as a different server.

The base expects:
- `server_name: testing.borooka.ee`
- signing key path: `/data/testing.borooka.ee.signing.key`

Recommended (using the Synapse container to generate the key):

```bash
SERVER_NAME="testing.borooka.ee"
TMPDIR="$(mktemp -d)"

docker run --rm \
  -e SYNAPSE_SERVER_NAME="${SERVER_NAME}" \
  -e SYNAPSE_REPORT_STATS=no \
  -v "${TMPDIR}:/data" \
  matrixdotorg/synapse:1.147.0 generate

ls -la "${TMPDIR}"
cat "${TMPDIR}/${SERVER_NAME}.signing.key"
```

You will use the contents of `${SERVER_NAME}.signing.key` to create a Secret/SealedSecret.

### 4.2 Generate the registration shared secret

This secret is used for shared-secret registration (and tooling like `register_new_matrix_user`).

```bash
openssl rand -hex 32
```

Store it as `registration-shared-secret`.

### 4.3 Generate Jitsi passwords

Even if you start with guest access, you should generate passwords so you can enable auth cleanly later.

Suggested values:

```bash
openssl rand -hex 16  # repeat per password
```

Store (at minimum):
- `jicofo-auth-password`
- `jvb-auth-password`

Optional (only if you later add recording components like Jibri):
- `jibri-recorder-password`
- `jibri-xmpp-password`

### 4.4 Create SealedSecrets using the cluster script

This cluster uses a centralized script (`bin/create-all-secrets.sh`) to manage all SealedSecrets.

Matrix stack secrets have been added to this script. To generate them:

1. **Generate the Synapse signing key first** (you'll need this for the script):

```bash
SERVER_NAME="testing.borooka.ee"
TMPDIR="$(mktemp -d)"

docker run --rm \
  -e SYNAPSE_SERVER_NAME="${SERVER_NAME}" \
  -e SYNAPSE_REPORT_STATS=no \
  -v "${TMPDIR}:/data" \
  matrixdotorg/synapse:1.147.0 generate

# Save the signing key content - you'll paste this when prompted
cat "${TMPDIR}/${SERVER_NAME}.signing.key"
```

2. **Run the secrets creation script**:

```bash
cd /var/home/decentm/code/fleet-infra
./bin/create-all-secrets.sh
```

The script will:
- Check if each Matrix secret already exists
- Prompt you for values if they don't exist
- Automatically seal them with `kubeseal`
- Save them to the correct locations

3. **When prompted, provide these values**:

**For `synapse-secrets`**:
- `registration-shared-secret`: Run `openssl rand -hex 32`
- `macaroon-secret-key`: Run `openssl rand -hex 32`
- `form-secret`: Run `openssl rand -hex 32`

**For `synapse-signing-key`**:
- `signing.key`: Paste the full content from step 1 (multi-line is OK, press Enter after pasting)

**For `jitsi-secrets`**:
- `jicofo-auth-password`: Run `openssl rand -hex 16`
- `jvb-auth-password`: Run `openssl rand -hex 16`

4. **Verify the sealed secrets were created**:

```bash
ls -la apps/base/matrix/sealed-*.yaml
```

You should see:
- `sealed-synapse-secrets.yaml`
- `sealed-synapse-signing-key.yaml`
- `sealed-jitsi-secrets.yaml`

5. **Update manifests to reference the secrets**

The deployment manifests have TODO comments where secrets need to be wired in. You need to add volume mounts and environment variables:

**In `apps/base/matrix/components/synapse.yaml`**:
- Add volume mount for `synapse-signing-key` at `/data/testing.borooka.ee.signing.key` (subPath: `signing.key`)
- Add environment variables from `synapse-secrets`:
  - `SYNAPSE_REGISTRATION_SHARED_SECRET` from key `registration-shared-secret`
  - `SYNAPSE_MACAROON_SECRET_KEY` from key `macaroon-secret-key`
  - `SYNAPSE_FORM_SECRET` from key `form-secret`

**In `apps/base/matrix/components/jitsi/*.yaml`**:
- Wire `jitsi-secrets` into the environment variables marked with TODO

After updating the manifests, commit all changes including the sealed secrets.

---

## 5) Deployment (order matters)

You can deploy with Kustomize, but some parts must exist first.

### Recommended order

1) Namespace
```bash
kubectl apply -f apps/base/matrix/namespace.yaml
```

2) Database + PVC
```bash
kubectl apply -f apps/base/matrix/data/cnpg-cluster.yaml
kubectl apply -f apps/base/matrix/data/pvc-media.yaml
```

Wait for PostgreSQL to be ready:
```bash
kubectl -n app-matrix get pods
kubectl -n app-matrix get cluster matrix-db
```

3) Secrets (SealedSecrets)
```bash
kubectl apply -f apps/base/matrix/sealed-synapse-signing-key.yaml
kubectl apply -f apps/base/matrix/sealed-synapse-secrets.yaml
kubectl apply -f apps/base/matrix/sealed-jitsi-secrets.yaml
```

Confirm Secrets exist after the controller decrypts them:
```bash
kubectl -n app-matrix get secrets | egrep 'synapse-signing-key|synapse-secrets|jitsi-secrets'
```

4) ConfigMaps
```bash
kubectl apply -f apps/base/matrix/config/synapse-config.yaml
kubectl apply -f apps/base/matrix/config/element-config.yaml
kubectl apply -f apps/base/matrix/config/jitsi-config.yaml
```

5) Workloads
```bash
kubectl apply -f apps/base/matrix/components/synapse.yaml
kubectl apply -f apps/base/matrix/components/element.yaml

# Jitsi order matters: Prosody first
kubectl apply -f apps/base/matrix/components/jitsi/prosody.yaml
kubectl apply -f apps/base/matrix/components/jitsi/jicofo.yaml
kubectl apply -f apps/base/matrix/components/jitsi/jvb.yaml
kubectl apply -f apps/base/matrix/components/jitsi/web.yaml
```

6) Networking/Ingress + Certificates
```bash
kubectl apply -f apps/base/matrix/networking/synapse-ingress.yaml
kubectl apply -f apps/base/matrix/networking/element-ingress.yaml
kubectl apply -f apps/base/matrix/networking/jitsi-ingress.yaml
```

### Alternative: single Kustomize apply

Once your SealedSecrets are present *and referenced by the manifests/patches*, you can do:

```bash
kubectl apply -k apps/base/matrix/
```

---

## 6) Post-Deployment Configuration

### 6.1 Create the first admin user

Option A (common): run `register_new_matrix_user` inside the Synapse pod.

```bash
kubectl -n app-matrix exec -it deploy/synapse -- \
  register_new_matrix_user \
  -c /config/homeserver.yaml \
  -a \
  -u admin \
  -p 'CHANGEME_STRONG_PASSWORD' \
  http://localhost:8008
```

If this fails with shared secret errors:
- Confirm `registration_shared_secret` is set (via `SYNAPSE_REGISTRATION_SHARED_SECRET`)
- Confirm the env var substitution is working in `homeserver.yaml`

Option B: use the Synapse Admin API shared-secret registration flow.
- This is more complex (nonce + HMAC) but works without shell access.
- If you need it, prefer the `register_new_matrix_user` approach unless you are automating provisioning.

### 6.2 Verify all components are running

```bash
kubectl -n app-matrix get pods
kubectl -n app-matrix get svc
kubectl -n app-matrix get ingressroute
kubectl -n app-matrix get certificates
```

Check logs as needed:
```bash
kubectl -n app-matrix logs deploy/synapse
kubectl -n app-matrix logs deploy/element
kubectl -n app-matrix logs deploy/jitsi-prosody
kubectl -n app-matrix logs deploy/jitsi-jicofo
kubectl -n app-matrix logs deploy/jitsi-jvb
kubectl -n app-matrix logs deploy/jitsi-web
```

### 6.3 Test Synapse client endpoints

```bash
curl -fsS https://matrix.testing.borooka.ee/_matrix/client/versions | jq .
curl -fsS https://matrix.testing.borooka.ee/health
```

### 6.4 Test Matrix federation

With `testing.borooka.ee` as your server_name, federation should work with proper DNS:
- Cloudflare Tunnel creates DNS records automatically
- Federation requests will reach your Synapse via the tunnel

Federation test:
- Use the Matrix Federation Tester: https://federationtester.matrix.org/

Local sanity check (endpoint exists):
```bash
curl -fsS https://matrix.testing.borooka.ee/_matrix/federation/v1/version | jq .
```

### 6.5 Test Element login

1) Visit `https://element.testing.borooka.ee`
2) Confirm the homeserver shown is `testing.borooka.ee` (it is set in `apps/base/matrix/config/element-config.yaml`)
3) Log in with your admin user

### 6.6 Test Jitsi video calls

Direct:
1) Visit `https://meet.testing.borooka.ee`
2) Create a test room and join from two devices (or a second browser)

From Element:
- Start a call in a room and confirm it routes to `meet.testing.borooka.ee` (configured via `preferredDomain`).

If video connects but media is one-way or fails, jump to the WebRTC troubleshooting section (UDP 10000 / NAT / advertised IP).

---

## 7) Accessing Services

- Synapse (Matrix homeserver): `https://matrix.testing.borooka.ee`
  - Client API: `/_matrix/client/...`
  - Federation API: `/_matrix/federation/...`

- Element Web: `https://element.testing.borooka.ee`

- Jitsi Meet: `https://meet.testing.borooka.ee`

Internal service names (Kubernetes DNS, namespace `app-matrix`):
- Synapse: `synapse.app-matrix.svc:8008`
- Postgres (read/write): `matrix-db-rw.app-matrix.svc:5432`
- Jitsi:
  - Prosody: `prosody.app-matrix.svc:5222`
  - Jicofo: `jicofo.app-matrix.svc:8888`
  - JVB: `jvb.app-matrix.svc:8080`
  - Web: `jitsi-web.app-matrix.svc:80`

---

## 8) Troubleshooting

### Database connection problems (Synapse <-> Postgres)

Symptoms:
- Synapse pod CrashLoopBackOff
- Logs show auth failures, DNS failures, or connection refused

Checks:
```bash
kubectl -n app-matrix get svc | grep matrix-db
kubectl -n app-matrix get secrets | grep matrix-db
kubectl -n app-matrix logs deploy/synapse
```

Key details from this base:
- Host: `matrix-db-rw.app-matrix.svc`
- User/database: `synapse` / `synapse`
- Password secret ref in `apps/base/matrix/components/synapse.yaml`:
  - Secret: `matrix-db-app`
  - Key: `password`

If the secret name differs in your CNPG version/config:
- Inspect secrets in `app-matrix` and update the deployment accordingly.

### Synapse signing key issues

Symptoms:
- Synapse fails on startup complaining about missing/unreadable signing key
- Federation breaks after a restore
- Other servers report signature/verification errors

Fixes:
- Confirm the key exists at: `/data/testing.borooka.ee.signing.key` inside the pod.
- Confirm the volume mount/subPath matches the Secret key name.
- Restore the *original* signing key from backup; do not regenerate unless you accept federation identity breakage.

### Jitsi WebRTC connectivity problems

Symptoms:
- "Connecting…" forever
- No audio/video, or one-way media
- Works on LAN but not over the internet

Most common causes:
- UDP `10000` blocked (firewall, security group, NAT)
- JVB advertising the wrong IP (node has multiple interfaces, NAT hairpin, etc.)
- Running JVB on a node without stable public reachability

Checks:
- Confirm `jitsi-jvb` is `hostNetwork: true` and `hostPort: 10000/UDP` (see `apps/base/matrix/components/jitsi/jvb.yaml`).
- Confirm your firewall allows inbound UDP `10000` to that node.
- Consider pinning JVB to a specific node (nodeSelector/affinity) that matches your firewall/NAT rules.
- If NAT is involved, you may need to set JVB advertised addresses (varies by Jitsi image/env; commonly `DOCKER_HOST_ADDRESS` or JVB advertise settings). Add these via ConfigMap/env as needed.

### Element can't connect to Synapse

Symptoms:
- Element shows "Can't connect to homeserver"
- CORS / network errors in browser console

Checks:
- Synapse reachable: `curl https://matrix.testing.borooka.ee/_matrix/client/versions`
- Element config points to Synapse:
  - `apps/base/matrix/config/element-config.yaml` -> `"base_url": "https://matrix.testing.borooka.ee"`

Common fixes:
- Ensure Cloudflare Tunnel is running and healthy
- Ensure certificates are issued and valid (`kubectl -n app-matrix get certificates`).
- Ensure Synapse is healthy (`/health` probe and `curl https://matrix.testing.borooka.ee/health`).

---

## 9) Maintenance

### Backups (do not skip)

You should back up:

1) PostgreSQL database (Synapse state)
- Preferred: CNPG-native backup tooling (recommended for production)
- Minimum: scheduled `pg_dump` stored off-cluster

2) Synapse media store
- Longhorn snapshots + off-cluster replication, or
- File-level backup of the PVC contents (`/data/media_store`)

3) Synapse signing key
- Back up the signing key Secret (or its source material) securely.
- Losing it breaks federation identity and can invalidate signatures.

Also consider backing up:
- Any SealedSecret source materials (you can re-seal from plaintext if you kept it securely)
- ConfigMaps and Kustomize overlays (Git already covers this)

### Upgrading components

General guidance:
- Upgrade one tier at a time and watch logs.
- Synapse upgrades can include database migrations; schedule a maintenance window.

Where versions are pinned:
- `apps/base/matrix/components/synapse.yaml`: `matrixdotorg/synapse:1.147.0`
- `apps/base/matrix/components/element.yaml`: `vectorim/element-web:v1.12.10`
- `apps/base/matrix/components/jitsi/*`: `stable-10741`
- `apps/base/matrix/data/cnpg-cluster.yaml`: Postgres `16.10`

After image updates:
```bash
kubectl -n app-matrix rollout status deploy/synapse
kubectl -n app-matrix logs deploy/synapse --tail=200
```

### Scaling considerations

- **Synapse**
  - This base runs 1 replica and uses a single RWO PVC.
  - Horizontal scaling typically requires additional components (e.g., Redis, worker processes, shared media storage) and is not covered here.

- **PostgreSQL**
  - CNPG `instances: 1` in this base.
  - For HA, increase instances and plan for resource/storage overhead.

- **Jitsi**
  - Scaling video capacity usually means adding more **JVB** replicas and ensuring load distribution.
  - With `hostNetwork`/`hostPort`, multiple JVB replicas require careful port/IP planning.

---

## 10) Resource Usage (expected)

Based on the current manifests (requests/limits):

- Synapse: `500m / 1Gi` requests, `2 CPU / 2Gi` limits
- Element: `10m / 32Mi` requests, `100m / 64Mi` limits
- Jitsi Prosody: `100m / 256Mi` requests, `500m / 512Mi` limits
- Jitsi Jicofo: `100m / 256Mi` requests, `500m / 512Mi` limits
- Jitsi JVB: `500m / 512Mi` requests, `2 CPU / 1Gi` limits
- Jitsi Web: `50m / 128Mi` requests, `200m / 256Mi` limits
- PostgreSQL (CNPG): resources not explicitly set here; expect at least ~`500m-1 CPU` and `1Gi+` RAM for comfortable operation under load.

Rule of thumb for a small/home deployment:
- Idle: a few hundred millicores, ~2–4Gi RAM total
- Active rooms / federation / media uploads: Synapse + Postgres + JVB can spike CPU/RAM significantly

---

## 11) Security Considerations

### Protect admin endpoints
- Synapse has powerful admin APIs under `/_synapse/admin`.
- Consider restricting access via:
  - Traefik middleware IP allowlist for admin paths
  - Separate admin ingress hostname only reachable on trusted networks
  - NetworkPolicies limiting cross-namespace access (if enforced in your cluster)

### Registration controls
- `enable_registration: false` in `apps/base/matrix/config/synapse-config.yaml`
- Use `registration_shared_secret` only for controlled provisioning.
- If you enable open registration later, add CAPTCHA/email verification and rate limits.

### Media upload limits
Configured in Synapse:
- `max_upload_size: 50M`
- `max_image_pixels: 32M`

Tune based on your storage and threat model.

### Network policies
If your cluster enforces NetworkPolicies, explicitly allow:
- Synapse -> Postgres (5432)
- Jitsi components -> Prosody (5222/5269/5347/5280 as needed)
- Ingress controller -> services (Synapse/Element/Jitsi web)
- JVB hostNetwork UDP 10000 inbound to the node

### TLS and trust
- Certificates here are issued by `custom-ca-cluster-issuer`.
- Ensure clients trust that CA (or switch to a public ACME issuer for external use).

---

<sub><em>This documentation was AI-generated under supervision.</em></sub>
