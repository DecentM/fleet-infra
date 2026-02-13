# Migration to Cloudflare Tunnels (testing.borooka.ee)

**Date:** February 13, 2026  
**Change:** Migrate from internal `*.cluster.arpa` domains to public `*.testing.borooka.ee` via Cloudflare tunnels

## Overview

The Matrix stack has been reconfigured to expose services publicly via Cloudflare tunnels:

| Old Domain (Internal) | New Domain (Public) | Access Method |
|-----------------------|---------------------|---------------|
| matrix.cluster.arpa | matrix.testing.borooka.ee | Cloudflare Tunnel |
| element.cluster.arpa | element.testing.borooka.ee | Cloudflare Tunnel |
| meet.cluster.arpa | meet.testing.borooka.ee | Cloudflare Tunnel |

## What Changed

### 1. Domain Names
- **server_name**: `matrix.cluster.arpa` → `testing.borooka.ee`
- All Matrix user IDs will be `@username:testing.borooka.ee`
- This is a **breaking change** for federation (existing federations will see this as a new server)

### 2. Network Architecture
- **Before**: Tailscale → Traefik IngressRoute → Services
- **After**: Internet → Cloudflare Tunnel → Services (TLS at edge)
- **Internal access still available**: `*.cluster.arpa` IngressRoutes remain functional

### 3. TLS Certificates
- **Before**: cert-manager with `custom-ca-cluster-issuer`
- **After**: Cloudflare handles TLS at the edge; services communicate via HTTP to cloudflared

### 4. Signing Key
- Signing key filename changed from `matrix.cluster.arpa.signing.key` to `testing.borooka.ee.signing.key`
- **If you already deployed**, you must regenerate the signing key with the new domain

## Migration Scenarios

### Scenario A: Fresh Deployment (Recommended)

If you haven't deployed yet, simply follow the standard deployment guide:

1. Follow [QUICKSTART.md](QUICKSTART.md)
2. Generate signing key with `SERVER_NAME="testing.borooka.ee"`
3. Deploy normally

DNS records will be automatically created by the Cloudflare operator.

### Scenario B: Migrating Existing Deployment

⚠️ **Warning**: This is a destructive migration. You will lose:
- All existing user accounts (new server_name = new identity)
- All room memberships on federated servers
- All existing federation trust relationships

If you must migrate:

1. **Backup everything first**:
   ```bash
   # Backup database
   kubectl -n app-matrix exec -it matrix-db-1 -- pg_dump -U synapse synapse > synapse-backup.sql
   
   # Backup media store (if you have data)
   kubectl -n app-matrix exec deploy/synapse -- tar czf - /data/media_store > media-backup.tar.gz
   
   # Export user list
   kubectl -n app-matrix exec deploy/synapse -- sqlite3 /data/homeserver.db ".dump" > users-backup.sql
   ```

2. **Delete the existing deployment**:
   ```bash
   kubectl delete -k apps/base/matrix/
   ```

3. **Regenerate signing key with new domain**:
   ```bash
   SERVER_NAME="testing.borooka.ee"
   TMPDIR="$(mktemp -d)"
   
   docker run --rm \
     -e SYNAPSE_SERVER_NAME="${SERVER_NAME}" \
     -e SYNAPSE_REPORT_STATS=no \
     -v "${TMPDIR}:/data" \
     matrixdotorg/synapse:1.147.0 generate
   
   cat "${TMPDIR}/${SERVER_NAME}.signing.key"
   ```

4. **Update sealed secrets**:
   ```bash
   ./bin/create-all-secrets.sh
   ```
   When prompted for `signing.key`, paste the new key from step 3.

5. **Redeploy**:
   ```bash
   kubectl apply -k apps/base/matrix/
   ```

6. **Recreate users**:
   ```bash
   kubectl -n app-matrix exec -it deploy/synapse -- \
     register_new_matrix_user \
     -c /config/homeserver.yaml \
     -a -u admin -p 'password' \
     http://localhost:8008
   ```

## Cloudflare Tunnel Details

### How It Works

The `TunnelBinding` resource (`apps/base/matrix/networking/tunnel.yaml`) connects to the existing `cluster-tunnel-borooka` ClusterTunnel defined in `infrastructure/production/layer1/cluster-tunnel.yaml`.

```
Internet (users)
    ↓ HTTPS (TLS at edge)
Cloudflare CDN
    ↓ Cloudflare Tunnel
cloudflared pod (in cluster)
    ↓ HTTP (no TLS)
Kubernetes Services (synapse, element, jitsi-web)
```

### DNS Management

DNS records are **automatically created** by the Cloudflare operator when you apply the TunnelBinding:

- `matrix.testing.borooka.ee` → CNAME to tunnel
- `element.testing.borooka.ee` → CNAME to tunnel
- `meet.testing.borooka.ee` → CNAME to tunnel

### Firewall Changes

**No longer needed:**
- ✅ ~~Inbound TCP 443~~ (Cloudflare handles this)
- ✅ ~~TLS certificates~~ (Cloudflare provides edge certs)

**Still required:**
- ⚠️ UDP 10000 for JVB (WebRTC media bypass CDN)

## Important: Jitsi JVB and WebRTC

### Why JVB Still Needs Direct Access

Jitsi Video Bridge (JVB) handles WebRTC media streams, which:
- Use UDP protocol (not HTTP/HTTPS)
- Cannot be proxied through Cloudflare Tunnel (which is HTTP-only)
- Require direct peer-to-peer or client-to-JVB connectivity

### Current Architecture

```
Video calls:
Browser → meet.testing.borooka.ee (Cloudflare) → jitsi-web (signaling)
Browser ←→ [UDP 10000] ←→ Node IP (JVB hostNetwork) (media)
```

The Jitsi web interface is served through Cloudflare, but **actual video/audio streams bypass Cloudflare** and go directly to your cluster node's public IP via UDP port 10000.

### Requirements

1. **Firewall**: UDP 10000 must be open on your node's public IP
2. **JVB Configuration**: May need to set advertised IP if behind NAT:
   
   Add to `apps/base/matrix/components/jitsi/jvb.yaml` environment:
   ```yaml
   - name: DOCKER_HOST_ADDRESS
     value: "YOUR_PUBLIC_IP"
   ```

3. **DNS A Record** (optional but recommended):
   Create a DNS A record for JVB if you want a stable hostname:
   ```
   jvb.testing.borooka.ee → <node-public-ip>
   ```

### Testing WebRTC Connectivity

After deployment, test video calls:

1. Visit `https://meet.testing.borooka.ee`
2. Create a test room
3. Join from 2+ devices/browsers
4. If video doesn't connect, check:
   ```bash
   # Verify JVB is listening on UDP 10000
   sudo ss -ulnp | grep 10000
   
   # Check JVB logs
   kubectl -n app-matrix logs deploy/jitsi-jvb
   ```

### Alternative: TURN Server

If your network has restrictive NAT/firewall:
- Consider deploying a TURN server (coturn)
- Acts as a relay for WebRTC when direct P2P fails
- Not included in this base implementation

## Federation Implications

With `server_name: testing.borooka.ee`:

✅ **Now possible:**
- Public Matrix federation with other homeservers
- Users can join rooms on matrix.org, etc.
- Federation discovery via `.well-known/matrix/server` (if configured)

⚠️ **Considerations:**
- Your server is now discoverable on the public internet
- Consider abuse controls (rate limiting, registration policies)
- Monitor federation traffic for spam/malicious servers

## Testing the Migration

### 1. Verify DNS Propagation
```bash
dig matrix.testing.borooka.ee
dig element.testing.borooka.ee
dig meet.testing.borooka.ee
```

Should show CNAME records pointing to Cloudflare tunnel.

### 2. Test Public Access
```bash
curl https://matrix.testing.borooka.ee/_matrix/client/versions
curl https://element.testing.borooka.ee/
curl https://meet.testing.borooka.ee/
```

### 3. Verify Server Name
```bash
kubectl -n app-matrix exec deploy/synapse -- cat /config/homeserver.yaml | grep server_name
```

Should output: `server_name: "testing.borooka.ee"`

### 4. Check Signing Key
```bash
kubectl -n app-matrix exec deploy/synapse -- ls -la /data/
```

Should show `testing.borooka.ee.signing.key`

### 5. Test Federation
Visit https://federationtester.matrix.org/ and test `testing.borooka.ee`

## Rollback Plan

If you need to revert to internal-only access:

1. Remove the TunnelBinding:
   ```bash
   kubectl delete -f apps/base/matrix/networking/tunnel.yaml
   ```

2. DNS records will be automatically removed by Cloudflare operator

3. Update configs back to `cluster.arpa` (reverse all changes)

4. Regenerate signing key with old domain

5. Redeploy

## Support

For issues:
- Check TunnelBinding status: `kubectl -n app-matrix get tunnelbinding`
- Check cloudflared logs: `kubectl -n cloudflare-operator logs -l app=cloudflared`
- Review Cloudflare dashboard for tunnel status

---

**Related Documentation:**
- [README.md](README.md) - Full deployment guide
- [QUICKSTART.md](QUICKSTART.md) - Quick deployment checklist
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Architecture details
