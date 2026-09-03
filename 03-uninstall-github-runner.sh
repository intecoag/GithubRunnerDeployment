#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo -E $0"
    exit 1
fi

# ============================================================
# Runner ID
# ============================================================

if [[ -z "${RUNNER_ID:-}" ]]; then
    read -rp "Runner ID: " RUNNER_ID
fi

if [[ -z "$RUNNER_ID" ]]; then
    echo "Runner ID cannot be empty."
    exit 1
fi

if [[ ! "$RUNNER_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Runner ID may only contain letters, numbers, '-' and '_'."
    exit 1
fi

# ============================================================
# Derived configuration
# ============================================================

RUNNER_USER="github-runner-${RUNNER_ID}"
RUNNER_DIR="/opt/${RUNNER_USER}"

# ============================================================
# Check runner
# ============================================================

echo
echo "============================================================"
echo " GitHub Actions Runner Uninstall"
echo "============================================================"
echo
echo "Runner ID:    $RUNNER_ID"
echo "Linux user:   $RUNNER_USER"
echo "Runner path:  $RUNNER_DIR"
echo
echo "============================================================"
echo

if [[ "${AUTO_CONFIRM:-false}" != "true" ]]; then
    read -rp "Remove this runner completely? [y/N] " CONFIRM

    if [[ ! "${CONFIRM:-N}" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ============================================================
# Stop and remove systemd service
# ============================================================

if [[ -d "$RUNNER_DIR" ]]; then
    echo
    echo "==> Stopping GitHub Actions runner"

    cd "$RUNNER_DIR"

    if [[ -x "./svc.sh" ]]; then
        ./svc.sh stop || true

        echo "==> Removing systemd service"

        ./svc.sh uninstall || true
    fi
fi

# ============================================================
# Remove runner from GitHub
# ============================================================

echo
echo "==> GitHub runner registration"

if [[ -n "${GITHUB_RUNNER_URL:-}" && -n "${GITHUB_RUNNER_TOKEN:-}" ]]; then
    echo "Removing runner registration from GitHub..."

    if [[ -d "$RUNNER_DIR" && -x "$RUNNER_DIR/config.sh" ]]; then
        sudo -u "$RUNNER_USER" \
            "$RUNNER_DIR/config.sh" \
            remove \
            --token "$GITHUB_RUNNER_TOKEN" \
            || true
    fi
else
    echo
    echo "GitHub registration was not removed automatically."
    echo
    echo "To remove the runner from GitHub as well, provide:"
    echo
    echo "  GITHUB_RUNNER_TOKEN=..."
    echo
    echo "The registration token is the removal token generated"
    echo "from the GitHub runner settings."
fi

# ============================================================
# Remove runner directory
# ============================================================

if [[ -d "$RUNNER_DIR" ]]; then
    echo
    echo "==> Removing runner directory"

    rm -rf "$RUNNER_DIR"
fi

# ============================================================
# Remove user
# ============================================================

if id "$RUNNER_USER" &>/dev/null; then
    echo
    echo "==> Removing runner user"

    userdel -r "$RUNNER_USER" || true
fi

# ============================================================
# Result
# ============================================================

echo
echo "============================================================"
echo " GitHub Actions runner removed"
echo "============================================================"
echo
echo "Runner:     $RUNNER_ID"
echo "User:       $RUNNER_USER"
echo "Directory:  $RUNNER_DIR"
echo