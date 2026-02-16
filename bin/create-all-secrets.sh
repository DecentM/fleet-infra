#!/bin/bash
set -euo pipefail

# Global flags
DEBUG=false
DRY_RUN=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if secret exists in cluster
secret_exists_in_cluster() {
    local namespace=$1
    local name=$2
    kubectl -n "$namespace" get secret "$name" &>/dev/null
}

# Check if all expected keys exist in a cluster secret
# Returns 0 (true) if all keys exist, 1 (false) if any are missing
all_keys_exist_in_secret() {
    local namespace=$1
    local name=$2
    local expected_keys_json=$3  # JSON array of key names

    # Get actual keys from the cluster secret
    local actual_keys
    if ! actual_keys=$(kubectl -n "$namespace" get secret "$name" -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys[]' 2>/dev/null); then
        warn "Failed to get keys from secret $namespace/$name"
        return 1
    fi

    # Check each expected key
    local expected_keys
    if ! expected_keys=$(echo "$expected_keys_json" | jq -r '.[]' 2>/dev/null); then
        warn "Failed to parse expected keys JSON"
        return 1
    fi

    # Handle empty expected keys (shouldn't happen but be graceful)
    if [[ -z "$expected_keys" ]]; then
        return 0
    fi

    local missing_key=false
    while IFS= read -r expected_key; do
        if ! echo "$actual_keys" | grep -q "^${expected_key}$"; then
            warn "Secret $namespace/$name is missing key: $expected_key (will recreate)"
            missing_key=true
        fi
    done <<< "$expected_keys"

    if [[ "$missing_key" == "true" ]]; then
        return 1
    fi

    return 0
}

# Determine if a secret should be skipped
# Returns 0 (true) to skip, 1 (false) to process
should_skip_secret() {
    local namespace=$1
    local name=$2
    local file=$3
    local expected_keys_json=$4  # JSON array of key names

    # Check if secret exists in cluster
    if ! secret_exists_in_cluster "$namespace" "$name"; then
        return 1  # Don't skip - secret doesn't exist
    fi

    # Check if sealed file exists
    if [[ ! -f "$file" ]]; then
        return 1  # Don't skip - file doesn't exist
    fi

    # Check if all expected keys exist in the secret
    if ! all_keys_exist_in_secret "$namespace" "$name" "$expected_keys_json"; then
        return 1  # Don't skip - missing keys
    fi

    # All conditions met - skip this secret
    return 0
}

# Function to seal a secret from a YAML file
seal_secret() {
    local input_yaml=$1
    local output_file=$2
    local cert_file=$3

    if kubeseal --format=yaml --cert="$cert_file" <"$input_yaml" >"$output_file"; then
        success "Sealed secret created: $output_file"
        return 0
    else
        error "Failed to seal secret"
        return 1
    fi
}

# Build YAML for generic secret
build_generic_secret_yaml() {
    local namespace=$1
    local name=$2
    local tmpdir=$3
    local output_yaml=$4

    cat >"$output_yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $name
  namespace: $namespace
type: Opaque
stringData:
EOF

    # Each file in the temp directory is a key, and its content is the value
    for filepath in "$tmpdir"/*; do
        [ -f "$filepath" ] || continue
        key=$(basename "$filepath")
        
        if [ -s "$filepath" ]; then
            # File has content - use proper YAML multi-line string format
            printf "  %s: |-\n" "$key" >>"$output_yaml"
            # Indent each line of the value with 4 spaces
            sed 's/^/    /' "$filepath" >>"$output_yaml"
            # Ensure trailing newline
            if [ -n "$(tail -c 1 "$filepath")" ]; then
                echo >>"$output_yaml"
            fi
        else
            # Empty file - use empty string to avoid invalid YAML
            printf '  %s: ""\n' "$key" >>"$output_yaml"
        fi
    done
}

# Build YAML for TLS secret
build_tls_secret_yaml() {
    local namespace=$1
    local name=$2
    local cert_content=$3
    local key_content=$4
    local output_yaml=$5

    local tmp_cert
    local tmp_key
    tmp_cert=$(mktemp)
    tmp_key=$(mktemp)

    echo "$cert_content" >"$tmp_cert"
    echo "$key_content" >"$tmp_key"

    kubectl -n "$namespace" create secret tls "$name" \
        --cert="$tmp_cert" \
        --key="$tmp_key" \
        --dry-run=client -o yaml >"$output_yaml"

    rm -f "$tmp_cert" "$tmp_key"
}

# Check if value name indicates it should be treated as sensitive
is_sensitive_value() {
    local name=$1
    local instruction=$2

    # Check if name or instruction contains sensitive keywords
    if echo "$name $instruction" | grep -qiE 'password|secret|token|key|credential'; then
        return 0
    fi
    return 1
}

# Check if value should be read as multiline
is_multiline_value() {
    local name=$1
    local multiline_flag=$2

    # Check extension or explicit multiline flag
    if [[ "$multiline_flag" == "true" ]]; then
        return 0
    fi
    if echo "$name" | grep -qE '\.(pem|key|crt|cert|pub)$'; then
        return 0
    fi
    return 1
}

# Prompt user for a value
prompt_value() {
    local name=$1
    local instruction=$2
    local multiline=$3
    local value=""

    if [[ -n "$instruction" ]]; then
        echo -e "${YELLOW}$instruction${NC}" >&2
    fi

    if is_multiline_value "$name" "$multiline"; then
        echo -e "${BLUE}(Enter multiline value, press Ctrl+D when done)${NC}" >&2
        value=$(cat)
    elif is_sensitive_value "$name" "$instruction"; then
        read -rs -p "Enter value for $name: " value
        echo >&2
    else
        read -r -p "Enter value for $name: " value
    fi

    echo "$value"
}

# Process a single secret definition
process_secret() {
    local secret_json=$1
    local kubeseal_cert=$2

    local namespace
    local name
    local file
    local type

    namespace=$(echo "$secret_json" | jq -r '.namespace')
    name=$(echo "$secret_json" | jq -r '.name')
    file=$(echo "$secret_json" | jq -r '.file')
    type=$(echo "$secret_json" | jq -r '.type // "generic"')

    # Extract expected key names from the values array
    local expected_keys_json
    expected_keys_json=$(echo "$secret_json" | jq -c '[.values[].name]')

    # Check if we should skip
    if should_skip_secret "$namespace" "$name" "$file" "$expected_keys_json"; then
        info "Skipping $namespace/$name (all keys present)"
        return 0
    fi

    echo
    echo -e "${BLUE}$namespace${NC} -> ${GREEN}$name${NC} ($type)"
    echo "===================="

    # Create temp directory for values
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    local values_count
    values_count=$(echo "$secret_json" | jq '.values | length')

    # Variables for TLS secrets
    local tls_cert=""
    local tls_key=""

    for ((j = 0; j < values_count; j++)); do
        local value_json
        local value_name
        local instruction
        local generate
        local multiline

        value_json=$(echo "$secret_json" | jq -r ".values[$j]")
        value_name=$(echo "$value_json" | jq -r '.name')
        instruction=$(echo "$value_json" | jq -r '.instruction // empty')
        generate=$(echo "$value_json" | jq -r '.generate // empty')
        multiline=$(echo "$value_json" | jq -r '.multiline // "false"')

        local value=""

        if [[ -n "$generate" ]]; then
            # Auto-generate value
            info "Generating $value_name..."
            if ! value=$(eval "$generate" 2>&1); then
                warn "Generation failed for $value_name, falling back to prompt"
                value=$(prompt_value "$value_name" "$instruction" "$multiline")
            fi
        else
            # Prompt user
            value=$(prompt_value "$value_name" "$instruction" "$multiline")
        fi

        if [[ "$type" == "tls" ]]; then
            # For TLS secrets, store cert and key separately
            if [[ "$value_name" == "tls.crt" ]] || [[ "$value_name" == "cert" ]]; then
                tls_cert="$value"
            elif [[ "$value_name" == "tls.key" ]] || [[ "$value_name" == "key" ]]; then
                tls_key="$value"
            fi
        else
            # For generic secrets, write to temp file
            printf '%s' "$value" >"$tmpdir/$value_name"
        fi
    done

    # Build and seal the secret
    local tmp_yaml
    tmp_yaml=$(mktemp)

    if [[ "$type" == "tls" ]]; then
        build_tls_secret_yaml "$namespace" "$name" "$tls_cert" "$tls_key" "$tmp_yaml"
    else
        build_generic_secret_yaml "$namespace" "$name" "$tmpdir" "$tmp_yaml"
    fi

    # Debug: Show YAML structure with redacted values
    if [[ "$DEBUG" == "true" ]]; then
        echo
        info "Generated YAML structure (values redacted):"
        echo "---"
        # Show YAML but redact actual secret values (lines with 4+ spaces of indentation)
        sed -E 's/^(    +).+$/\1[REDACTED]/' "$tmp_yaml"
        echo "---"
    fi

    # Create output directory if needed
    local output_dir
    output_dir=$(dirname "$file")
    mkdir -p "$output_dir"

    # Skip sealing in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry-run mode: skipping seal for $namespace/$name"
        rm -f "$tmp_yaml"
        return 0
    fi

    # Seal the secret
    if seal_secret "$tmp_yaml" "$file" "$kubeseal_cert"; then
        rm -f "$tmp_yaml"
        return 0
    else
        rm -f "$tmp_yaml"
        return 1
    fi
}

# Main execution
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug)
                DEBUG=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Create and seal Kubernetes secrets based on secrets.json definitions."
                echo ""
                echo "Options:"
                echo "  --debug     Print generated YAML structure (with redacted values) before sealing"
                echo "  --dry-run   Generate YAML but skip sealing (implies --debug)"
                echo "  --help, -h  Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # --dry-run implies --debug
    if [[ "$DRY_RUN" == "true" ]]; then
        DEBUG=true
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local secrets_file="$script_dir/secrets.json"

    if [[ ! -f "$secrets_file" ]]; then
        error "secrets.json not found at $secrets_file"
        exit 1
    fi

    # Check dependencies
    for cmd in kubectl kubeseal jq; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done

    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to the cluster. Check your kubeconfig."
        exit 1
    fi

    info "Fetching sealed-secrets certificate..."
    local kubeseal_cert
    kubeseal_cert=$(mktemp)
    if ! kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=flux-system >"$kubeseal_cert"; then
        error "Failed to fetch sealed-secrets certificate"
        rm -f "$kubeseal_cert"
        exit 1
    fi

    info "Reading secret definitions from $secrets_file"

    local secrets_count
    secrets_count=$(jq '.secrets | length' "$secrets_file")

    info "Found $secrets_count secret definitions"
    echo

    local failed=0
    for ((i = 0; i < secrets_count; i++)); do
        local secret
        secret=$(jq -c ".secrets[$i]" "$secrets_file")
        if ! process_secret "$secret" "$kubeseal_cert"; then
            ((failed++))
        fi
    done

    rm -f "$kubeseal_cert"

    echo
    if [[ $failed -eq 0 ]]; then
        success "All secrets processed successfully!"
    else
        warn "$failed secret(s) failed to process"
        exit 1
    fi
}

main "$@"
