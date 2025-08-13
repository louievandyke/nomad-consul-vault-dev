# Demos

---

## 🧪 Use-Case Demos

### Environment setup (new terminal)

Export addresses and tokens printed by the launcher script:

```bash
export NOMAD_ADDR="http://127.0.0.1:4646"
export VAULT_ADDR="http://127.0.0.1:8200"
export NOMAD_TOKEN="<Nomad Bootstrap Token>"
export CONSUL_HTTP_TOKEN="<Consul Bootstrap Token>"
export VAULT_TOKEN="<Vault Root Token>"   # root for quick demos
```

> The example jobs use the `raw_exec` driver, which is enabled in Nomad dev mode.

### 1) Web service with Consul service checks

```bash
nomad job run demos/web.nomad
# Validate via Consul health API:
curl -s "http://127.0.0.1:8500/v1/health/service/web?passing" \
  -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" | grep '"Service":'
```

Tip: Edit `web.nomad` to change the command (e.g., print `v2`) and `nomad job run demos/web.nomad` to watch a rolling update.

### 2) Consul KV → env templating with restart-on-change

Seed KV and run:

```bash
curl -s -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data 'Hello Nomad!' http://127.0.0.1:8500/v1/kv/app/message

nomad job run demos/kv-watcher.nomad
```

Change the value and watch the task restart with the new env:

```bash
curl -s -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data 'Hello *again* 👋' http://127.0.0.1:8500/v1/kv/app/message
```

### 3) Vault Workload Identity token injection

```bash
nomad job run demos/vault-token.nomad
nomad alloc logs -stderr -job vault-token
```

The task reveals a short-lived Vault token and calls `auth/token/lookup-self` to prove it.

### 4) Periodic batch job (cron)

```bash
nomad job run demos/cron-hello.nomad
nomad job history cron-hello
```

### Cleanup

```bash
nomad job stop -purge web kv-watcher vault-token cron-hello
```
