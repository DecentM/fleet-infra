#!/bin/sh

set -eu

if ! command -v kubeadm >/dev/null; then
    echo "kubeadm is not installed. Please install it to continue. (is this a node?)"
    exit 1
fi

printf "> Master IP: "
read -r master_ip

printf "> Token: "
read -r token

printf "> Cert Hash: "
read -r cert_hash

kubeadm join "$master_ip:6443" --token "$token" --discovery-token-ca-cert-hash "$cert_hash" --config infrastructure/base/layer0/config/join-config.yaml
