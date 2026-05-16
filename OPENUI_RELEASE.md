# OpenUI Release and Installation

OpenUI release assets are built by `.github/workflows/release.yml` when a `v*.*.*`
tag is pushed.

## Release assets

- `open-ui-linux-amd64.tar.gz`

Only Linux amd64 is built and published.

Linux archives contain an `open-ui/` directory with:

- `open-ui` panel binary
- `open-ui.sh` CLI helper
- `open-ui.service.*` systemd unit files
- `open-ui.rc` OpenRC unit file
- `bin/xray-*` and geo data files

## One-line install

```bash
bash <(curl -Ls https://raw.githubusercontent.com/helloandworlder/OpenUI/main/install.sh)
```

Install a specific tag:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/helloandworlder/OpenUI/main/install.sh) v3.0.5
```

If the GitHub repository name changes, override it without editing the script:

```bash
OPENUI_REPO=owner/repo bash <(curl -Ls https://raw.githubusercontent.com/owner/repo/main/install.sh)
```

## Default Linux paths

- Install dir: `/usr/local/open-ui`
- CLI: `/usr/bin/open-ui`
- Service: `/etc/systemd/system/open-ui.service`
- Environment file: `/etc/default/open-ui`
- Data dir: `/etc/open-ui`
- Database: `/etc/open-ui/open-ui.db`
- Log dir: `/var/log/open-ui`
- Xray bin dir: `/usr/local/open-ui/bin`

OpenUI uses `OPENUI_*` environment variables by default. Legacy `XUI_*`
variables are accepted only as compatibility fallback.

## Local verification

```bash
go test ./config
bash scripts/verify-openui-release.sh
```
