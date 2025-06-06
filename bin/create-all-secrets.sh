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
    app-concourse \
    local-users \
    generic \
    "value main-team-members" \
    "apps/base/concourse/secrets/sealed-local-users.yaml"

create_secret \
    concourse-main \
    npm \
    generic \
    "automation-token" \
    "apps/base/concourse/secrets/sealed-npm.yaml"

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
    app-etu-website-strapi \
    strapi-secrets \
    generic \
    "ADMIN_JWT_SECRET JWT_SECRET API_TOKEN_SALT TRANSFER_TOKEN_SALT APP_KEYS" \
    "apps/base/etu-website-strapi/sealed-strapi-secrets.yaml"

create_secret \
    app-invidious \
    invidious-secrets \
    generic \
    "hmac_key db_user db_password po_token visitor_data" \
    "apps/base/invidious/sealed-invidious-secrets.yaml"

create_secret \
    app-samba \
    samba-secrets \
    generic \
    "SAMBA_USERNAME SAMBA_PASSWORD" \
    "apps/base/samba/sealed-samba-secrets.yaml"

create_secret \
    app-o11y \
    grafana-secrets \
    generic \
    "admin-user admin-password" \
    "apps/base/o11y/sealed-grafana-secrets.yaml"

create_secret \
    app-o11y \
    qbittorrent-exporter-secrets \
    generic \
    "QBITTORRENT_USERNAME QBITTORRENT_PASSWORD" \
    "apps/base/o11y/qbittorrent-exporter/sealed-qbittorrent-exporter-secrets.yaml"

create_secret \
    cert-manager-system \
    ca-issuer \
    tls \
    "" \
    "infrastructure/base/layer1/cert-manager/sealed-ca-issuer.yaml"

create_secret \
    app-nextcloud \
    nextcloud-secrets \
    generic \
    "username password" \
    "apps/base/nextcloud/sealed-nextcloud-secrets.yaml"

create_secret \
    app-authentik \
    authentik-secrets \
    generic \
    "db-password secret-key" \
    "apps/base/authentik/sealed-authentik-secrets.yaml"

create_secret \
    app-minecraft \
    secrets \
    generic \
    "SEED PROXY_SECRET RCON_PASSWORD" \
    "apps/base/minecraft/sealed-secrets.yaml"

create_secret \
    app-etu-event-planner \
    secrets \
    generic \
    "SECURE_SESSION_KEY DISCORD_CONTROL_GUILD_ID DISCORD_CLIENT_ID DISCORD_CLIENT_SECRET DISCORD_USER_ID_OWNERS DISCORD_ROLE_ID_ADMIN DISCORD_ROLE_ID_EDITOR DISCORD_ROLE_ID_PUBLISHER DISCORD_TOKEN" \
    "apps/base/etu-event-planner/sealed-secrets.yaml"
