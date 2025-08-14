# Nomad + Consul + Vault Dev Stack (macOS/Linux)

A single-file script to launch a local **Nomad**, **Consul**, and **Vault** dev stack with sensible defaults, version prompts, and robust health checks. Designed to be macOS-friendly (Bash 3.2 compatible) and also works on Linux (amd64/arm64).

> **Script:** `ncv-dev.sh`

---

## ✨ Features

- Choose versions via **flags** or **env vars**; prompts interactively if unset
- `--check` preflight validation of release URLs
- `--stream-logs` to see startup progress live
- `--no-example` to skip the sample Nomad job
- Finite health waits with log tails (no silent hangs)
- Vault configured with `api_addr` / `cluster_addr` to avoid HA standby issues
- Cleanup that kills child processes and removes the temp dir reliably

---

## ⚙️ Requirements

- macOS or Linux (x86_64 / arm64)
- `curl` and `unzip` available in `PATH`
  - Linux: `sudo apt-get install -y curl unzip` (Debian/Ubuntu) or `sudo yum install -y curl unzip` (RHEL/CentOS)
- Internet access to download HashiCorp releases

> The script downloads **Nomad**, **Consul**, and **Vault** locally into a temporary directory and does not alter system installs.

---

## 🚀 Quick Start

```bash
chmod +x ./ncv-dev.sh
./ncv-dev.sh            # prompts for versions
# or:
./ncv-dev.sh --no-example
```

---

## 🔧 Flags

```text
--nomad X.Y.Z        Pin Nomad version
--consul X.Y.Z       Pin Consul version
--vault X.Y.Z        Pin Vault version
--non-interactive    Fail if any version is missing (no prompts)
--check              Validate release URLs before downloading
--stream-logs        Stream Consul/Vault/Nomad logs during waits
--no-example         Skip creating/running the example Nomad job
-h, --help           Show usage
```

### Environment variables

- `NOMAD_VERSION` (default `1.10.0`)
- `CONSUL_VERSION` (default `1.21.0`)
- `VAULT_VERSION` (default `1.19.3`)
- `HEALTH_TIMEOUT` (seconds, default `90`)

---

## 🧠 What the script does

1. Downloads and unpacks Nomad/Consul/Vault for your OS/arch
2. Starts **Consul** dev agent with ACLs and bootstraps a token
3. Starts **Vault** on Consul storage; initializes, unseals, sets `api_addr/cluster_addr`
4. Starts **Nomad** with ACLs + Vault Workload Identity; bootstraps a token
5. *(Optional)* Runs an example job and tails logs
6. Prints tokens and temp dir; cleans up on exit

> **Security:** Tokens are printed to your terminal. Treat them as secrets; don’t commit them.

---

## 🧪 Use-Case Demos

### Environment setup (new terminal)

```bash
export NOMAD_ADDR="http://127.0.0.1:4646"
export VAULT_ADDR="http://127.0.0.1:8200"
export NOMAD_TOKEN="<Nomad Bootstrap Token>"
export CONSUL_HTTP_TOKEN="<Consul Bootstrap Token>"
export VAULT_TOKEN="<Vault Root Token>"
```

> Demos use the `raw_exec` driver, enabled in Nomad dev.

### 1) Web service with Consul service checks

```bash
nomad job run demos/web.nomad

# Validate via Consul health API
curl -s "http://127.0.0.1:8500/v1/health/service/web?passing" \
  -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" | grep '"Service":'
```

#### 🚦 Rolling update (v1 → v2)

Edit `demos/web.nomad` — change:

```diff
- args    = ["-c", "echo v1 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
+ args    = ["-c", "echo v2 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
```

Re-run:
```bash
nomad job plan demos/web.nomad
nomad job run demos/web.nomad
```

Verify:
```bash
PORT=$(curl -s "http://127.0.0.1:8500/v1/health/service/web?passing" \
  -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" | jq -r '.[0].Service.Port')
curl -s "http://127.0.0.1:${PORT}/"
# -> v2
```

### 2) Consul KV → env templating with restart-on-change

Seed and run:
```bash
curl -s -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data 'Hello Nomad!' http://127.0.0.1:8500/v1/kv/app/message

nomad job run demos/kv-watcher.nomad
```

#### Validation
```bash
# KV value
curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  http://127.0.0.1:8500/v1/kv/app/message?raw

# Running alloc
ALLOC=$(nomad job allocs -json kv-watcher \
  | jq -r 'map(select(.ClientStatus=="running")) | .[0].ID'); echo "$ALLOC"

# Restart count from task events
nomad alloc status -json "$ALLOC" \
  | jq '[.TaskStates["watcher"].Events[] | select(.Type=="Restarting")] | length'

# Recent restart-related events
nomad alloc status -json "$ALLOC" \
  | jq -r '.TaskStates["watcher"].Events[]
           | select(.Type=="Restart Signaled" or .Type=="Restarting")
           | "\(.Time)  \(.Type)  \(.Message)"' | tail -n 10

# Rendered env inside the alloc
nomad alloc fs cat "$ALLOC" local/env
```

### 3) Vault Workload Identity: token injection
```bash
nomad job run demos/vault-token.nomad
nomad alloc logs -stderr -job vault-token
```

### 4) Periodic batch (cron) job
```bash
nomad job run demos/cron-hello.nomad
nomad job history cron-hello
```

### Cleanup
```bash
nomad job stop -purge web kv-watcher vault-token cron-hello
```

---

## 📦 Layout
```
.
├── README.md
├── ncv-dev.sh
└── demos/
    ├── web.nomad
    ├── kv-watcher.nomad
    ├── vault-token.nomad
    └── cron-hello.nomad
```

---

## 🧰 Dev & CI Tips
```bash
brew install shellcheck
shellcheck ncv-dev.sh
```

GitHub Actions:
```yaml
name: shellcheck
on: [push, pull_request]
jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install ShellCheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: Lint
        run: shellcheck ncv-dev.sh
```
