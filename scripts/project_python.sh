#!/usr/bin/env bash
# Run Python from the SpaceInvader project virtual environment.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_PYTHON="${PROJECT_ROOT}/.venv/bin/python"

if [[ ! -x "${PROJECT_PYTHON}" ]]; then
    cat >&2 <<EOF
SpaceInvader project virtual environment is not ready.

Run setup on the Pi first:
  sudo bash ${PROJECT_ROOT}/scripts/setup_pi_overlay.sh

Then use:
  ${PROJECT_PYTHON} ...
EOF
    exit 1
fi

exec "${PROJECT_PYTHON}" "$@"
