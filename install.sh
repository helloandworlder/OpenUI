#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

OPENUI_REPO="${OPENUI_REPO:-helloandworlder/OpenUI}"
OPENUI_INSTALL_DIR="${OPENUI_INSTALL_DIR:-/usr/local/open-ui}"
OPENUI_CLI="${OPENUI_CLI:-/usr/bin/open-ui}"
OPENUI_DATA_DIR="${OPENUI_DATA_DIR:-/etc/open-ui}"
OPENUI_LOG_DIR="${OPENUI_LOG_DIR:-/var/log/open-ui}"
OPENUI_SERVICE_DIR="${OPENUI_SERVICE_DIR:-/etc/systemd/system}"
OPENUI_SERVICE_NAME="${OPENUI_SERVICE_NAME:-open-ui}"
OPENUI_ENV_FILE="${OPENUI_ENV_FILE:-/etc/default/open-ui}"
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
        *) echo -e "${red}Unsupported CPU architecture: $(uname -m). OpenUI release currently supports linux-amd64 only.${plain}" >&2 && exit 1 ;;
    esac
}

install_base() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update
            apt-get install -y -q curl tar ca-certificates openssl socat
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf install -y -q curl tar ca-certificates openssl socat
            ;;
        centos)
            if [[ "${VERSION_ID:-}" =~ ^7 ]]; then
                yum install -y curl tar ca-certificates openssl socat
            else
                dnf install -y -q curl tar ca-certificates openssl socat
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm curl tar ca-certificates openssl socat
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh
            zypper -q install -y curl tar ca-certificates openssl socat
            ;;
        alpine)
            apk update
            apk add curl tar ca-certificates openssl socat openrc
            ;;
        *)
            apt-get update
            apt-get install -y -q curl tar ca-certificates openssl socat
            ;;
    esac
}

gen_random_string() {
    local length="$1"
    openssl rand -base64 $((length * 2)) | tr -dc 'a-zA-Z0-9' | head -c "${length}"
}

is_port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {found=1} END {exit found ? 0 : 1}'
        return
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | awk -v p=":${port} " '$4 ~ p {found=1} END {exit found ? 0 : 1}'
        return
    fi
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    fi
    return 1
}

pick_random_panel_port() {
    local port
    for _ in $(seq 1 40); do
        port="$(shuf -i 1024-62000 -n 1)"
        if ! is_port_in_use "${port}"; then
            echo "${port}"
            return 0
        fi
    done
    echo -e "${red}Fatal error:${plain} Failed to pick a free panel port." >&2
    exit 1
}

detect_server_ipv4() {
    local url response http_code ip_result
    local urls=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    for url in "${urls[@]}"; do
        response="$(curl -s -w "\n%{http_code}" --max-time 3 "${url}" 2>/dev/null || true)"
        http_code="$(echo "${response}" | tail -n1)"
        ip_result="$(echo "${response}" | head -n-1 | tr -d '[:space:]"')"
        if [[ "${http_code}" == "200" && "${ip_result}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${ip_result}"
            return 0
        fi
    done
    return 1
}

install_acme() {
    if [[ -x "${HOME}/.acme.sh/acme.sh" ]]; then
        return 0
    fi
    echo -e "${green}Installing acme.sh for OpenUI IP certificate...${plain}"
    curl -fsSL https://get.acme.sh | sh -s email=admin@open-ui.local
}

latest_version() {
    curl -fsSL "https://api.github.com/repos/${OPENUI_REPO}/releases/latest" \
        | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        | head -n1
}

download_release() {
    local version="$1"
    local platform
    platform="$(arch)"
    local asset="open-ui-linux-${platform}.tar.gz"
    local url="https://github.com/${OPENUI_REPO}/releases/download/${version}/${asset}"

    echo -e "${green}Downloading OpenUI ${version} for linux-${platform}...${plain}" >&2
    curl -fL --retry 3 --retry-delay 2 -o "/tmp/${asset}" "${url}"
    echo "/tmp/${asset}"
}

stop_existing() {
    if [[ "${release}" == "alpine" ]]; then
        rc-service "${OPENUI_SERVICE_NAME}" stop >/dev/null 2>&1 || true
    else
        systemctl stop "${OPENUI_SERVICE_NAME}" >/dev/null 2>&1 || true
    fi
}

install_files() {
    local archive="$1"
    local tmpdir
    tmpdir="$(mktemp -d)"

    tar -zxf "${archive}" -C "${tmpdir}"
    if [[ ! -d "${tmpdir}/open-ui" ]]; then
        rm -rf "${tmpdir}"
        echo -e "${red}Fatal error:${plain} Release archive does not contain open-ui/." >&2
        exit 1
    fi

    mkdir -p "${OPENUI_INSTALL_DIR}" "${OPENUI_DATA_DIR}" "${OPENUI_LOG_DIR}"
    cp -a "${tmpdir}/open-ui/." "${OPENUI_INSTALL_DIR}/"

    if [[ -f "${OPENUI_INSTALL_DIR}/open-ui.sh" ]]; then
        install -m 0755 "${OPENUI_INSTALL_DIR}/open-ui.sh" "${OPENUI_CLI}"
    else
        cat > "${OPENUI_CLI}" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  start|stop|restart|status)
    exec systemctl "$1" open-ui
    ;;
  version)
    exec /usr/local/open-ui/open-ui -v
    ;;
  *)
    echo "OpenUI management script is missing. Reinstall with install.sh." >&2
    exit 1
    ;;
esac
EOF
        chmod 0755 "${OPENUI_CLI}"
    fi

    chmod 0755 "${OPENUI_INSTALL_DIR}/open-ui"
    find "${OPENUI_INSTALL_DIR}/bin" -type f -name 'xray-*' -exec chmod 0755 {} \; 2>/dev/null || true
    rm -rf "${tmpdir}"
}

install_service() {
    if [[ "${release}" == "alpine" ]]; then
        if [[ -f "${OPENUI_INSTALL_DIR}/open-ui.rc" ]]; then
            install -m 0755 "${OPENUI_INSTALL_DIR}/open-ui.rc" "/etc/init.d/${OPENUI_SERVICE_NAME}"
        else
            echo -e "${red}Fatal error:${plain} open-ui.rc not found in release archive." >&2
            exit 1
        fi
        rc-update add "${OPENUI_SERVICE_NAME}" default
        rc-service "${OPENUI_SERVICE_NAME}" start
        return
    fi

    mkdir -p "$(dirname "${OPENUI_ENV_FILE}")"
    cat > "${OPENUI_ENV_FILE}" <<EOF
OPENUI_DB_FOLDER=${OPENUI_DATA_DIR}
OPENUI_LOG_FOLDER=${OPENUI_LOG_DIR}
OPENUI_BIN_FOLDER=${OPENUI_INSTALL_DIR}/bin
XRAY_VMESS_AEAD_FORCED=false
EOF

    local service_source=""
    case "${release}" in
        arch | manjaro | parch) service_source="${OPENUI_INSTALL_DIR}/open-ui.service.arch" ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol | centos) service_source="${OPENUI_INSTALL_DIR}/open-ui.service.rhel" ;;
        *) service_source="${OPENUI_INSTALL_DIR}/open-ui.service.debian" ;;
    esac

    if [[ ! -f "${service_source}" ]]; then
        echo -e "${red}Fatal error:${plain} $(basename "${service_source}") not found in release archive." >&2
        exit 1
    fi

    install -m 0644 "${service_source}" "${OPENUI_SERVICE_DIR}/${OPENUI_SERVICE_NAME}.service"
    systemctl daemon-reload
    systemctl enable "${OPENUI_SERVICE_NAME}"
    systemctl start "${OPENUI_SERVICE_NAME}"
}

configure_initial_security() {
    local settings
    if ! settings="$("${OPENUI_INSTALL_DIR}/open-ui" setting -show true 2>/dev/null)"; then
        echo -e "${yellow}Warning:${plain} Could not read OpenUI settings for initial security setup." >&2
        return 0
    fi

    local has_default_credential existing_webbasepath existing_port existing_cert
    has_default_credential="$(echo "${settings}" | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}' || true)"
    existing_webbasepath="$(echo "${settings}" | grep -Eo 'webBasePath: .+' | awk '{print $2}' | sed 's#^/##' || true)"
    existing_port="$(echo "${settings}" | grep -Eo 'port: .+' | awk '{print $2}' || true)"
    existing_cert="$("${OPENUI_INSTALL_DIR}/open-ui" setting -getCert true 2>/dev/null | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]' || true)"

    local username="" password="" webbasepath="${existing_webbasepath}" panel_port="${existing_port}"
    if [[ "${has_default_credential}" == "true" ]]; then
        username="$(gen_random_string 10)"
        password="$(gen_random_string 18)"
    fi
    if [[ ${#webbasepath} -lt 4 ]]; then
        webbasepath="$(gen_random_string 18)"
    fi
    if [[ -z "${panel_port}" || "${panel_port}" == "2053" ]] || is_port_in_use "${panel_port}"; then
        panel_port="$(pick_random_panel_port)"
    fi

    if [[ -n "${username}" || "${webbasepath}" != "${existing_webbasepath}" || "${panel_port}" != "${existing_port}" ]]; then
        local setting_args=(-port "${panel_port}" -webBasePath "${webbasepath}")
        if [[ -n "${username}" ]]; then
            setting_args=(-username "${username}" -password "${password}" "${setting_args[@]}")
        fi
        "${OPENUI_INSTALL_DIR}/open-ui" setting "${setting_args[@]}" >/dev/null
    fi

    local scheme="http" host
    host="$(detect_server_ipv4 || true)"
    if [[ -n "${existing_cert}" ]]; then
        scheme="https"
        host="${host:-127.0.0.1}"
    elif [[ -n "${host}" ]]; then
        if setup_ip_certificate "${host}"; then
            scheme="https"
        else
            echo -e "${yellow}Warning:${plain} IP certificate setup failed or port 80 is unavailable; OpenUI remains HTTP until SSL is configured." >&2
        fi
    else
        host="127.0.0.1"
        echo -e "${yellow}Warning:${plain} Could not detect public IPv4; skipped automatic IP certificate setup." >&2
    fi

    if [[ "${release}" == "alpine" ]]; then
        rc-service "${OPENUI_SERVICE_NAME}" restart >/dev/null 2>&1 || true
    else
        systemctl restart "${OPENUI_SERVICE_NAME}" >/dev/null 2>&1 || true
    fi

    echo ""
    echo -e "${green}OpenUI panel initialized.${plain}"
    if [[ -n "${username}" ]]; then
        echo -e "${green}Username: ${username}${plain}"
        echo -e "${green}Password: ${password}${plain}"
    else
        echo -e "${green}Username/password: existing credentials preserved${plain}"
    fi
    echo -e "${green}Port: ${panel_port}${plain}"
    echo -e "${green}WebBasePath: ${webbasepath}${plain}"
    echo -e "${green}Access URL: ${scheme}://${host}:${panel_port}/${webbasepath}${plain}"
}

setup_ip_certificate() {
    local server_ip="$1"
    local cert_dir="/root/cert/ip"

    if is_port_in_use 80; then
        echo -e "${yellow}Port 80 is already in use; skipping automatic IP certificate.${plain}" >&2
        return 1
    fi
    if ! install_acme; then
        return 1
    fi

    mkdir -p "${cert_dir}"
    "${HOME}/.acme.sh/acme.sh" --set-default-ca --server letsencrypt --force >/dev/null 2>&1 || true
    if ! "${HOME}/.acme.sh/acme.sh" --issue \
        -d "${server_ip}" \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport 80 \
        --force; then
        rm -rf "${HOME}/.acme.sh/${server_ip}" "${cert_dir}" 2>/dev/null || true
        return 1
    fi

    "${HOME}/.acme.sh/acme.sh" --installcert -d "${server_ip}" \
        --key-file "${cert_dir}/privkey.pem" \
        --fullchain-file "${cert_dir}/fullchain.pem" \
        --reloadcmd "systemctl restart ${OPENUI_SERVICE_NAME} 2>/dev/null || rc-service ${OPENUI_SERVICE_NAME} restart 2>/dev/null || true" >/dev/null 2>&1 || true

    if [[ ! -f "${cert_dir}/fullchain.pem" || ! -f "${cert_dir}/privkey.pem" ]]; then
        rm -rf "${HOME}/.acme.sh/${server_ip}" "${cert_dir}" 2>/dev/null || true
        return 1
    fi

    chmod 600 "${cert_dir}/privkey.pem" 2>/dev/null || true
    chmod 644 "${cert_dir}/fullchain.pem" 2>/dev/null || true
    "${HOME}/.acme.sh/acme.sh" --upgrade --auto-upgrade >/dev/null 2>&1 || true
    "${OPENUI_INSTALL_DIR}/open-ui" cert -webCert "${cert_dir}/fullchain.pem" -webCertKey "${cert_dir}/privkey.pem" >/dev/null
}

main() {
    echo -e "${green}Installing OpenUI...${plain}"
    echo "Repository: ${OPENUI_REPO}"
    echo "Detected OS: ${release}"
    echo "Detected arch: $(arch)"

    install_base

    local version="${OPENUI_VERSION}"
    if [[ "${version}" == "latest" ]]; then
        version="$(latest_version)"
        if [[ -z "${version}" ]]; then
            echo -e "${red}Fatal error:${plain} Failed to resolve latest OpenUI release." >&2
            exit 1
        fi
    fi

    local archive
    archive="$(download_release "${version}")"
    stop_existing
    install_files "${archive}"
    install_service
    configure_initial_security
    rm -f "${archive}"

    echo -e "${green}OpenUI ${version} installation finished.${plain}"
    echo "CLI: ${OPENUI_CLI}"
    echo "Install dir: ${OPENUI_INSTALL_DIR}"
    echo "Data dir: ${OPENUI_DATA_DIR}"
    echo "Log dir: ${OPENUI_LOG_DIR}"
    echo "Service: ${OPENUI_SERVICE_NAME}"
}

main "$@"
