#!/bin/sh

set -eu

if ! command -v kubeseal >/dev/null; then
    echo "kubeseal is not installed. Please install it to continue."
    exit 1
fi

if ! command -v kubectl >/dev/null; then
    echo "kubectl is not installed. Please install it to continue."
    exit 1
fi

trap 'rm -f /tmp/sealed-secrets.pub.pem /tmp/secret.yaml /tmp/sealed-secret.yaml' EXIT

kubectl cluster-info >/dev/null || (echo "Cannot connect to the cluster. Check your kubeconfig or the kube-system namespace. We need the cluster to be online to create secrets in it." && exit 1)

kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=flux-system >/tmp/sealed-secrets.pub.pem

if [ $# -eq 0 ]; then
    printf "> Namespace: "
    read -r namespace

    printf "> Secret name: "
    read -r secret_name

    printf "> Secret type (e.g. generic, docker-registry, etc.): "
    read -r secret_type

    printf "> Enter space separated literals (like a=b c=d): "
    read -r input_literals
else
    namespace="$1"
    secret_name="$2"
    secret_type="$3"
    input_literals="$4"
fi

literals=""

if [ "$secret_type" = "docker-registry" ]; then
    for word in $input_literals; do
        literals="--$word $literals"
    done
else
    for word in $input_literals; do
        literals="--from-literal=$word $literals"
    done
fi

# shellcheck disable=SC2086 # literals is a string of arguments
kubectl -n "$namespace" create secret "$secret_type" "$secret_name" $literals --dry-run=client -o yaml >/tmp/secret.yaml
kubeseal --format=yaml --cert=/tmp/sealed-secrets.pub.pem </tmp/secret.yaml >/tmp/sealed-secret.yaml

rm -f /tmp/sealed-secrets.pub.pem /tmp/secret.yaml

if [ $# -eq 0 ]; then
    echo "Secret created in /tmp. Pwd is $(pwd)"
    printf "> Output path (relative): "
    read -r output_path
else
    output_path="$5"
fi

mv /tmp/sealed-secret.yaml "$output_path"
