#!/bin/sh

set -eu

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

    echo "$namespace ➜ $secret_name"
    echo "===================="

    for key in $input_keys; do
        printf "> %s: " "$key"
        read -r value
        input_literals="$key=$value $input_literals"
    done

    printf "…"

    bin/create-secret.sh "$namespace" "$secret_name" "$input_literals" "$output_path"

    printf "\r✓\n\n"
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
    "apps/base/servarr/sealed-api-key.yaml"
