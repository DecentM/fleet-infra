# Matrix Stack Quick Start

This is a condensed checklist for deploying the Matrix stack. See [README.md](README.md) for detailed explanations.

## Prerequisites Checklist

- [ ] Traefik ingress controller installed
- [ ] cert-manager with `custom-ca-cluster-issuer` ClusterIssuer
- [ ] Longhorn with `longhorn-local` StorageClass
- [ ] CloudNativePG operator installed
- [ ] Sealed Secrets controller in `flux-system` namespace
- [ ] `docker`, `kubectl`, and `kubeseal` CLI tools installed

## DNS Records

DNS records are **automatically created** by Cloudflare Tunnel for public access:

- `matrix.testing.borooka.ee` (auto-created)
- `element.testing.borooka.ee` (auto-created)
- `meet.testing.borooka.ee` (auto-created)

For internal `cluster.arpa` access (optional), point these to your Traefik ingress IP:

- [ ] `matrix.cluster.arpa`
- [ ] `element.cluster.arpa`
- [ ] `meet.cluster.arpa`

## Firewall Rules

- [ ] No inbound rules needed for HTTPS (Cloudflare Tunnel handles this)
- [ ] Allow TCP 443 to Traefik (only for internal cluster.arpa access)
- [ ] Allow UDP 10000 to the node (for Jitsi JVB)

## Deployment Steps

### 1. Generate Synapse Signing Key

```bash
SERVER_NAME="testing.borooka.ee"
TMPDIR="$(mktemp -d)"

docker run --rm \
  -e SYNAPSE_SERVER_NAME="${SERVER_NAME}" \
  -e SYNAPSE_REPORT_STATS=no \
  -v "${TMPDIR}:/data" \
  matrixdotorg/synapse:1.147.0 generate

# Save this output - you'll need it in the next step
cat "${TMPDIR}/${SERVER_NAME}.signing.key"
```

### 2. Create Sealed Secrets

```bash
cd /var/home/decentm/code/fleet-infra
./bin/create-all-secrets.sh
```

When prompted, provide:

| Secret | Key | Value |
|--------|-----|-------|
| synapse-secrets | registration-shared-secret | `openssl rand -hex 32` |
| synapse-secrets | macaroon-secret-key | `openssl rand -hex 32` |
| synapse-secrets | form-secret | `openssl rand -hex 32` |
| synapse-signing-key | signing.key | Paste output from step 1 |
| jitsi-secrets | jicofo-auth-password | `openssl rand -hex 16` |
| jitsi-secrets | jvb-auth-password | `openssl rand -hex 16` |

### 3. Verify Sealed Secrets

```bash
ls -la apps/base/matrix/sealed-*.yaml
```

Expected files:
- `sealed-synapse-secrets.yaml`
- `sealed-synapse-signing-key.yaml`
- `sealed-jitsi-secrets.yaml`

### 4. Deploy the Stack

**Option A: Using Kustomize (recommended)**

```bash
kubectl apply -k apps/base/matrix/
```

**Option B: Step-by-step deployment**

```bash
# 1. Namespace
kubectl apply -f apps/base/matrix/namespace.yaml

# 2. Secrets
kubectl apply -f apps/base/matrix/sealed-*.yaml

# 3. Database & Storage
kubectl apply -f apps/base/matrix/data/

# 4. Wait for database
kubectl -n app-matrix wait --for=condition=Ready cluster/matrix-db --timeout=300s

# 5. ConfigMaps
kubectl apply -f apps/base/matrix/config/

# 6. Components
kubectl apply -f apps/base/matrix/components/synapse.yaml
kubectl apply -f apps/base/matrix/components/element.yaml
kubectl apply -f apps/base/matrix/components/jitsi/

# 7. Networking
kubectl apply -f apps/base/matrix/networking/
```

### 5. Wait for Pods to be Ready

```bash
kubectl -n app-matrix get pods -w
```

Wait until all pods show `Running` with `1/1` or `2/2` ready.

### 6. Create First Admin User

```bash
kubectl -n app-matrix exec -it deploy/synapse -- \
  register_new_matrix_user \
  -c /config/homeserver.yaml \
  -a \
  -u admin \
  -p 'CHANGE_ME_STRONG_PASSWORD' \
  http://localhost:8008
```

### 7. Test Access

**Synapse API:**
```bash
curl -k https://matrix.testing.borooka.ee/_matrix/client/versions
curl -k https://matrix.testing.borooka.ee/health
```

**Element Web:**
- Visit `https://element.testing.borooka.ee`
- Log in with your admin credentials

**Jitsi:**
- Visit `https://meet.testing.borooka.ee`
- Create a test room

## Verification Checklist

- [ ] All pods in `app-matrix` namespace are Running
- [ ] PostgreSQL cluster is Ready: `kubectl -n app-matrix get cluster`
- [ ] Certificates are issued: `kubectl -n app-matrix get certificates`
- [ ] Synapse health endpoint responds: `curl -k https://matrix.testing.borooka.ee/health`
- [ ] Can log into Element Web
- [ ] Jitsi Meet web interface loads
- [ ] Video call works in Jitsi (test with 2 browser tabs)

## Troubleshooting Quick Checks

**Synapse won't start:**
```bash
kubectl -n app-matrix logs deploy/synapse
kubectl -n app-matrix get secrets
```

**Database connection issues:**
```bash
kubectl -n app-matrix get svc | grep matrix-db
kubectl -n app-matrix exec -it deploy/synapse -- ping matrix-db-rw
```

**Jitsi video not working:**
```bash
# Check JVB is using hostNetwork
kubectl -n app-matrix get pod -l app=jitsi-jvb -o yaml | grep hostNetwork

# Check UDP 10000 is accessible
sudo ss -ulnp | grep 10000
```

**Element can't connect:**
```bash
kubectl -n app-matrix get ingressroute
kubectl -n app-matrix describe certificate synapse-tls
```

## Next Steps

- [ ] Configure backup for PostgreSQL database
- [ ] Set up media store backups (synapse-media PVC)
- [ ] Back up signing key securely
- [ ] Review [README.md](README.md) security section
- [ ] Consider disabling `registration_shared_secret` after creating users
- [ ] Configure rate limits and upload quotas

---

For detailed documentation, see [README.md](README.md).
