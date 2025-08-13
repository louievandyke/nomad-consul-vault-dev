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
# 1) Make it executable
chmod +x ./ncv-dev.sh

# 2) Run interactively (you'll be prompted for versions)
./ncv-dev.sh
```

When finished, the script prints tokens and the temp working directory and then cleans up processes and files.

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

You can also provide versions via env vars (flags take precedence):

- `NOMAD_VERSION` (default `1.10.0`)
- `CONSUL_VERSION` (default `1.21.0`)
- `VAULT_VERSION` (default `1.19.3`)

Control health check timeout via:

- `HEALTH_TIMEOUT` (seconds, default `90`)

Examples:

```bash
# Non-interactive with explicit versions and URL validation
./ncv-dev.sh --non-interactive --check \
  --nomad 1.10.0 --consul 1.21.0 --vault 1.19.3

# Stream logs during startup
./ncv-dev.sh --stream-logs

# Skip the example job
./ncv-dev.sh --no-example

# Use environment variables instead of flags
NOMAD_VERSION=1.10.0 CONSUL_VERSION=1.21.0 VAULT_VERSION=1.19.3 ./ncv-dev.sh
```

---

## 🧠 What the script does

1. Detects OS/arch and downloads HashiCorp zip releases for Nomad, Consul, and Vault.
2. Starts a **Consul dev agent** with ACLs enabled and bootstraps a management token.
3. Starts **Vault** backed by Consul storage; initializes, unseals, and sets `api_addr/cluster_addr`.
4. Starts **Nomad** with ACLs and Vault Workload Identity integration; bootstraps a management token.
5. *(Optional)* Runs a simple **example** job using the `raw_exec` driver and tails its logs.
6. Prints useful tokens (Vault root/unseal, Consul bootstrap, Nomad bootstrap) and the temp directory path.
7. On exit, force-stops processes and removes the temp directory.

> **Security note:** Tokens are printed to your terminal for convenience. Treat them as secrets and **do not commit** them anywhere.

---

## 🧪 Example Output

- Nomad Web UI: `http://127.0.0.1:4646/ui`
- Example job: `Jobs → example` (if not skipped with `--no-example`)

The script tail-dumps `consul.log`, `vault.log`, and `nomad.log` if a service fails to become healthy within the timeout.

---

## 🐞 Troubleshooting

- **Port conflicts**: Ensure nothing else is listening on `:8500` (Consul), `:8200` (Vault), or `:4646` (Nomad).  
- **HCL parse errors**: The script writes multi-line HCL without semicolons. If you edit configs, avoid `;` in HCL2.  
- **Cleanup hangs**: The script now renames the temp dir and deletes it asynchronously to avoid Finder/indexing blocks.  
- **Vault standby/HA**: The script sets `api_addr` and `cluster_addr` to keep Vault responsive for local dev use.

---

## 📦 Repository Layout

```
.
├── README.md
└── ncv-dev.sh
```

Optional: add a simple `.gitignore`

```
.DS_Store
*.log
```

---

## 🧰 Dev & CI Tips

Run basic linting with ShellCheck (locally):

```bash
brew install shellcheck  # macOS (or use your package manager)
shellcheck ncv-dev.sh
```

GitHub Actions workflow (optional):

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

---

## 🔒 Disclaimer

This is intended for **local development** only. It prints sensitive tokens to your terminal and runs Vault/Consul/Nomad in dev modes. Do not use these defaults in production.

---

## 📜 License

MIT (or choose your preferred license).
