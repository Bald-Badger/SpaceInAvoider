#!/usr/bin/env bash
# One-time persistent setup for the Stratux/Raspberry Pi overlay filesystem.
#
# Run from the Pi with sudo:
#
#   sudo bash /rwbase/playground/SpaceInvader/scripts/setup_pi_overlay.sh
#
# Stratux keeps / as a small writable overlay, so normal installs can disappear
# after reboot. This script applies setup both to the live overlay for the
# current boot and to /overlay/robase, the persistent lower root used on reboot.

set -Eeuo pipefail

ARGON_ONE_INSTALLER_URL="https://download.argon40.com/argon1.sh"
APT_DATE_REFERENCE_URL="http://deb.debian.org/debian/"
MAX_CLOCK_SKEW_SECONDS=300
DEFAULT_PERSISTENT_ROOT="/overlay/robase"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_VENV="${PROJECT_ROOT}/.venv"
LOG_DIR="${PROJECT_ROOT}/setup-logs"

# Add apt packages here when a missing Python module needs system support.
# These are installed into both the live root and /overlay/robase when enabled.
SYSTEM_APT_PACKAGES=(
    ca-certificates
    python3-venv
)

# These were pulled by an earlier python3-full attempt and are too large for
# the small Stratux live overlay. Keep the project on python3-venv instead.
UNWANTED_APT_PACKAGES=(
    idle
    idle-python3.11
    libjs-mathjax
    libpython3.11-testsuite
    python3-doc
    python3-examples
    python3-full
    python3-tk
    python3.11-doc
    python3.11-examples
    python3.11-full
)

# Add missing Python modules here. These are installed into PROJECT_VENV, which
# should live under /rwbase/playground/SpaceInvader and survive reboot.
PYTHON_PIP_PACKAGES=(
    "pygame-ce>=2.5"
)

PERSISTENT_ROOT="${DEFAULT_PERSISTENT_ROOT}"
RUN_LIVE_APPLY=1
RUN_PERSISTENT_APPLY=1
FORCE=0

BIND_MOUNTS=()
PERSISTENT_ROOT_WAS_RO=0
LOG_FILE=""


usage() {
    cat <<EOF
Usage: sudo bash scripts/setup_pi_overlay.sh [options]

Options:
  --persistent-root PATH  Persistent lower root to modify.
                          Default: ${DEFAULT_PERSISTENT_ROOT}
  --live-only             Apply setup only to the current live root.
  --persistent-only       Apply setup only to the persistent lower root.
  --skip-live             Do not apply setup to the current live root.
  --skip-persistent       Do not apply setup to the persistent lower root.
  --force                 Re-run actions even if local markers already exist.
  -h, --help              Show this help.

This currently installs:
  - system apt packages listed in SYSTEM_APT_PACKAGES
  - dedicated project virtual environment:
    ${PROJECT_VENV}
  - Python packages listed in PYTHON_PIP_PACKAGES into:
    ${PROJECT_VENV}
  - Argon ONE fan control using:
    curl ${ARGON_ONE_INSTALLER_URL} | bash

After a persistent-root install, reboot the Pi so the modified lower root is
used by the overlay on the next boot.
EOF
}


log() {
    printf '[setup] %s\n' "$*"
}


warn() {
    printf '[setup][warn] %s\n' "$*" >&2
}


die() {
    printf '[setup][error] %s\n' "$*" >&2
    exit 1
}


run() {
    log "running: $*"
    "$@"
}


parse_args() {
    while (($#)); do
        case "$1" in
            --persistent-root)
                [[ $# -ge 2 ]] || die "--persistent-root needs a path"
                PERSISTENT_ROOT="$2"
                shift 2
                ;;
            --live-only)
                RUN_LIVE_APPLY=1
                RUN_PERSISTENT_APPLY=0
                shift
                ;;
            --persistent-only)
                RUN_LIVE_APPLY=0
                RUN_PERSISTENT_APPLY=1
                shift
                ;;
            --skip-live)
                RUN_LIVE_APPLY=0
                shift
                ;;
            --skip-persistent)
                RUN_PERSISTENT_APPLY=0
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}


require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Run this with sudo, for example: sudo bash ${BASH_SOURCE[0]}"
    fi
}


validate_modes() {
    if [[ "${RUN_LIVE_APPLY}" -eq 0 && "${RUN_PERSISTENT_APPLY}" -eq 0 ]]; then
        die "Both live and persistent setup were disabled; nothing to do."
    fi
}


init_logging() {
    mkdir -p "${LOG_DIR}" 2>/dev/null || LOG_DIR="/tmp/spaceinvader-setup-logs"
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "${LOG_FILE}") 2>&1
    log "logging to ${LOG_FILE}"
}


require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}


check_host_tools() {
    require_command bash
    require_command chroot
    require_command curl
    require_command date
    require_command findmnt
    require_command mount
    require_command stat
    require_command tee
    require_command umount
}


overlay_root_is_active() {
    [[ "$(findmnt -n -o FSTYPE / 2>/dev/null || true)" == "overlay" ]]
}


persistent_root_exists() {
    [[ -d "${PERSISTENT_ROOT}/etc" && -x "${PERSISTENT_ROOT}/bin/bash" ]]
}


is_mountpoint() {
    findmnt -rn --mountpoint "$1" >/dev/null 2>&1
}


mount_bind_dir() {
    local source="$1"
    local target="$2"

    [[ -d "${source}" ]] || return 0
    mkdir -p "${target}"

    if is_mountpoint "${target}"; then
        log "mount already present: ${target}"
        return 0
    fi

    run mount --rbind "${source}" "${target}"
    mount --make-rslave "${target}" 2>/dev/null || true
    BIND_MOUNTS+=("${target}")
}


mount_bind_file() {
    local source="$1"
    local target="$2"

    [[ -f "${source}" ]] || return 0
    mkdir -p "$(dirname -- "${target}")"

    if [[ -L "${target}" ]]; then
        log "leaving symlinked file alone in chroot: ${target}"
        return 0
    fi

    [[ -e "${target}" ]] || touch "${target}"

    if is_mountpoint "${target}"; then
        log "mount already present: ${target}"
        return 0
    fi

    run mount --bind "${source}" "${target}"
    BIND_MOUNTS+=("${target}")
}


mount_chroot_helpers() {
    mount_bind_dir /dev "${PERSISTENT_ROOT}/dev"
    mount_bind_dir /proc "${PERSISTENT_ROOT}/proc"
    mount_bind_dir /sys "${PERSISTENT_ROOT}/sys"
    mount_bind_dir /run "${PERSISTENT_ROOT}/run"
    mount_bind_dir /boot/firmware "${PERSISTENT_ROOT}/boot/firmware"
    mount_bind_file /etc/resolv.conf "${PERSISTENT_ROOT}/etc/resolv.conf"
}


cleanup_chroot_helpers() {
    local index

    for ((index=${#BIND_MOUNTS[@]} - 1; index >= 0; index--)); do
        local target="${BIND_MOUNTS[index]}"
        log "unmounting ${target}"
        umount -R "${target}" 2>/dev/null || umount "${target}" 2>/dev/null || true
    done

    BIND_MOUNTS=()
}


remount_persistent_root_rw() {
    local options

    is_mountpoint "${PERSISTENT_ROOT}" || die "${PERSISTENT_ROOT} is not a mountpoint"
    options="$(findmnt -n -o OPTIONS --mountpoint "${PERSISTENT_ROOT}")"

    case ",${options}," in
        *,ro,*)
            log "remounting ${PERSISTENT_ROOT} read-write"
            run mount -o remount,rw "${PERSISTENT_ROOT}"
            PERSISTENT_ROOT_WAS_RO=1
            ;;
        *)
            log "${PERSISTENT_ROOT} is already writable"
            ;;
    esac
}


restore_persistent_root_ro() {
    if [[ "${PERSISTENT_ROOT_WAS_RO}" -eq 1 ]]; then
        log "remounting ${PERSISTENT_ROOT} read-only"
        mount -o remount,ro "${PERSISTENT_ROOT}" \
            || warn "Could not remount ${PERSISTENT_ROOT} read-only. Reboot will restore normal overlay state."
    fi
}


begin_persistent_root_changes() {
    if ! persistent_root_exists; then
        warn "Persistent root ${PERSISTENT_ROOT} was not found; skipping persistent install."
        return 1
    fi

    remount_persistent_root_rw
    mount_chroot_helpers
}


end_persistent_root_changes() {
    cleanup_chroot_helpers
    restore_persistent_root_ro
}


apt_get_exists_in_persistent_root() {
    [[ -x "${PERSISTENT_ROOT}/usr/bin/apt-get" || -x "${PERSISTENT_ROOT}/bin/apt-get" ]]
}


dpkg_exists_in_persistent_root() {
    [[ -x "${PERSISTENT_ROOT}/usr/bin/dpkg" || -x "${PERSISTENT_ROOT}/bin/dpkg" ]]
}


remote_http_date_epoch() {
    local date_text=""
    local line

    while IFS= read -r line; do
        line="${line%$'\r'}"
        case "${line,,}" in
            date:*)
                date_text="${line#*: }"
                ;;
        esac
    done < <(curl -fsSI --max-time 10 "${APT_DATE_REFERENCE_URL}" 2>/dev/null)

    [[ -n "${date_text}" ]] || return 1
    date -u -d "${date_text}" +%s
}


ensure_clock_for_apt() {
    local current_epoch
    local remote_epoch
    local skew_seconds
    local abs_skew_seconds

    log "checking system clock before apt operations"

    if ! remote_epoch="$(remote_http_date_epoch)"; then
        warn "Could not read Date header from ${APT_DATE_REFERENCE_URL}; apt may fail if the Pi clock is wrong."
        return 0
    fi

    current_epoch="$(date -u +%s)"
    skew_seconds=$((remote_epoch - current_epoch))
    abs_skew_seconds="${skew_seconds#-}"

    if ((abs_skew_seconds <= MAX_CLOCK_SKEW_SECONDS)); then
        log "system clock is close enough for apt"
        return 0
    fi

    warn "System clock differs from ${APT_DATE_REFERENCE_URL} by ${skew_seconds} seconds."
    warn "Setting the live system clock so apt release-file date checks can pass."
    run date -u -s "@${remote_epoch}"
}


repair_live_dpkg_if_needed() {
    if ! command -v dpkg >/dev/null 2>&1; then
        return 0
    fi

    log "repairing live dpkg state if needed"
    env DEBIAN_FRONTEND=noninteractive dpkg --configure -a \
        || warn "Live dpkg repair did not finish cleanly; apt purge/install will try to recover."
}


repair_persistent_dpkg_if_needed() {
    if ! dpkg_exists_in_persistent_root; then
        warn "dpkg is not available in ${PERSISTENT_ROOT}; skipping persistent dpkg repair."
        return 0
    fi

    log "repairing persistent dpkg state if needed"
    chroot "${PERSISTENT_ROOT}" env DEBIAN_FRONTEND=noninteractive \
        dpkg --configure -a \
        || warn "Persistent dpkg repair did not finish cleanly; apt purge/install will try to recover."
}


purge_live_unwanted_apt_packages() {
    if ((${#UNWANTED_APT_PACKAGES[@]} == 0)); then
        return 0
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        return 0
    fi

    log "purging live apt packages that are too large for the overlay: ${UNWANTED_APT_PACKAGES[*]}"
    env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${UNWANTED_APT_PACKAGES[@]}" || true
    env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
    apt-get clean || true
}


purge_persistent_unwanted_apt_packages() {
    if ((${#UNWANTED_APT_PACKAGES[@]} == 0)); then
        return 0
    fi
    if ! apt_get_exists_in_persistent_root; then
        return 0
    fi

    log "purging persistent apt packages that are unnecessary for this project: ${UNWANTED_APT_PACKAGES[*]}"
    chroot "${PERSISTENT_ROOT}" env DEBIAN_FRONTEND=noninteractive \
        apt-get purge -y "${UNWANTED_APT_PACKAGES[@]}" || true
    chroot "${PERSISTENT_ROOT}" env DEBIAN_FRONTEND=noninteractive \
        apt-get autoremove -y || true
    chroot "${PERSISTENT_ROOT}" apt-get clean || true
}


install_live_apt_packages() {
    if ((${#SYSTEM_APT_PACKAGES[@]} == 0)); then
        log "no system apt packages configured"
        return 0
    fi

    require_command apt-get
    log "installing live apt packages: ${SYSTEM_APT_PACKAGES[*]}"
    export DEBIAN_FRONTEND=noninteractive
    purge_live_unwanted_apt_packages
    repair_live_dpkg_if_needed
    run apt-get update
    run apt-get install -y --no-install-recommends "${SYSTEM_APT_PACKAGES[@]}"
}


install_persistent_apt_packages() {
    if ((${#SYSTEM_APT_PACKAGES[@]} == 0)); then
        log "no persistent apt packages configured"
        return 0
    fi

    begin_persistent_root_changes || return 0

    if ! apt_get_exists_in_persistent_root; then
        warn "apt-get is not available in ${PERSISTENT_ROOT}; skipping persistent apt packages."
        end_persistent_root_changes
        return 0
    fi

    purge_persistent_unwanted_apt_packages
    repair_persistent_dpkg_if_needed

    log "installing persistent apt packages: ${SYSTEM_APT_PACKAGES[*]}"
    chroot "${PERSISTENT_ROOT}" env DEBIAN_FRONTEND=noninteractive \
        apt-get update
    chroot "${PERSISTENT_ROOT}" env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends "${SYSTEM_APT_PACKAGES[@]}"

    end_persistent_root_changes
}


project_owner() {
    stat -c '%U' "${PROJECT_ROOT}"
}


run_as_project_owner() {
    local owner

    owner="$(project_owner)"

    if [[ "${owner}" != "root" && "${owner}" != "UNKNOWN" ]] && command -v runuser >/dev/null 2>&1; then
        runuser -u "${owner}" -- "$@"
    elif [[ "${owner}" != "root" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] \
        && command -v sudo >/dev/null 2>&1; then
        sudo -H -u "${SUDO_USER}" "$@"
    else
        "$@"
    fi
}


setup_project_python_venv() {
    require_command python3

    log "setting up project Python virtual environment at ${PROJECT_VENV}"

    if [[ ! -x "${PROJECT_VENV}/bin/python" || "${FORCE}" -eq 1 ]]; then
        run_as_project_owner python3 -m venv "${PROJECT_VENV}"
    fi

    run_as_project_owner "${PROJECT_VENV}/bin/python" -m pip install --upgrade pip

    if ((${#PYTHON_PIP_PACKAGES[@]} == 0)); then
        log "no project Python packages configured"
        return 0
    fi

    log "installing Python packages into ${PROJECT_VENV}: ${PYTHON_PIP_PACKAGES[*]}"
    run_as_project_owner "${PROJECT_VENV}/bin/python" -m pip install "${PYTHON_PIP_PACKAGES[@]}"
    log "project Python: ${PROJECT_VENV}/bin/python"
    log "activate with: source ${PROJECT_VENV}/bin/activate"
}


run_argon_one_installer() {
    log "installing Argon ONE fan control"
    log "source: ${ARGON_ONE_INSTALLER_URL}"
    curl -fsSL "${ARGON_ONE_INSTALLER_URL}" | bash
}


run_argon_one_installer_in_persistent_root() {
    log "installing Argon ONE fan control into ${PERSISTENT_ROOT}"
    chroot "${PERSISTENT_ROOT}" /bin/bash -lc "
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! command -v sudo >/dev/null 2>&1; then
    sudo() { \"\$@\"; }
fi
if ! command -v curl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl
fi
curl -fsSL '${ARGON_ONE_INSTALLER_URL}' | bash
"
}


argon_marker_path() {
    printf '%s/.setup/argon-one-installed' "${PROJECT_ROOT}"
}


argon_marker_exists() {
    [[ -f "$(argon_marker_path)" ]]
}


write_argon_marker() {
    local marker

    marker="$(argon_marker_path)"
    mkdir -p "$(dirname -- "${marker}")"
    {
        printf 'installed_at=%s\n' "$(date --iso-8601=seconds)"
        printf 'installer_url=%s\n' "${ARGON_ONE_INSTALLER_URL}"
        printf 'persistent_root=%s\n' "${PERSISTENT_ROOT}"
        printf 'log_file=%s\n' "${LOG_FILE}"
    } >"${marker}"
}


install_argon_one() {
    if argon_marker_exists && [[ "${FORCE}" -ne 1 ]]; then
        log "Argon ONE marker already exists: $(argon_marker_path)"
        log "Use --force to run the Argon installer again."
        return 0
    fi

    if [[ "${RUN_PERSISTENT_APPLY}" -eq 1 ]]; then
        if begin_persistent_root_changes; then
            run_argon_one_installer_in_persistent_root
            end_persistent_root_changes
        fi
    fi

    if [[ "${RUN_LIVE_APPLY}" -eq 1 ]]; then
        run_argon_one_installer
    fi

    write_argon_marker
}


finish() {
    local exit_code=$?

    cleanup_chroot_helpers
    restore_persistent_root_ro

    if [[ "${exit_code}" -eq 0 ]]; then
        log "setup completed"
        if [[ "${RUN_PERSISTENT_APPLY}" -eq 1 ]]; then
            log "reboot the Pi to boot from the modified persistent lower root"
        fi
    else
        warn "setup exited with status ${exit_code}"
    fi

    exit "${exit_code}"
}


main() {
    parse_args "$@"
    validate_modes
    require_root
    init_logging
    check_host_tools

    log "project root: ${PROJECT_ROOT}"
    log "persistent root: ${PERSISTENT_ROOT}"
    log "root filesystem type: $(findmnt -n -o FSTYPE / 2>/dev/null || printf unknown)"

    if ! overlay_root_is_active; then
        warn "/ is not currently an overlay filesystem. Live installs may already be persistent."
    fi

    trap finish EXIT
    ensure_clock_for_apt
    install_persistent_apt_packages
    install_live_apt_packages
    setup_project_python_venv
    install_argon_one
}


main "$@"
