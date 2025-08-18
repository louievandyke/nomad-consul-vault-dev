#!/usr/bin/env bash
# ncv-dev.sh — macOS-friendly dev stack launcher for Nomad + Consul + Vault
# Features:
# - Choose versions via env vars or flags; prompts if missing
# - --non-interactive to fail when versions are unset
# - --check to validate release URLs exist before download
# - --no-example to skip running the example Nomad job
# - Finite health waits with log tail dumps (no silent hangs)
# - Vault configured with api_addr/cluster_addr to avoid HA standby
# - Works with macOS's Bash 3.2 (no ${var^}, ${var,,})

set -euo pipefail

# Remember where we started so cleanup can safely cd back
ORIG_PWD="$(pwd)"

DEFAULT_NOMAD_VERSION="${NOMAD_VERSION:-1.10.0}"
DEFAULT_CONSUL_VERSION="${CONSUL_VERSION:-1.21.0}"
DEFAULT_VAULT_VERSION="${VAULT_VERSION:-1.19.3}"

NON_INTERACTIVE=false
RUN_CHECK=false
STREAM_LOGS=false
NO_EXAMPLE=false
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-90}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--nomad X.Y.Z] [--consul X.Y.Z] [--vault X.Y.Z] [--non-interactive] [--check] [--stream-logs] [--no-example] [--env-out PATH]

Flags:
  --non-interactive  Fail if any required version is unset (do not prompt)
  --check            Validate that release URLs exist before downloading
  --stream-logs      Stream logs while waiting for health checks
  --no-example       Skip running the example Nomad job
  --env-out PATH     Also write a copy of stack.env to PATH (not cleaned up)
  -h, --help         Show this help and exit
USAGE
}

is_semver() { [[ "$1" =~ ^[0-9]+(\.[0-9]+){2}(-[A-Za-z0-9\.\-]+)?$ ]]; }
ask_version() { local name="$1" default="$2" outvar="$3" input=""; read -r -p "Enter ${name} version [default: ${default}]: " input || true; input="${input:-$default}"; if ! is_semver "$input"; then echo "Invalid ${name} version: \"$input\"."; exit 1; fi; printf -v "$outvar" '%s' "$input"; }
require_or_prompt() { local name="$1" current="$2" default="$3" outvar="$4"; local name_lc; name_lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"; if [[ -z "$current" ]]; then if $NON_INTERACTIVE; then echo "Missing required ${name} version and --non-interactive specified. Set via env or --$name_lc."; exit 1; else ask_version "$name" "$default" "$outvar"; return; fi; fi; if ! is_semver "$current"; then echo "Invalid ${name} version: $current"; exit 1; fi; printf -v "$outvar" '%s' "$current"; }
pause() { read -r -p $'\n⌛️ Press any key to continue...' -n1 -s || true; echo; }
log_head() { local f="$1"; local n="${2:-100}"; [[ -f "$f" ]] && { echo -e "\n===== tail -n $n $f ====="; tail -n "$n" "$f"; } || true; }
wait_for_url() { local url="$1" name="$2"; local timeout="${3:-$HEALTH_TIMEOUT}"; local i=0; echo -n "📝 Waiting for ${name} to start up..."; while ! curl -s "$url" >/dev/null; do echo -n .; sleep 1; i=$((i+1)); if $STREAM_LOGS; then case "$name" in Nomad) tail -n 2 nomad.log 2>/dev/null || true;; Vault) tail -n 2 vault.log 2>/dev/null || true;; Consul) tail -n 2 consul.log 2>/dev/null || true;; esac; fi; if [[ $i -ge $timeout ]]; then echo -e "\n❌ Timed out waiting for ${name}."; log_head consul.log 200; log_head vault.log 200; log_head nomad.log 200; exit 1; fi; done; echo; }
check_command_success() { if [[ $? -ne 0 ]]; then echo "Error occurred"; tail -n 30 nomad.log 2>/dev/null || true; exit 1; fi; }
cleanup() {
  set +e
  trap - EXIT INT TERM
  echo -e "
 Cleaning up..."

  # 1) Nuke all child processes fast (don’t rely on CLIs)
  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -P $$ >/dev/null 2>&1 || true
    sleep 1
    pkill -KILL -P $$ >/dev/null 2>&1 || true
  fi
  for pid in "${nomadPID:-}" "${vaultPID:-}" "${consulPID:-}"; do
    [[ -n "$pid" ]] && kill -TERM "$pid" >/dev/null 2>&1 || true
  done
  sleep 1
  for pid in "${nomadPID:-}" "${vaultPID:-}" "${consulPID:-}"; do
    [[ -n "$pid" ]] && kill -KILL "$pid" >/dev/null 2>&1 || true
  done

  # 2) Leave temp dir if we’re inside it
  if [[ -n "${TMPDIR:-}" && -n "${PWD:-}" && "$PWD" == "$TMPDIR"* ]]; then
    cd "$ORIG_PWD" >/dev/null 2>&1 || cd /
  fi

  # 3) Rename then delete temp dir in the background to avoid hangs
  if [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]]; then
    DELDIR="${TMPDIR}.deleting.$$"
    mv "$TMPDIR" "$DELDIR" >/dev/null 2>&1 || DELDIR="$TMPDIR"
    (rm -rf "$DELDIR" >/dev/null 2>&1 &)  # async delete
  fi
  echo "Done."
}
trap cleanup EXIT INT TERM

ENV_EXPORT_PATH=""
NOMAD_VERSION="${NOMAD_VERSION:-}"; CONSUL_VERSION="${CONSUL_VERSION:-}"; VAULT_VERSION="${VAULT_VERSION:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --nomad) NOMAD_VERSION="$2"; shift 2 ;;
    --consul) CONSUL_VERSION="$2"; shift 2 ;;
    --vault) VAULT_VERSION="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --check) RUN_CHECK=true; shift ;;
    --stream-logs) STREAM_LOGS=true; shift ;;
    --no-example) NO_EXAMPLE=true; shift ;;
    --env-out) ENV_EXPORT_PATH="$2"; shift 2 ;;   # <— new
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# If a relative path was given, anchor it to where you launched the script
if [[ -n "$ENV_EXPORT_PATH" && "$ENV_EXPORT_PATH" != /* ]]; then
  ENV_EXPORT_PATH="$ORIG_PWD/$ENV_EXPORT_PATH"
fi



require_or_prompt "Nomad" "$NOMAD_VERSION" "$DEFAULT_NOMAD_VERSION" NOMAD_VERSION
require_or_prompt "Consul" "$CONSUL_VERSION" "$DEFAULT_CONSUL_VERSION" CONSUL_VERSION
require_or_prompt "Vault" "$VAULT_VERSION" "$DEFAULT_VAULT_VERSION" VAULT_VERSION

echo "Versions:"; echo "  Nomad : $NOMAD_VERSION"; echo "  Consul: $CONSUL_VERSION"; echo "  Vault : $VAULT_VERSION"

myOS="$(uname -s | tr '[:upper:]' '[:lower:]')"; myUnameArch="$(uname -m)"; case "$myUnameArch" in x86_64) myArch="amd64" ;; aarch64|arm64) myArch="arm64" ;; *) echo "Unsupported arch"; exit 1 ;; esac
hc_zip_url() { echo "https://releases.hashicorp.com/$1/$2/$1_$2_${myOS}_${myArch}.zip"; }
check_url() { curl -sIf "$1" >/dev/null || { echo "URL not found: $1"; return 1; }; }
if $RUN_CHECK; then check_url "$(hc_zip_url nomad "$NOMAD_VERSION")"; check_url "$(hc_zip_url consul "$CONSUL_VERSION")"; check_url "$(hc_zip_url vault "$VAULT_VERSION")"; echo "All URLs good."; fi

# Choose a non-symlink temp root and canonicalize the path
TMPROOT="/tmp"
if [[ "$myOS" == "darwin" ]]; then
  TMPROOT="/private/tmp"
fi

TMPDIR="$(mktemp -d "${TMPROOT}/$(basename "$0").XXXXXX")"
cd "$TMPDIR"
TMPDIR="$(pwd -P)"   # canonical, no symlinks
echo "📂 Using $TMPDIR..."

fetch_hc() { local name="$1" ver="$2"; echo "Fetching ${name} v${ver}..."; curl -sSL "$(hc_zip_url "$name" "$ver")" -o "${name}.zip"; unzip -o "${name}.zip" >/dev/null; rm -f "${name}.zip"; chmod +x "$name"; }
fetch_hc nomad "$NOMAD_VERSION"; fetch_hc consul "$CONSUL_VERSION"; fetch_hc vault "$VAULT_VERSION"

unset NOMAD_ADDR NOMAD_TOKEN CONSUL_HTTP_TOKEN VAULT_TOKEN

echo "🚦 Starting Consul..."; cat > consul.hcl <<EOF
datacenter = "dc1"
data_dir   = "$TMPDIR/consul-data"

acl {
  enabled                  = true
  default_policy           = "deny"
  enable_token_persistence = true
}
EOF
./consul agent -dev -config-file=consul.hcl > consul.log 2>&1 & consulPID=$!; wait_for_url "http://127.0.0.1:8500/v1/status/leader" "Consul"; CONSUL_TOKEN="$(./consul acl bootstrap | awk '/SecretID:/ {print $2}')"; export CONSUL_HTTP_TOKEN="$CONSUL_TOKEN"

echo "Starting Vault..."; cat > vault-config.hcl <<EOF
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}
listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}
api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
EOF
./vault server -config=vault-config.hcl > vault.log 2>&1 & vaultPID=$!; wait_for_url "http://127.0.0.1:8200/v1/sys/health" "Vault"; export VAULT_ADDR='http://127.0.0.1:8200'; ./vault operator init -key-shares=1 -key-threshold=1 > vault-init.log 2>&1; VAULT_UNSEAL_KEY="$(awk '/Unseal Key 1:/ {print $4}' vault-init.log)"; VAULT_TOKEN="$(awk '/Initial Root Token:/ {print $4}' vault-init.log)"; export VAULT_TOKEN; ./vault operator unseal "$VAULT_UNSEAL_KEY"; until ./vault status | grep -q 'Sealed *false'; do sleep 1; done

export NOMAD_ADDR="http://127.0.0.1:4646"; cat > nomad.hcl <<EOF
log_level = "DEBUG"
data_dir  = "${TMPDIR}/data"

server {
  enabled          = true
  bootstrap_expect = 1
}

client {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
  token   = "${CONSUL_HTTP_TOKEN}"
}

vault {
  enabled          = true
  address          = "http://127.0.0.1:8200"
  create_from_role = "nomad-workloads"
  task_token_ttl   = "1h"
  workload_identity {
    enabled = true
  }
}

acl {
  enabled = true
}
EOF
./nomad agent -dev -config=nomad.hcl > nomad.log 2>&1 & nomadPID=$!; wait_for_url "http://127.0.0.1:4646/v1/agent/health" "Nomad"; ./nomad setup vault -y || true; NOMAD_TOKEN="$(./nomad acl bootstrap | awk '/Secret ID/ {print $NF}')"; export NOMAD_TOKEN

if ! $NO_EXAMPLE; then
  cat > example.nomad <<'EOF'
job "example" {
  datacenters = ["dc1"]

  group "group" {
    task "test" {
      driver = "raw_exec"

      config {
        command = "bash"
        args    = ["-c", "while true; do date; sleep 5; done"]
      }

      template {
        data = <<EOH
VAULT_TOKEN={{ with secret "auth/token/lookup-self" }}{{ .Data.id }}{{ end }}
EOH
        destination = "secrets/token.env"
        env         = true
      }
    }
  }
}
EOF
  ./nomad job run example.nomad || true; ./nomad status example || true; allocID="$(./nomad alloc status -t '{{range .}}{{if eq .JobID "example"}}{{printf "%s\n" .ID}}{{end}}{{end}}' 2>/dev/null | head -n1 || true)"; if [[ -n "$allocID" ]]; then echo "==> Tailing logs for alloc $allocID (task: test)"; ./nomad alloc logs "$allocID" test 2>/dev/null || true; fi
fi

SUMMARY_FILE="$TMPDIR/stack-info.txt"
ENV_FILE="$TMPDIR/stack.env"

{
  echo
  echo "Go have fun with Nomad, Consul, and Vault!"
  echo "===================="
  echo "Directory: $TMPDIR"
  echo "Vault Root Token: $VAULT_TOKEN"
  echo "Vault Unseal Key: $VAULT_UNSEAL_KEY"
  echo "Consul Bootstrap Token: $CONSUL_HTTP_TOKEN"
  echo "Nomad Bootstrap Token: $NOMAD_TOKEN"
} | tee "$SUMMARY_FILE"

cat > "$ENV_FILE" <<EOF
export NOMAD_ADDR="http://127.0.0.1:4646"
export VAULT_ADDR="http://127.0.0.1:8200"
export NOMAD_TOKEN="$NOMAD_TOKEN"
export CONSUL_HTTP_TOKEN="$CONSUL_HTTP_TOKEN"
export VAULT_TOKEN="$VAULT_TOKEN"
EOF

echo "Wrote summary to: $SUMMARY_FILE (auto-removed on cleanup)"
echo "Wrote env exports to: $ENV_FILE (auto-removed on cleanup)"

if [[ -n "$ENV_EXPORT_PATH" ]]; then
  mkdir -p "$(dirname "$ENV_EXPORT_PATH")" 2>/dev/null || true
  cp -f "$ENV_FILE" "$ENV_EXPORT_PATH"
  echo "Persisted env exports to: $ENV_EXPORT_PATH (safe to source later)"
fi

pause
