#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n install.sh
bash -n update.sh
bash -n open-ui.sh
bash -n scripts/verify-openui-release.sh

python3 - <<'PY'
import pathlib
import sys

workflow = pathlib.Path(".github/workflows/release.yml")
text = workflow.read_text()
required = [
    "name: Release OpenUI",
    "  build-linux-amd64:",
    "uses: actions/checkout@v6",
    "uses: actions/setup-go@v6",
    "uses: actions/setup-node@v6",
    "uses: actions/upload-artifact@v7",
    "uses: svenstaro/upload-release-action@v2",
]
missing = [item for item in required if item not in text]
if missing:
    sys.exit("release workflow missing required text: " + ", ".join(missing))
PY

required_files=(
  "open-ui.service.debian"
  "open-ui.service.arch"
  "open-ui.service.rhel"
  "open-ui.rc"
)

for file in "${required_files[@]}"; do
  test -f "${file}"
done

grep -q "open-ui-linux-amd64.tar.gz" .github/workflows/release.yml
grep -q "open-ui/" .github/workflows/release.yml
grep -q "cp open-ui.sh open-ui/open-ui.sh" .github/workflows/release.yml
if grep -q "matrix\\|windows-latest\\|GOARCH=arm\\|GOARCH=386\\|s390x\\|arm64\\|armv7\\|armv6\\|armv5\\|open-ui-windows" .github/workflows/release.yml; then
  echo "release workflow must build linux amd64 only" >&2
  exit 1
fi
grep -q "OPENUI_DB_FOLDER=/etc/open-ui" open-ui.service.debian
grep -q "ExecStart=/usr/local/open-ui/open-ui" open-ui.service.debian
grep -q "OPENUI_REPO" install.sh
grep -q "helloandworlder/OpenUI" install.sh
grep -q "helloandworlder/OpenUI" open-ui.sh
grep -q "show_menu" open-ui.sh
grep -q "open-ui control menu usages" open-ui.sh
grep -q "/usr/local/open-ui" install.sh
grep -q "/etc/open-ui" install.sh
grep -q "/usr/bin/open-ui" install.sh

if grep -Rqi "MHSanaei/3x-ui\|mhsanaei/3x-ui\|3x-ui\|3X-UI\|/usr/local/x-ui\|/usr/bin/x-ui\|/etc/x-ui\|/var/log/x-ui\|x-ui.service\|rc-service x-ui\|systemctl .*x-ui\|journalctl -u x-ui\|x-ui-linux" install.sh update.sh open-ui.sh .github/workflows; then
  echo "OpenUI install, update, menu, and release files must not use upstream 3x-ui paths, services, or assets" >&2
  exit 1
fi

if grep -q '"")' open-ui.sh; then
  echo "open-ui with no arguments must show the management menu, not execute the panel binary" >&2
  exit 1
fi

echo "OpenUI release files verified."
