#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Configuration
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo -E $0"
    exit 1
fi

# ------------------------------------------------------------
# Runner ID
# ------------------------------------------------------------

if [[ -z "${RUNNER_ID:-}" ]]; then
    read -rp "Runner ID: " RUNNER_ID
fi

if [[ -z "$RUNNER_ID" ]]; then
    echo "Runner ID cannot be empty."
    exit 1
fi

# Only allow safe characters for the Linux username.
if [[ ! "$RUNNER_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Runner ID may only contain letters, numbers, '-' and '_'."
    exit 1
fi

# ------------------------------------------------------------
# GitHub URL
# ------------------------------------------------------------

if [[ -z "${GITHUB_RUNNER_URL:-}" ]]; then
    read -rp "GitHub repository/organization URL: " GITHUB_RUNNER_URL
fi

if [[ -z "$GITHUB_RUNNER_URL" ]]; then
    echo "GitHub URL cannot be empty."
    exit 1
fi

# ------------------------------------------------------------
# GitHub registration token
# ------------------------------------------------------------

if [[ -z "${GITHUB_RUNNER_TOKEN:-}" ]]; then
    read -rsp "GitHub runner registration token: " GITHUB_RUNNER_TOKEN
    echo
fi

if [[ -z "$GITHUB_RUNNER_TOKEN" ]]; then
    echo "GitHub runner token cannot be empty."
    exit 1
fi

# ------------------------------------------------------------
# Runner name
# ------------------------------------------------------------

RUNNER_NAME="${RUNNER_NAME:-runner-${RUNNER_ID}}"

if [[ -z "${RUNNER_NAME:-}" ]]; then
    read -rp "Runner name: " RUNNER_NAME
fi

if [[ -z "$RUNNER_NAME" ]]; then
    echo "Runner name cannot be empty."
    exit 1
fi

# ------------------------------------------------------------
# Runner labels
# ------------------------------------------------------------

DEFAULT_LABELS="linux,ubuntu,docker"

if [[ -z "${RUNNER_LABELS:-}" ]]; then
    read -rp "Runner labels [$DEFAULT_LABELS]: " RUNNER_LABELS
    RUNNER_LABELS="${RUNNER_LABELS:-$DEFAULT_LABELS}"
fi

# ------------------------------------------------------------
# Derived configuration
# ------------------------------------------------------------

RUNNER_USER="github-runner-${RUNNER_ID}"
RUNNER_DIR="/opt/${RUNNER_USER}"

# ------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------

echo
echo "============================================================"
echo " GitHub Actions Runner"
echo "============================================================"
echo
echo "Runner ID:     $RUNNER_ID"
echo "Runner name:   $RUNNER_NAME"
echo "Linux user:    $RUNNER_USER"
echo "Runner path:   $RUNNER_DIR"
echo "GitHub URL:    $GITHUB_RUNNER_URL"
echo "Runner labels: $RUNNER_LABELS"
echo
echo "============================================================"
echo

if [[ "${AUTO_CONFIRM:-false}" != "true" ]]; then
    read -rp "Continue? [Y/n] " CONFIRM

    if [[ "${CONFIRM:-Y}" =~ ^[Nn]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ============================================================
# Check Ubuntu
# ============================================================

if [[ ! -f /etc/os-release ]]; then
    echo "Unable to determine operating system."
    exit 1
fi

source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "This script is intended for Ubuntu."
    echo "Detected: ${PRETTY_NAME:-unknown}"
    exit 1
fi

echo
echo "==> Ubuntu detected: ${PRETTY_NAME}"

# ============================================================
# Check Docker
# ============================================================

echo
echo "==> Checking Docker"

if ! command -v docker &>/dev/null; then
    echo
    echo "Docker is not installed."
    echo "Please run the Docker installation script first."
    exit 1
fi

systemctl enable --now docker

echo "Docker: $(docker --version)"

# ============================================================
# Create runner user
# ============================================================

echo
echo "==> Creating runner user"

if id "$RUNNER_USER" &>/dev/null; then
    echo "User already exists: $RUNNER_USER"
else
    useradd \
        --create-home \
        --shell /usr/sbin/nologin \
        "$RUNNER_USER"

    echo "Created user: $RUNNER_USER"
fi

# ============================================================
# Docker permissions
# ============================================================

echo
echo "==> Adding $RUNNER_USER to docker group"

usermod -aG docker "$RUNNER_USER"

# ============================================================
# Runner directory
# ============================================================

echo
echo "==> Creating runner directory"

mkdir -p "$RUNNER_DIR"

chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

# ============================================================
# Determine architecture
# ============================================================

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)
        RUNNER_ARCH="x64"
        ;;
    aarch64)
        RUNNER_ARCH="arm64"
        ;;
    armv7l)
        RUNNER_ARCH="arm"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo
echo "==> Architecture: $RUNNER_ARCH"

# ============================================================
# Get latest GitHub Actions runner
# ============================================================

echo
echo "==> Getting latest GitHub Actions runner version"

RUNNER_VERSION="$(
    curl -fsSL \
        https://api.github.com/repos/actions/runner/releases/latest |
    grep '"tag_name":' |
    sed -E 's/.*"v([^"]+)".*/\1/'
)"

if [[ -z "$RUNNER_VERSION" ]]; then
    echo "Failed to determine latest runner version."
    exit 1
fi

echo "Runner version: $RUNNER_VERSION"

RUNNER_FILE="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_FILE}"

# ============================================================
# Download runner
# ============================================================

echo
echo "==> Downloading GitHub Actions runner"

sudo -u "$RUNNER_USER" curl -fsSL \
    -o "$RUNNER_DIR/$RUNNER_FILE" \
    "$RUNNER_URL"

# ============================================================
# Extract runner
# ============================================================

echo
echo "==> Extracting runner"

sudo -u "$RUNNER_USER" tar -xzf \
    "$RUNNER_DIR/$RUNNER_FILE" \
    -C "$RUNNER_DIR"

rm "$RUNNER_DIR/$RUNNER_FILE"

# ============================================================
# Install runner dependencies
# ============================================================

echo
echo "==> Installing GitHub Actions runner dependencies"

"$RUNNER_DIR/bin/installdependencies.sh"

# ============================================================
# Install Azure CLI
# ============================================================

echo
echo "==> Installing Azure CLI"

if command -v az &>/dev/null; then
    echo "Azure CLI is already installed: $(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo unknown)"
else
    curl -fsSL https://aka.ms/InstallAzureCLIDeb | bash

    echo "Azure CLI: $(az version --query '"azure-cli"' -o tsv)"
fi

# ============================================================
# Configure runner
# ============================================================

echo
echo "==> Configuring GitHub Actions runner"

sudo -u "$RUNNER_USER" "$RUNNER_DIR/config.sh" \
    --url "$GITHUB_RUNNER_URL" \
    --token "$GITHUB_RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --work "_work" \
    --labels "$RUNNER_LABELS" \
    --unattended

# ============================================================
# Ensure ownership
# ============================================================

echo
echo "==> Setting runner directory ownership"

chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

# ============================================================
# Install systemd service
# ============================================================

echo
echo "==> Installing systemd service"

cd "$RUNNER_DIR"

./svc.sh install "$RUNNER_USER"

# ============================================================
# Start service
# ============================================================

echo
echo "==> Starting GitHub Actions runner"

./svc.sh start

# ============================================================
# Result
# ============================================================

echo
echo "============================================================"
echo " GitHub Actions runner installed successfully"
echo "============================================================"
echo
echo "Runner:     $RUNNER_NAME"
echo "User:       $RUNNER_USER"
echo "Directory:  $RUNNER_DIR"
echo "Labels:     $RUNNER_LABELS"
echo
echo "Service:"
./svc.sh status
echo