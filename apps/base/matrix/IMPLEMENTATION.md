# Matrix Stack Implementation Summary

**Date:** February 12, 2026  
**Stack Version:** Synapse 1.147.0, Element 1.12.10, Jitsi stable-10741  
**Target:** Single-node Kubernetes cluster with flux-infra GitOps pattern

## Components Deployed

### Core Services

| Component | Image | Purpose |
|-----------|-------|---------|
| **Synapse** | matrixdotorg/synapse:1.147.0 | Matrix homeserver (federation + client API) |
| **Element Web** | vectorim/element-web:v1.12.10 | Web-based Matrix client |
| **Jitsi Prosody** | jitsi/prosody:stable-10741 | XMPP server for Jitsi |
| **Jitsi Jicofo** | jitsi/jicofo:stable-10741 | Jitsi conference focus |
| **Jitsi JVB** | jitsi/jvb:stable-10741 | Jitsi video bridge (SFU) |
| **Jitsi Web** | jitsi/web:stable-10741 | Jitsi Meet web interface |
| **PostgreSQL** | ghcr.io/cloudnative-pg/postgresql:16.10 | Synapse database (via CNPG operator) |

### Infrastructure Integration

- **Namespace:** `app-matrix`
- **Ingress:** Cloudflare Tunnel (primary), Traefik IngressRoute (internal)
- **Storage:** Longhorn `longhorn-local` StorageClass
- **Database:** CloudNativePG operator
- **Secrets:** Bitnami SealedSecrets
- **TLS:** Cloudflare (edge termination for public), cert-manager with `custom-ca-cluster-issuer` (internal)

## Architecture Decisions

### 1. Synapse Configuration

**Decision:** Monolith mode (no workers)  
**Rationale:** Simplifies deployment for single-node cluster; workers require Redis and more complex orchestration. Monolith is sufficient for small-to-medium deployments (<1000 users).

**Decision:** PostgreSQL 16 via CloudNativePG  
**Rationale:** CNPG provides backup, HA capabilities, and follows cluster patterns. Synapse requires PostgreSQL (SQLite deprecated).

**Decision:** Separate PVCs for config/media  
**Rationale:** Different I/O patterns - config is small/high-IOPS, media is large/sequential. Allows independent scaling and backup strategies.

### 2. Jitsi Networking

**Decision:** JVB uses `hostNetwork: true` and `hostPort: 10000/UDP`  
**Rationale:** 
- JVB requires direct UDP connectivity for WebRTC media streams
- NAT traversal issues are common with NodePort/LoadBalancer for UDP
- Single-node cluster makes hostNetwork acceptable
- Performance: eliminates kube-proxy overhead for video traffic

**Trade-off:** Limits JVB to one replica per node (port conflict). For scaling, would need:
- Multiple nodes with different advertised IPs, or
- TURN server for NAT traversal (more complex)

### 3. Storage Strategy

| Data | Storage | Size | Backup Priority |
|------|---------|------|----------------|
| PostgreSQL | Longhorn RWO | 5Gi | **Critical** - CNPG backups |
| Synapse media | Longhorn RWO | 20Gi | High - media uploads |
| Signing key | Kubernetes Secret | <1Ki | **Critical** - federation identity |
| Jitsi state | emptyDir | - | None - ephemeral XMPP state |

**Decision:** No shared filesystem (RWX)  
**Rationale:** Monolith Synapse doesn't need it; simplifies storage requirements.

### 4. Secrets Management

**Decision:** Use `bin/create-all-secrets.sh` cluster pattern  
**Rationale:**
- Consistent with existing cluster practices
- Centralizes secret lifecycle management
- Automated sealing with kubeseal
- Audit trail via Git commits of sealed secrets

**Secrets created:**
- `synapse-secrets`: registration-shared-secret, macaroon-secret-key, form-secret
- `synapse-signing-key`: signing.key (federation identity)
- `jitsi-secrets`: jicofo-auth-password, jvb-auth-password

### 5. Security Configuration

**Container Security:**
- All containers run as non-root where possible
- Synapse: UID/GID 991 (official image default)
- Element: UID 101 (nginx user)
- Jitsi: Varied by component (official images)

**Network Security:**
- TLS termination at Traefik (ingress)
- Internal cluster traffic uses plaintext HTTP (trusted network)
- Synapse configured with `x_forwarded: true` for proxy headers

**Access Control:**
- `enable_registration: false` (closed registration)
- `registration_shared_secret` for controlled user creation
- Admin endpoints (`/_synapse/admin`) exposed but require auth token

### 6. Integration Design

**Element → Synapse:**
- Element `config.json` sets `default_server_config.m.homeserver.base_url`
- Direct HTTPS via Traefik IngressRoute

**Element → Jitsi:**
- Element `config.json` sets `jitsi.preferredDomain: "meet.testing.borooka.ee"`
- Client-side integration (Element embeds Jitsi widget)
- No server-side Synapse config needed for basic Jitsi usage

**Synapse ↔ PostgreSQL:**
- Database connection via CNPG-managed Service: `matrix-db-rw.app-matrix.svc:5432`
- Credentials from CNPG-generated Secret: `matrix-db-app`
- Connection pooling: `cp_min: 5, cp_max: 10`

**Jitsi Internal Mesh:**
- Prosody (XMPP hub) at `prosody.app-matrix.svc:5222`
- Jicofo and JVB connect to Prosody via cluster DNS
- Web component serves UI, connects browser to Prosody BOSH/WebSocket

## Resource Allocation

### CPU/Memory Requests and Limits

| Component | CPU Request | CPU Limit | RAM Request | RAM Limit |
|-----------|-------------|-----------|-------------|-----------|
| Synapse | 500m | 2 | 1Gi | 2Gi |
| PostgreSQL | (CNPG defaults) | - | (CNPG defaults) | - |
| Element | 10m | 100m | 32Mi | 64Mi |
| Prosody | 100m | 500m | 256Mi | 512Mi |
| Jicofo | 100m | 500m | 256Mi | 512Mi |
| JVB | 500m | 2 | 512Mi | 1Gi |
| Jitsi Web | 50m | 200m | 128Mi | 256Mi |

**Total (approx):**
- Idle: ~1.5 CPU, ~3Gi RAM
- Under load: Can spike to 6+ CPU (Synapse + JVB are CPU-intensive)

### Storage Allocation

- PostgreSQL: 5Gi (Longhorn)
- Synapse media: 20Gi (Longhorn)
- Total: 25Gi persistent storage

## DNS and Ingress Layout

```
User Browser
    | HTTPS (443)
    v
Cloudflare Edge (TLS termination)
    |
Cloudflare Tunnel
    |
+-------------------------------------+
| matrix.testing.borooka.ee           | -> synapse:8008
| element.testing.borooka.ee          | -> element:80
| meet.testing.borooka.ee             | -> jitsi-web:80
+-------------------------------------+
```

**Cloudflare Tunnel Benefits:**
- No inbound firewall rules needed
- Automatic DNS record creation
- TLS handled at edge (no cert-manager needed for public access)
- DDoS protection included

**Internal Access (optional):**
- Traefik IngressRoutes remain for `*.cluster.arpa` access
- Certificates issued by `custom-ca-cluster-issuer`

**Federation:**
- `server_name: testing.borooka.ee` (defines Matrix IDs like `@user:testing.borooka.ee`)
- Federation works via Cloudflare Tunnel (publicly resolvable domain)
- No `.well-known/matrix/server` needed if serving on port 443

## File Structure

```
apps/base/matrix/
├── README.md                       # Comprehensive documentation
├── QUICKSTART.md                   # Deployment checklist
├── IMPLEMENTATION.md               # This file (design decisions)
├── kustomization.yaml              # Kustomize resource aggregation
├── namespace.yaml                  # app-matrix namespace
├── sealed-synapse-secrets.yaml     # Generated by bin/create-all-secrets.sh
├── sealed-synapse-signing-key.yaml # Generated by bin/create-all-secrets.sh
├── sealed-jitsi-secrets.yaml       # Generated by bin/create-all-secrets.sh
├── config/
│   ├── synapse-config.yaml         # homeserver.yaml + logging config
│   ├── element-config.yaml         # config.json for Element
│   └── jitsi-config.yaml           # ConfigMaps for all Jitsi components
├── data/
│   ├── cnpg-cluster.yaml           # PostgreSQL cluster definition
│   └── pvc-media.yaml              # Synapse media store PVC
├── networking/
│   ├── synapse-ingress.yaml        # IngressRoute + Certificate (internal access)
│   ├── element-ingress.yaml        # IngressRoute + Certificate (internal access)
│   ├── jitsi-ingress.yaml          # IngressRoute + Certificate (internal access)
│   └── tunnel.yaml                 # Cloudflare TunnelBinding (public access)
└── components/
    ├── synapse.yaml                # Deployment + Service
    ├── element.yaml                # Deployment + Service
    └── jitsi/
        ├── prosody.yaml            # Deployment + Service (XMPP)
        ├── jicofo.yaml             # Deployment + Service (focus)
        ├── jvb.yaml                # Deployment + Service (bridge)
        └── web.yaml                # Deployment + Service (UI)
```

## Health Checks

| Component | Liveness Probe | Readiness Probe |
|-----------|----------------|-----------------|
| Synapse | HTTP GET `/health` :8008 | HTTP GET `/health` :8008 |
| Element | HTTP GET `/` :80 | HTTP GET `/` :80 |
| Prosody | TCP :5222 | TCP :5222 |
| Jicofo | HTTP GET `/about/health` :8888 | HTTP GET `/about/health` :8888 |
| JVB | HTTP GET `/about/health` :8080 | HTTP GET `/about/health` :8080 |
| Jitsi Web | HTTP GET `/` :80 | HTTP GET `/` :80 |

## Initialization Dependencies

Startup order enforced via initContainers:

1. **PostgreSQL** (CNPG Cluster) - must be Ready first
2. **Synapse** - waits for `matrix-db-rw:5432` (nc check in initContainer)
3. **Jitsi Prosody** - no dependencies
4. **Jitsi Jicofo** - waits for Prosody (`prosody:5222`)
5. **Jitsi JVB** - waits for Prosody (`prosody:5222`)
6. **Jitsi Web** - waits for Prosody (`prosody:5222`)
7. **Element** - no dependencies (static files)

## Known Limitations

1. **Single-node only:** JVB hostNetwork limits scaling
2. **No workers:** Synapse monolith may bottleneck at high federation load
3. **No TURN server:** 1:1 calls may fail behind restrictive NATs (group calls via Jitsi work)
4. **No media retention:** Media store will grow indefinitely without manual cleanup
5. **WebRTC via Cloudflare:** Jitsi JVB still requires direct UDP (port 10000) for media; tunnel only handles signaling

## Future Enhancements

- [ ] Add TURN server (coturn) for 1:1 call NAT traversal
- [ ] Implement Synapse workers for horizontal scaling
- [ ] Configure media retention policies
- [ ] Add Prometheus ServiceMonitor for metrics
- [ ] NetworkPolicies for defense-in-depth
- [ ] Automated backup CronJob for media store
- [ ] Well-known delegation for public domain federation
- [ ] Jibri integration for recording/streaming

## Testing Recommendations

### Unit Tests (per-component)
- Synapse: `/_matrix/client/versions`, `/health`
- Element: Load homepage, verify config
- Jitsi: Create room, join with 2+ participants

### Integration Tests
- Element → Synapse: Login flow
- Element → Jitsi: Start video call from room
- Synapse → PostgreSQL: Check connection in logs

### Federation Tests (if public)
- Use Matrix Federation Tester: https://federationtester.matrix.org/
- Verify `/_matrix/federation/v1/version` responds

## Maintenance Tasks

| Task | Frequency | Command/Location |
|------|-----------|------------------|
| Check pod health | Daily | `kubectl -n app-matrix get pods` |
| Review Synapse logs | Weekly | `kubectl -n app-matrix logs deploy/synapse` |
| Database backup | Daily | CNPG backup schedule |
| Media backup | Weekly | PVC snapshot or rsync |
| Update images | Monthly | Edit manifest tags, apply |
| Rotate secrets | Yearly | Re-run `bin/create-all-secrets.sh` |

## References

- [Matrix Specification](https://spec.matrix.org/)
- [Synapse Documentation](https://matrix-org.github.io/synapse/)
- [Element Documentation](https://element.io/get-started)
- [Jitsi Docker Setup](https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-docker)
- [CloudNativePG Docs](https://cloudnative-pg.io/)

---

**Implemented by:** AI Assistant (Claude Sonnet 4.5)  
**Reviewed by:** [Pending human review]
