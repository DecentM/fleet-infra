#!/bin/sh

set -eu

if ! command -v kubectl >/dev/null; then
    echo "kubectl is not installed. Please install it to continue."
    exit 1
fi

kubectl proxy &

sleep 0.1

printf "> Name: "
read -r namespace

kubectl get ns "$namespace" -o json | jq ".spec = {\"finalizers\": []}" >/tmp/kubecmd.json
curl -k -H "Content-Type: application/json" -X PUT --data-binary @/tmp/kubecmd.json "127.0.0.1:8001/api/v1/namespaces/$namespace/finalize"

rm -f /tmp/kubecmd.json

jobs -p | xargs -I{} kill -- -{}
