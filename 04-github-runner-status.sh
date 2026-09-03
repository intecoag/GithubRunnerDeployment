#!/usr/bin/env bash
set -euo pipefail

RUNNER_PREFIX="github-runner-"

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

echo
echo "============================================================"
echo " GitHub Actions Runners"
echo "============================================================"
echo

FOUND=0

# ============================================================
# Runner users
# ============================================================

while IFS=: read -r USER_NAME _ USER_UID USER_GID _ USER_HOME USER_SHELL; do

    # Only consider users created for GitHub runners
    [[ "$USER_NAME" == "${RUNNER_PREFIX}"* ]] || continue

    FOUND=1

    RUNNER_ID="${USER_NAME#${RUNNER_PREFIX}}"
    RUNNER_DIR="/opt/${USER_NAME}"

    echo "Runner:     $RUNNER_ID"
    echo "User:       $USER_NAME"
    echo "UID:        $USER_UID"
    echo "Home:       $USER_HOME"
    echo "Shell:      $USER_SHELL"

    # --------------------------------------------------------
    # Docker access
    # --------------------------------------------------------

    if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx docker; then
        echo "Docker:     YES"
    else
        echo "Docker:     NO"
    fi

    # --------------------------------------------------------
    # Runner directory
    # --------------------------------------------------------

    if [[ -d "$RUNNER_DIR" ]]; then
        echo "Directory:  OK"
    else
        echo "Directory:  MISSING"
    fi

    # --------------------------------------------------------
    # Runner process
    # --------------------------------------------------------

    PROCESS_COUNT=$(
        pgrep -u "$USER_NAME" -f 'Runner.Listener|runsvc.sh' 2>/dev/null |
        wc -l
    )

    if [[ "$PROCESS_COUNT" -gt 0 ]]; then
        echo "Process:    RUNNING ($PROCESS_COUNT processes)"
    else
        echo "Process:    NOT RUNNING"
    fi

    echo
    echo "------------------------------------------------------------"
    echo

done < /etc/passwd

if [[ "$FOUND" -eq 0 ]]; then
    echo "No GitHub runner users found."
    echo
fi

# ============================================================
# Systemd services
# ============================================================

echo "GitHub Runner Services"
echo "============================================================"

SERVICES=$(
    systemctl list-unit-files \
        --type=service \
        --no-legend |
    awk '{print $1}' |
    grep '^actions\.runner\..*\.service$' || true
)

if [[ -z "$SERVICES" ]]; then
    echo "No GitHub runner services found."
else
    while read -r SERVICE; do

        [[ -z "$SERVICE" ]] && continue

        ACTIVE=$(systemctl is-active "$SERVICE" 2>/dev/null || true)
        ENABLED=$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)
        SERVICE_USER=$(systemctl show "$SERVICE" \
            --property=User \
            --value)

        echo
        echo "Service:    $SERVICE"
        echo "Active:     $ACTIVE"
        echo "Enabled:    $ENABLED"
        echo "User:       ${SERVICE_USER:-root}"

    done <<< "$SERVICES"
fi

echo