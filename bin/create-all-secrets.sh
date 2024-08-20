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

create_secret() {
    namespace="$1"
    secret_name="$2"
    input_keys="$3"
    output_path="$4"

    input_literals=""

    exists=$(kubectl get secret -n "$namespace" "$secret_name" >/dev/null 2>/dev/null && echo 1 || echo 0)

    if [ "$exists" = "1" ]; then
        echo "Skipping $namespace/$secret_name"
        return
    fi

    echo
    echo "$namespace ➜ $secret_name"
    echo "===================="

    for key in $input_keys; do
        printf "> %s: " "$key"
        read -r value
        input_literals="$key=$value $input_literals"
    done

    printf "…"

    bin/create-secret.sh "$namespace" "$secret_name" "$input_literals" "$output_path"

    printf "\r✓\n"
}

create_secret \
    cloudflare-operator-system \
    cloudflare-secrets \
    "CLOUDFLARE_API_TOKEN" \
    "infrastructure/base/layer1/cloudflare/sealed-cloudflare-secrets.yaml"

create_secret \
    tailscale-system \
    oauth \
    "client-id client-secret" \
    "infrastructure/base/layer1/tailscale/sealed-tailscale-oauth.yaml"

create_secret \
    app-servarr \
    servarr-api-key \
    "value" \
    "apps/base/servarr/secrets/sealed-api-key.yaml"

create_secret \
    app-servarr \
    sonarr-postgres-credentials \
    "POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB" \
    "apps/base/servarr/secrets/sealed-sonarr-postgres-credentials.yaml"

create_secret \
    app-servarr \
    prowlarr-postgres-credentials \
    "POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB" \
    "apps/base/servarr/secrets/sealed-prowlarr-postgres-credentials.yaml"

create_secret \
    app-servarr \
    radarr-postgres-credentials \
    "POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB" \
    "apps/base/servarr/secrets/sealed-radarr-postgres-credentials.yaml"