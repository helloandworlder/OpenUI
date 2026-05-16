#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

OPENUI_REPO="${OPENUI_REPO:-helloandworlder/OpenUI}"
OPENUI_INSTALL_DIR="${OPENUI_INSTALL_DIR:-/usr/local/open-ui}"
OPENUI_BINARY="${OPENUI_BINARY:-${OPENUI_INSTALL_DIR}/open-ui}"
OPENUI_SERVICE_NAME="${OPENUI_SERVICE_NAME:-open-ui}"

need_root() {
    [[ ${EUID} -ne 0 ]] && echo -e "${red}Fatal error:${plain} Please run as root." && exit 1
}

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${red}Unsupported CPU architecture: $(uname -m)${plain}" && exit 1 ;;
    esac
}

latest_version() {
    curl -fsSL "https://api.github.com/repos/${OPENUI_REPO}/releases/latest" \
        | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        | head -n1
}

restart_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "${OPENUI_SERVICE_NAME}"
        return
    fi
    if command -v rc-service >/dev/null 2>&1; then
        rc-service "${OPENUI_SERVICE_NAME}" restart
        return
    fi
    echo -e "${yellow}Service manager not found. Restart OpenUI manually.${plain}"
}

update_openui() {
    need_root
    local version="${1:-latest}"
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
    trap 'rm -rf "${tmpdir}"' RETURN

    echo -e "${green}Updating OpenUI to ${version} (${platform})...${plain}"
    curl -fL --retry 3 --retry-delay 2 -o "${tmpdir}/${asset}" "${url}"
    tar -zxf "${tmpdir}/${asset}" -C "${tmpdir}"
    if [[ ! -x "${tmpdir}/open-ui/open-ui" ]]; then
        echo -e "${red}Fatal error:${plain} Release archive does not contain open-ui binary." >&2
        exit 1
    fi

    install -m 0755 "${tmpdir}/open-ui/open-ui" "${OPENUI_BINARY}"
    if [[ -d "${tmpdir}/open-ui/bin" ]]; then
        mkdir -p "${OPENUI_INSTALL_DIR}/bin"
        cp -a "${tmpdir}/open-ui/bin/." "${OPENUI_INSTALL_DIR}/bin/"
        find "${OPENUI_INSTALL_DIR}/bin" -type f -name 'xray-*' -exec chmod 0755 {} \; 2>/dev/null || true
    fi
    if [[ -f "${tmpdir}/open-ui/open-ui.sh" ]]; then
        install -m 0755 "${tmpdir}/open-ui/open-ui.sh" /usr/bin/open-ui
    fi

    restart_service
    echo -e "${green}OpenUI ${version} update finished.${plain}"
}

case "${1:-}" in
    update)
        shift
        update_openui "${1:-latest}"
        ;;
    restart)
        need_root
        restart_service
        ;;
    start)
        need_root
        if command -v systemctl >/dev/null 2>&1; then
            systemctl start "${OPENUI_SERVICE_NAME}"
        else
            rc-service "${OPENUI_SERVICE_NAME}" start
        fi
        ;;
    stop)
        need_root
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop "${OPENUI_SERVICE_NAME}"
        else
            rc-service "${OPENUI_SERVICE_NAME}" stop
        fi
        ;;
    status)
        if command -v systemctl >/dev/null 2>&1; then
            systemctl status "${OPENUI_SERVICE_NAME}" -l
        else
            rc-service "${OPENUI_SERVICE_NAME}" status
        fi
        ;;
    version)
        "${OPENUI_BINARY}" version
        ;;
    "")
        "${OPENUI_BINARY}"
        ;;
    *)
        exec "${OPENUI_BINARY}" "$@"
        ;;
esac
