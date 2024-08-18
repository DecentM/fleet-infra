#!/bin/sh

kubectl proxy &

sleep 0.1

printf "> Namespace: "
read -r namespace

printf "> Object type: "
read -r object_type

printf "> Object name: "
read -r object_name

kubectl get "$object_type" "$object_name" -o json | jq ".spec = {\"namespace\": \"$namespace\", \"finalizers\": []}" >/tmp/kubecmd.json
curl -k -H "Content-Type: application/json" -X PUT --data-binary @/tmp/kubecmd.json "127.0.0.1:8001/api/v1/$object_type/$object_name/finalize"

rm -f /tmp/kubecmd.json

killall kubectl
