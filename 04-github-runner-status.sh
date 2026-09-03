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

while IFS=: read -r USER_NAME _ UID GID _ HOME SHELL; do

    [[ "$USER_NAME" == "${RUNNER_PREFIX}"* ]] || continue

    FOUND=1

    RUNNER_ID="${USER_NAME#${RUNNER_PREFIX}}"
    RUNNER_DIR="/opt/${USER_NAME}"

    echo "Runner:     $RUNNER_ID"
    echo "User:       $USER_NAME"
    echo "UID:        $UID"
    echo "Home:       $HOME"
    echo "Shell:      $SHELL"

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
    # Processes
    # --------------------------------------------------------

    PROCESS_COUNT=$(
        pgrep -u "$USER_NAME" -f 'Runner.Listener|runsvc.sh' 2>/dev/null |
        wc -l
    )

    if [[ "$PROCESS_COUNT" -gt 0 ]]; then
        echo "Process:    RUNNING"
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
# Services
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
    echo "No runner services found."
else
    while read -r SERVICE; do
        [[ -z "$SERVICE" ]] && continue

        ACTIVE=$(systemctl is-active "$SERVICE" 2>/dev/null || true)
        ENABLED=$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)
        USER=$(systemctl show "$SERVICE" --property=User --value)

        echo
        echo "Service:    $SERVICE"
        echo "Active:     $ACTIVE"
        echo "Enabled:    $ENABLED"
        echo "User:       ${USER:-root}"
    done <<< "$SERVICES"
fi

echo