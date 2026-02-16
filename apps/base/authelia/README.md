# Authelia Authentication Stack

This directory contains the Authelia identity and access management stack, including LLDAP for user management.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Authelia Stack                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐   │
│  │   LLDAP     │────▶│  Authelia   │────▶│   Redis     │   │
│  │  (Users)    │     │ (Auth/OIDC) │     │ (Sessions)  │   │
│  └──────┬──────┘     └──────┬──────┘     └─────────────┘   │
│         │                   │                               │
│         ▼                   ▼                               │
│  ┌─────────────┐     ┌─────────────┐                       │
│  │  lldap-db   │     │ authelia-db │                       │
│  │ (PostgreSQL)│     │ (PostgreSQL)│                       │
│  └─────────────┘     └─────────────┘                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose | Port(s) |
|-----------|---------|---------|
| Authelia | Identity provider, OIDC, 2FA | 9091 (HTTP), 9959 (metrics) |
| LLDAP | Lightweight LDAP for user management | 3890 (LDAP), 17170 (Web UI) |
| authelia-db | PostgreSQL for Authelia state | 5432 |
| lldap-db | PostgreSQL for LLDAP data | 5432 |
| authelia-redis | Session storage | 6379 |

## Access URLs

| Service | Internal URL | External URL |
|---------|--------------|--------------|
| Authelia | https://auth.cluster.arpa | https://auth.decentm.com |
| LLDAP Web UI | https://lldap.cluster.arpa | N/A (internal only) |

## LLDAP User Management

### Accessing the LLDAP Web UI

The LLDAP web interface is available at `https://lldap.cluster.arpa` from within the cluster network.

Alternatively, use port-forwarding:

```bash
kubectl port-forward -n app-authelia svc/lldap 17170:17170
# Then access http://localhost:17170
```

### Default Admin Credentials

- **Username**: `admin`
- **Password**: Found in the `lldap-secrets` secret under `lldap-admin-password`

To retrieve the admin password:

```bash
kubectl get secret -n app-authelia lldap-secrets -o jsonpath='{.data.lldap-admin-password}' | base64 -d
```

### Creating Users

1. Log into the LLDAP web UI
2. Navigate to "Users" → "Create user"
3. Fill in:
   - **User ID**: Username (e.g., `john`)
   - **Email**: User's email address (required for password resets)
   - **Display Name**: Full name
   - **Password**: Initial password
4. Optionally add the user to groups

### Creating Groups

1. Navigate to "Groups" → "Create group"
2. Enter a group name (e.g., `admins`, `users`)
3. Add members to the group

### LDAP Structure

- **Base DN**: `dc=auth,dc=decentm,dc=com`
- **Users**: `ou=people,dc=auth,dc=decentm,dc=com`
- **Groups**: `ou=groups,dc=auth,dc=decentm,dc=com`
- **Admin User**: `uid=admin,ou=people,dc=auth,dc=decentm,dc=com`

## SMTP Notifications

Authelia uses SMTP for sending notifications (password resets, 2FA setup, etc.).

**Important**: Authelia does NOT support SMS notifications. Only email (SMTP) or filesystem notifications are available.

### SMTP Configuration

SMTP settings are configured via secrets in `authelia-secrets`:

| Secret Key | Description | Example |
|------------|-------------|---------|
| `smtp-address` | SMTP server address | `submission://smtp.gmail.com:587` |
| `smtp-username` | SMTP authentication username | `user@gmail.com` |
| `smtp-password` | SMTP authentication password | `app-specific-password` |
| `smtp-sender` | From address for emails | `Authelia <auth@example.com>` |

### SMTP Address Formats

- **Submission (recommended)**: `submission://smtp.example.com:587`
- **SMTPS (implicit TLS)**: `smtps://smtp.example.com:465`
- **Plain SMTP**: `smtp://smtp.example.com:25`

## Secrets

### Required Secrets

#### authelia-secrets

| Key | Description | Generation |
|-----|-------------|------------|
| `jwt-secret` | JWT signing secret | Auto-generated (64 char hex) |
| `session-secret` | Session encryption secret | Auto-generated (64 char hex) |
| `storage-encryption-key` | Database encryption key | Auto-generated (64 char hex) |
| `oidc-hmac-secret` | OIDC HMAC secret | Auto-generated (64 char hex) |
| `oidc-issuer-private-key.pem` | OIDC signing key | Auto-generated (RSA 4096) |
| `smtp-address` | SMTP server address | User-provided |
| `smtp-username` | SMTP username | User-provided |
| `smtp-password` | SMTP password | User-provided |
| `smtp-sender` | Email sender address | User-provided |

#### lldap-secrets

| Key | Description | Generation |
|-----|-------------|------------|
| `lldap-admin-password` | LLDAP admin password | Auto-generated (32 char alphanumeric) |
| `lldap-jwt-secret` | LLDAP JWT secret | Auto-generated (64 char hex) |

### Generating Secrets

Run the secret generation script:

```bash
bin/create-all-secrets.sh
```

This will:
1. Generate LLDAP secrets (auto-generated)
2. Generate Authelia secrets (auto-generated + SMTP prompts)
3. Create SealedSecrets for both

## User Creation Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    User Creation Flow                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Admin accesses LLDAP Web UI                             │
│     └── https://lldap.cluster.arpa                          │
│                                                             │
│  2. Admin creates user with email                           │
│     └── User ID, Email, Display Name, Initial Password      │
│                                                             │
│  3. User logs into Authelia                                 │
│     └── https://auth.decentm.com                            │
│                                                             │
│  4. User can self-service password reset via email          │
│     └── Receives reset link via SMTP                        │
│                                                             │
│  5. User configures 2FA (TOTP/WebAuthn)                     │
│     └── Optional but recommended                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Check LLDAP logs

```bash
kubectl logs -n app-authelia -l app=lldap
```

### Check Authelia logs

```bash
kubectl logs -n app-authelia -l app=authelia
```

### Test LDAP connectivity

```bash
kubectl exec -it -n app-authelia deploy/authelia -- \
  nc -zv lldap.app-authelia.svc.cluster.local 3890
```

### Verify LDAP bind

```bash
# Port-forward LLDAP
kubectl port-forward -n app-authelia svc/lldap 3890:3890

# In another terminal, test with ldapsearch (if installed)
ldapsearch -x -H ldap://localhost:3890 \
  -D "uid=admin,ou=people,dc=auth,dc=decentm,dc=com" \
  -w "$(kubectl get secret -n app-authelia lldap-secrets -o jsonpath='{.data.lldap-admin-password}' | base64 -d)" \
  -b "dc=auth,dc=decentm,dc=com" "(objectClass=*)"
```

### SMTP test

Check Authelia logs for SMTP connection issues:

```bash
kubectl logs -n app-authelia -l app=authelia | grep -i smtp
```

## Database Connections

### Authelia Database

```bash
kubectl exec -it -n app-authelia authelia-db-1 -- psql -U authelia -d authelia
```

### LLDAP Database

```bash
kubectl exec -it -n app-authelia lldap-db-1 -- psql -U lldap -d lldap
```

## Notes

- Users must be created in LLDAP, not in Authelia
- Authelia does NOT support database-backed user authentication - only LDAP or file
- Authelia does NOT support SMS notifications - only SMTP or filesystem
- The LLDAP web UI is internal-only (no Cloudflare tunnel binding)
- Password resets require valid email addresses and working SMTP configuration
