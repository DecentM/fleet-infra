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

cat <<EOF >/tmp/join-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: "$token"
    apiServerEndpoint: "$master_ip:6443"
    caCertHashes:
      - "$cert_hash"
EOF

kubeadm join --config infrastructure/base/layer0/config/join-config.yaml --config /tmp/join-config.yaml

rm -f /tmp/join-config.yaml
