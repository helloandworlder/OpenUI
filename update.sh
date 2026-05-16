#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

OPENUI_REPO="${OPENUI_REPO:-helloandworlder/OpenUI}"
OPENUI_INSTALL_DIR="${OPENUI_INSTALL_DIR:-/usr/local/open-ui}"
OPENUI_CLI="${OPENUI_CLI:-/usr/bin/open-ui}"
OPENUI_SERVICE_NAME="${OPENUI_SERVICE_NAME:-open-ui}"
OPENUI_SERVICE_DIR="${OPENUI_SERVICE_DIR:-/etc/systemd/system}"
OPENUI_VERSION="${1:-${OPENUI_VERSION:-latest}}"

[[ ${EUID} -ne 0 ]] && echo -e "${red}Fatal error:${plain} Please run this script as root." && exit 1

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    release="${ID}"
else
    echo -e "${red}Fatal error:${plain} Failed to detect Linux distribution." >&2
    exit 1
fi

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        *) echo -e "${red}Unsupported CPU architecture: $(uname -m). OpenUI update currently supports linux-amd64 only.${plain}" >&2 && exit 1 ;;
    esac
}

latest_version() {
    curl -fsSL "https://api.github.com/repos/${OPENUI_REPO}/releases/latest" \
        | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        | head -n1
}

stop_openui() {
    if [[ "${release}" == "alpine" ]]; then
        rc-service "${OPENUI_SERVICE_NAME}" stop >/dev/null 2>&1 || true
    else
        systemctl stop "${OPENUI_SERVICE_NAME}" >/dev/null 2>&1 || true
    fi
}

start_openui() {
    if [[ "${release}" == "alpine" ]]; then
        rc-service "${OPENUI_SERVICE_NAME}" start
    else
        systemctl daemon-reload
        systemctl enable "${OPENUI_SERVICE_NAME}"
        systemctl start "${OPENUI_SERVICE_NAME}"
    fi
}

main() {
    local version="${OPENUI_VERSION}"
    if [[ "${version}" == "latest" ]]; then
        version="$(latest_version)"
        if [[ -z "${version}" ]]; then
            echo -e "${red}Fatal error:${plain} Failed to resolve latest OpenUI release." >&2
            exit 1
        fi
    fi

    local platform
    platform="$(arch)"
    local asset="open-ui-linux-${platform}.tar.gz"
    local url="https://github.com/${OPENUI_REPO}/releases/download/${version}/${asset}"
    local tmpdir
    tmpdir="$(mktemp -d)"

    echo -e "${green}Updating OpenUI to ${version} for linux-${platform}...${plain}"
    curl -fL --retry 3 --retry-delay 2 -o "${tmpdir}/${asset}" "${url}"
    tar -zxf "${tmpdir}/${asset}" -C "${tmpdir}"

    if [[ ! -x "${tmpdir}/open-ui/open-ui" ]]; then
        rm -rf "${tmpdir}"
        echo -e "${red}Fatal error:${plain} Release archive does not contain open-ui binary." >&2
        exit 1
    fi

    stop_openui
    mkdir -p "${OPENUI_INSTALL_DIR}"
    cp -a "${tmpdir}/open-ui/." "${OPENUI_INSTALL_DIR}/"
    install -m 0755 "${OPENUI_INSTALL_DIR}/open-ui.sh" "${OPENUI_CLI}"
    chmod 0755 "${OPENUI_INSTALL_DIR}/open-ui"
    find "${OPENUI_INSTALL_DIR}/bin" -type f -name 'xray-*' -exec chmod 0755 {} \; 2>/dev/null || true

    if [[ "${release}" == "alpine" ]]; then
        install -m 0755 "${OPENUI_INSTALL_DIR}/open-ui.rc" "/etc/init.d/${OPENUI_SERVICE_NAME}"
        rc-update add "${OPENUI_SERVICE_NAME}" default
    else
        local service_source="${OPENUI_INSTALL_DIR}/open-ui.service.debian"
        case "${release}" in
            arch | manjaro | parch) service_source="${OPENUI_INSTALL_DIR}/open-ui.service.arch" ;;
            fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol | centos) service_source="${OPENUI_INSTALL_DIR}/open-ui.service.rhel" ;;
        esac
        install -m 0644 "${service_source}" "${OPENUI_SERVICE_DIR}/${OPENUI_SERVICE_NAME}.service"
    fi

    start_openui
    rm -rf "${tmpdir}"
    echo -e "${green}OpenUI ${version} update finished.${plain}"
}

main "$@"
