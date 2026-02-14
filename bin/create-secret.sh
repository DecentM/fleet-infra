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

#trap 'rm -f /tmp/sealed-secrets.pub.pem /tmp/secret.yaml /tmp/sealed-secret.yaml /tmp/cert.pem /tmp/key.pem' EXIT

kubectl cluster-info >/dev/null || (echo "Cannot connect to the cluster. Check your kubeconfig or the kube-system namespace. We need the cluster to be online to create secrets in it." && exit 1)

kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=flux-system >/tmp/sealed-secrets.pub.pem

if [ $# -eq 0 ]; then
    printf "> Namespace: "
    read -r namespace

    printf "> Secret name: "
    read -r secret_name

    printf "> Secret type (e.g. generic, docker-registry, etc.): "
    read -r secret_type

    printf "> Enter newline-separated literals (key=value per line, Ctrl+D when done):\n"
    input_literals=$(cat)

    printf "> TLS key (if applicable): "
    read -r tls_key
else
    namespace="$1"
    secret_name="$2"
    secret_type="$3"
    input_literals="$4"
    # $5 is output path
    tls_key="$6"
fi

literals=""

if [ "$secret_type" = "docker-registry" ]; then
    for word in $input_literals; do
        literals="--$word $literals"
    done

    # shellcheck disable=SC2086 # literals is a string of arguments
    kubectl -n "$namespace" create secret "$secret_type" "$secret_name" $literals --dry-run=client -o yaml >/tmp/secret.yaml
elif [ "$secret_type" = "tls" ]; then
    if [ -z "$input_literals" ]; then
        echo "TLS secret requires a cert file. Please provide the PEM encoded certificate in \$4."
        exit 1
    fi

    if [ -z "$tls_key" ]; then
        echo "TLS secret requires a key file. Please provide the PEM encoded key in \$6."
        exit 1
    fi

    # Write them to file
    echo "$input_literals" >/tmp/cert.pem
    echo "$tls_key" >/tmp/key.pem

    # In this case, literals are the cert
    literals="--cert=/tmp/cert.pem $literals"
    literals="--key=/tmp/key.pem $literals"

    # shellcheck disable=SC2086 # literals is a string of arguments
    kubectl -n "$namespace" create secret "$secret_type" "$secret_name" $literals --dry-run=client -o yaml >/tmp/secret.yaml
else
    # For generic secrets, use stringData YAML generation to handle special characters
    # This avoids shell word-splitting and kubectl argument parsing issues
    cat >/tmp/secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $secret_name
  namespace: $namespace
type: Opaque
stringData:
EOF

    # Check if input_literals is a directory (temp dir with files) or string (legacy key=value format)
    if [ -d "$input_literals" ]; then
        # New approach: read from temp files in directory
        # Each file in the directory is a key, and its content is the value
        for filepath in "$input_literals"/*; do
            [ -f "$filepath" ] || continue
            key=$(basename "$filepath")
            # Use proper YAML multi-line string format to handle any value
            # Indent with 2 spaces for the key, then use literal block scalar for value
            printf "  %s: |-\n" "$key" >>/tmp/secret.yaml
            # Indent each line of the value with 4 spaces
            sed 's/^/    /' "$filepath" >>/tmp/secret.yaml
            # Ensure trailing newline (fixes YAML corruption when files don't end with newline)
            # tail -c 1 returns empty string (after $() strips trailing newline) if file ends with \n
            if [ -n "$(tail -c 1 "$filepath")" ]; then
                echo >>/tmp/secret.yaml
            fi
        done
    else
        # Legacy approach: parse key=value pairs from newline-delimited input
        # Each line should be in format: key=value (value can contain spaces, special chars, etc.)
        # WARNING: This approach does NOT support multiline values!
        echo "$input_literals" | while IFS= read -r line; do
            [ -z "$line" ] && continue
            key="${line%%=*}"
            value="${line#*=}"
            # Use proper YAML multi-line string format to handle any value
            # Indent with 2 spaces for the key, then use literal block scalar for value
            printf "  %s: |-\n" "$key" >>/tmp/secret.yaml
            # Indent each line of the value with 4 spaces
            echo "$value" | sed 's/^/    /' >>/tmp/secret.yaml
        done
    fi
fi
kubeseal --format=yaml --cert=/tmp/sealed-secrets.pub.pem </tmp/secret.yaml >/tmp/sealed-secret.yaml

if [ $# -eq 0 ]; then
    echo "Secret created in /tmp. Pwd is $(pwd)"
    printf "> Output path (relative to pwd): "
    read -r output_path
else
    output_path="$5"
fi

mv /tmp/sealed-secret.yaml "$output_path"
