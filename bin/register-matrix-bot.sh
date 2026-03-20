#!/usr/bin/env bash
set -euo pipefail

# Matrix Bot Registration Script
# Registers a bot user on Synapse using the shared secret admin API

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check dependencies
for cmd in curl jq openssl; do
    if ! command -v "$cmd" &>/dev/null; then
        error "Required command '$cmd' not found. Please install it."
        exit 1
    fi
done

# Check for Python (required for HMAC calculation - bash can't handle null bytes)
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
else
    error "Python is required for HMAC calculation but not found"
    exit 1
fi

# Interactive prompts
echo
echo -e "${BLUE}Matrix Bot Registration${NC}"
echo "========================"
echo

# Prompt for shared secret (masked)
read -rs -p "Enter registration shared secret: " SHARED_SECRET
echo

if [[ -z "$SHARED_SECRET" ]]; then
    error "Shared secret is required."
    exit 1
fi

# Prompt for homeserver URL
read -r -p "Homeserver URL [https://integrations.borooka.ee]: " HOMESERVER
HOMESERVER="${HOMESERVER:-https://integrations.borooka.ee}"

# Prompt for username
read -r -p "Bot username [openclaw]: " USERNAME
USERNAME="${USERNAME:-openclaw}"

# Prompt for password (auto-generate or manual)
echo
echo -e "${YELLOW}Password options:${NC}"
echo "  1. Auto-generate a secure password (recommended)"
echo "  2. Enter password manually"
read -r -p "Choose [1]: " PASSWORD_CHOICE
PASSWORD_CHOICE="${PASSWORD_CHOICE:-1}"

if [[ "$PASSWORD_CHOICE" == "1" ]]; then
    PASSWORD=$(openssl rand -base64 24)
    info "Generated secure password"
else
    read -rs -p "Enter bot password: " PASSWORD
    echo
    if [[ -z "$PASSWORD" ]]; then
        error "Password cannot be empty."
        exit 1
    fi
fi

# Fixed values
USER_TYPE="bot"
ADMIN="false"

echo
info "Registering bot user '$USERNAME' on $HOMESERVER"

# Step 1: Request a nonce
info "Requesting nonce..."
NONCE_RESPONSE=$(curl -s -X GET "${HOMESERVER}/_synapse/admin/v1/register")

if ! echo "$NONCE_RESPONSE" | jq -e '.nonce' > /dev/null 2>&1; then
    error "Failed to get nonce. Response: $NONCE_RESPONSE"
    exit 1
fi

NONCE=$(echo "$NONCE_RESPONSE" | jq -r '.nonce')
info "Got nonce: ${NONCE:0:16}..."

# Step 2: Calculate HMAC-SHA1
# Format: nonce\0username\0password\0admin_flag[\0user_type]
# The user_type must be included in HMAC if it's being sent in the request
if [[ "$ADMIN" == "true" ]]; then
    ADMIN_FLAG="admin"
else
    ADMIN_FLAG="notadmin"
fi

# Calculate HMAC-SHA1 using Python (bash can't handle null bytes in command substitution)
MAC=$($PYTHON_CMD -c "
import hmac
import hashlib
import sys

secret = sys.argv[1]
nonce = sys.argv[2]
username = sys.argv[3]
password = sys.argv[4]
admin_flag = sys.argv[5]
user_type = sys.argv[6] if len(sys.argv) > 6 else None

parts = [nonce.encode('utf-8'), b'\x00', username.encode('utf-8'), b'\x00', password.encode('utf-8'), b'\x00', admin_flag.encode('utf-8')]
if user_type:
    parts.extend([b'\x00', user_type.encode('utf-8')])

message = b''.join(parts)
mac = hmac.new(secret.encode('utf-8'), message, hashlib.sha1)
print(mac.hexdigest())
" "$SHARED_SECRET" "$NONCE" "$USERNAME" "$PASSWORD" "$ADMIN_FLAG" ${USER_TYPE:+"$USER_TYPE"})
info "Calculated HMAC: ${MAC:0:16}..."

# Step 3: Send registration request
info "Sending registration request..."

# Build JSON payload
# user_type is optional and may not be supported on all Synapse versions
if [[ -n "$USER_TYPE" ]]; then
    PAYLOAD=$(jq -n \
        --arg nonce "$NONCE" \
        --arg username "$USERNAME" \
        --arg password "$PASSWORD" \
        --arg mac "$MAC" \
        --arg user_type "$USER_TYPE" \
        --argjson admin "$([[ "$ADMIN" == "true" ]] && echo "true" || echo "false")" \
        '{nonce: $nonce, username: $username, password: $password, mac: $mac, admin: $admin, user_type: $user_type}')
else
    PAYLOAD=$(jq -n \
        --arg nonce "$NONCE" \
        --arg username "$USERNAME" \
        --arg password "$PASSWORD" \
        --arg mac "$MAC" \
        --argjson admin "$([[ "$ADMIN" == "true" ]] && echo "true" || echo "false")" \
        '{nonce: $nonce, username: $username, password: $password, mac: $mac, admin: $admin}')
fi

REGISTER_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${HOMESERVER}/_synapse/admin/v1/register")

# Check for errors
if echo "$REGISTER_RESPONSE" | jq -e '.errcode' > /dev/null 2>&1; then
    ERRCODE=$(echo "$REGISTER_RESPONSE" | jq -r '.errcode')
    ERROR_MSG=$(echo "$REGISTER_RESPONSE" | jq -r '.error')
    
    # If user_type caused an error, retry without it
    if [[ "$ERROR_MSG" == *"user_type"* ]] || [[ "$ERRCODE" == "M_INVALID_PARAM" ]]; then
        warn "user_type not supported, retrying without it..."
        
        # Get a new nonce since the old one is consumed
        NONCE_RESPONSE=$(curl -s -X GET "${HOMESERVER}/_synapse/admin/v1/register")
        NONCE=$(echo "$NONCE_RESPONSE" | jq -r '.nonce')
        
        # Build HMAC without user_type using Python
        MAC=$($PYTHON_CMD -c "
import hmac
import hashlib
import sys

secret = sys.argv[1]
nonce = sys.argv[2]
username = sys.argv[3]
password = sys.argv[4]
admin_flag = sys.argv[5]

parts = [nonce.encode('utf-8'), b'\x00', username.encode('utf-8'), b'\x00', password.encode('utf-8'), b'\x00', admin_flag.encode('utf-8')]

message = b''.join(parts)
mac = hmac.new(secret.encode('utf-8'), message, hashlib.sha1)
print(mac.hexdigest())
" "$SHARED_SECRET" "$NONCE" "$USERNAME" "$PASSWORD" "$ADMIN_FLAG")
        
        PAYLOAD=$(jq -n \
            --arg nonce "$NONCE" \
            --arg username "$USERNAME" \
            --arg password "$PASSWORD" \
            --arg mac "$MAC" \
            --argjson admin "$([[ "$ADMIN" == "true" ]] && echo "true" || echo "false")" \
            '{nonce: $nonce, username: $username, password: $password, mac: $mac, admin: $admin}')
        
        REGISTER_RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            "${HOMESERVER}/_synapse/admin/v1/register")
    fi
fi

# Final check
if echo "$REGISTER_RESPONSE" | jq -e '.errcode' > /dev/null 2>&1; then
    ERRCODE=$(echo "$REGISTER_RESPONSE" | jq -r '.errcode')
    ERROR_MSG=$(echo "$REGISTER_RESPONSE" | jq -r '.error')
    error "Registration failed: [$ERRCODE] $ERROR_MSG"
    exit 1
fi

# Extract user_id from response
USER_ID=$(echo "$REGISTER_RESPONSE" | jq -r '.user_id // empty')
ACCESS_TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.access_token // empty')

if [[ -z "$USER_ID" ]]; then
    error "Unexpected response: $REGISTER_RESPONSE"
    exit 1
fi

success "Registration successful!"

# Step 4: Login to get access token
info "Logging in to get access token..."

LOGIN_PAYLOAD=$(jq -n \
    --arg type "m.login.password" \
    --arg user "$USERNAME" \
    --arg password "$PASSWORD" \
    '{type: $type, user: $user, password: $password}')

LOGIN_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$LOGIN_PAYLOAD" \
    "${HOMESERVER}/_matrix/client/v3/login")

if echo "$LOGIN_RESPONSE" | jq -e '.errcode' > /dev/null 2>&1; then
    ERRCODE=$(echo "$LOGIN_RESPONSE" | jq -r '.errcode')
    ERROR_MSG=$(echo "$LOGIN_RESPONSE" | jq -r '.error')
    warn "Login failed: [$ERRCODE] $ERROR_MSG"
    warn "You may need to log in manually to get an access token"
    ACCESS_TOKEN=""
else
    ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token // empty')
    if [[ -n "$ACCESS_TOKEN" ]]; then
        success "Login successful!"
    fi
fi
echo
echo "========================================"
echo -e "${GREEN}Bot Registration Complete${NC}"
echo "========================================"
echo "User ID:      $USER_ID"
echo "Username:     $USERNAME"
echo "Password:     $PASSWORD"
echo "Homeserver:   $HOMESERVER"
if [[ -n "$ACCESS_TOKEN" ]]; then
    echo "Access Token: $ACCESS_TOKEN"
fi
echo "========================================"
echo
warn "Save these credentials securely!"
