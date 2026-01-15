#!/bin/sh

set -eu

if ! command -v kubectl >/dev/null; then
    echo "kubectl is not installed. Please install it and try again."
    exit 1
fi

if [ ! -f bin/create-secret.sh ]; then
    echo "This script must be run from the root of the repository."
    exit 1
fi

secret_exists() {
    namespace="$1"
    secret_name="$2"

    kubectl get secret -n "$namespace" "$secret_name" >/dev/null 2>/dev/null
}

create_secret() {
    namespace="$1"
    secret_name="$2"
    secret_type="$3"
    input_keys="$4"
    output_path="$5"
    extra="${6:-''}"

    input_literals=""

    secret_exists=$(secret_exists "$namespace" "$secret_name" && echo 1 || echo 0)
    output_exists=$(test -f "$output_path" && echo 1 || echo 0)

    if [ "$secret_exists" = "1" ] && [ "$output_exists" = "1" ]; then
        echo "Skipping $namespace/$secret_name"
        return
    fi

    echo
    echo "$namespace ➜ $secret_name ($secret_type)"
    echo "===================="

    if [ "$secret_type" = "tls" ]; then
        printf "> TLS cert (PEM encoded content, press CTRL+D to submit):\n"
        input_literals=$(cat)

        printf "> TLS key (PEM encoded conten, press CTRL+D to submit):\n"
        extra=$(cat)
    else
        for key in $input_keys; do
            printf "> %s: " "$key"
            read -r value
            input_literals="$key=$value $input_literals"
        done
    fi

    printf "…"

    bin/create-secret.sh "$namespace" "$secret_name" "$secret_type" "$input_literals" "$output_path" "$extra"

    printf "\r✓\n"
}

create_secret \
    cloudflare-operator-system \
    cloudflare-secrets \
    generic \
    "CLOUDFLARE_API_TOKEN" \
    "infrastructure/base/layer1/cloudflare/sealed-cloudflare-secrets.yaml"

create_secret \
    tailscale-system \
    oauth \
    generic \
    "client-id client-secret" \
    "infrastructure/base/layer1/tailscale/sealed-tailscale-oauth.yaml"

create_secret \
    app-servarr \
    servarr-api-key \
    generic \
    "value" \
    "apps/base/servarr/secrets/sealed-api-key.yaml"

create_secret \
    app-joplin \
    joplin-secrets \
    generic \
    "baseurl" \
    "apps/base/joplin/sealed-joplin-secrets.yaml"

create_secret \
    longhorn-system \
    s3-secret \
    generic \
    "AWS_ACCESS_KEY_ID AWS_ENDPOINTS AWS_SECRET_ACCESS_KEY" \
    "infrastructure/production/layer1/sealed-s3-secret.yaml"

create_secret \
    app-photoprism \
    photoprism-admin-secrets \
    generic \
    "PHOTOPRISM_ADMIN_PASSWORD PHOTOPRISM_ADMIN_USER" \
    "apps/base/photoprism/sealed-admin-secrets.yaml"

create_secret \
    app-photoprism \
    photoprism-db-secrets \
    generic \
    "PHOTOPRISM_DATABASE_PASSWORD" \
    "apps/base/photoprism/sealed-db-secrets.yaml"

create_secret \
    app-invidious \
    invidious-secrets \
    generic \
    "hmac_key db_user db_password po_token visitor_data" \
    "apps/base/invidious/sealed-invidious-secrets.yaml"

create_secret \
    cert-manager-system \
    ca-issuer \
    tls \
    "" \
    "infrastructure/base/layer1/cert-manager/sealed-ca-issuer.yaml"

create_secret \
    app-minecraft \
    secrets \
    generic \
    "SEED PROXY_SECRET RCON_PASSWORD" \
    "apps/base/minecraft/sealed-secrets.yaml"

create_secret \
    app-restic \
    restic-secrets \
    generic \
    "repository password aws-access-key-id aws-secret-access-key" \
    "apps/base/restic/sealed-secrets.yaml"

create_secret \
    monitoring-system \
    alertmanager-discord-webhook \
    generic \
    "webhook-url" \
    "infrastructure/base/layer0/monitoring/sealed-discord-webhook.yaml"

# Keycloak SSO secrets
create_secret \
    keycloak-system \
    keycloak-admin \
    generic \
    "username password" \
    "infrastructure/base/layer1/keycloak/sealed-admin-secret.yaml"

create_secret \
    keycloak-system \
    keycloak-client-secrets \
    generic \
    "OAUTH2_PROXY_CLIENT_SECRET GRAFANA_CLIENT_SECRET JELLYFIN_CLIENT_SECRET PAPERLESS_CLIENT_SECRET PHOTOPRISM_CLIENT_SECRET HOME_ASSISTANT_CLIENT_SECRET" \
    "infrastructure/base/layer1/keycloak/sealed-client-secrets.yaml"

create_secret \
    oauth2-proxy-system \
    oauth2-proxy-secrets \
    generic \
    "client-secret cookie-secret" \
    "infrastructure/base/layer1/oauth2-proxy/sealed-secrets.yaml"

create_secret \
    monitoring-system \
    grafana-oidc-secret \
    generic \
    "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET" \
    "infrastructure/base/layer0/monitoring/sealed-grafana-oidc.yaml"

create_secret \
    app-paperless-ngx \
    paperless-oidc-secret \
    generic \
    "PAPERLESS_SOCIALACCOUNT_OIDC_SECRET" \
    "apps/base/paperless-ngx/sealed-oidc-secret.yaml"

create_secret \
    app-photoprism \
    photoprism-oidc-secret \
    generic \
    "PHOTOPRISM_OIDC_SECRET" \
    "apps/base/photoprism/sealed-oidc-secret.yaml"
