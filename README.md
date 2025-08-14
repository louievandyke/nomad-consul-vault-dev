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

### 🚦 Rolling update (v1 → v2)

The `web` job serves a tiny page via Python’s HTTP server. To demo a rolling update, we’ll change the page contents from **v1** to **v2** and resubmit the job.

1) **Edit** `demos/web.nomad` — change the task’s command from `v1` to `v2`:

```diff
 task "server" {
   driver = "raw_exec"
   config {
     command = "bash"
-    args    = ["-c", "echo v1 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
+    args    = ["-c", "echo v2 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
   }
   resources {
     cpu    = 100
     memory = 64
   }
 }
```

2) **Plan** (optional) and **run** the update:

```bash
nomad job plan demos/web.nomad
nomad job run demos/web.nomad
```

3) **Watch** the deployment roll (one new alloc becomes healthy, then replaces the old one):

```bash
# CLI
nomad job deployment watch -job web

# or in the UI: http://127.0.0.1:4646/ui/jobs/web
```

4) **Verify** the new version is live:

```bash
PORT=$(curl -s "http://127.0.0.1:8500/v1/health/service/web?passing"   -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" | jq -r '.[0].Service.Port'])

curl -s "http://127.0.0.1:${PORT}/"
# should return: v2
```

> Notes  
> • The job uses a **dynamic port**; Nomad exposes it via `${NOMAD_PORT_http}`.  
> • If `python3` isn’t available on your host, swap the command for another simple server, e.g.:  
>   `ruby -run -e httpd . -p ${NOMAD_PORT_http}` or `busybox httpd -f -p ${NOMAD_PORT_http}`.  
> • With `count = 1` and the `update` stanza, Nomad still performs a rolling replacement (blue/green-style) to keep the service healthy.


### 2) Consul KV → env templating with restart-on-change

Seed KV and run:

```bash
curl -s -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data 'Hello Nomad!' http://127.0.0.1:8500/v1/kv/app/message

nomad job run demos/kv-watcher.nomad
```

#### Validation

```bash
# 1) Confirm the KV value you wrote (raw)
curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  http://127.0.0.1:8500/v1/kv/app/message?raw

# 2) Get the running allocation ID for the job
ALLOC=$(nomad job allocs -json kv-watcher \
  | jq -r 'map(select(.ClientStatus=="running")) | .[0].ID'); echo "$ALLOC"

# 3) Restart count derived from task events (Nomad 1.10+)
nomad alloc status -json "$ALLOC" \
  | jq '[.TaskStates["watcher"].Events[] | select(.Type=="Restarting")] | length'

# 4) Show recent restart-related events
nomad alloc status -json "$ALLOC" \
  | jq -r '.TaskStates["watcher"].Events[]
           | select(.Type=="Restart Signaled" or .Type=="Restarting")
           | "\(.Time)  \(.Type)  \(.Message)"' | tail -n 10

# 5) Inspect the rendered env file inside the allocation
nomad alloc fs cat "$ALLOC" local/env
```


**Watch live (optional):**

```bash
# Terminal A: stream task logs
ALLOC=$(nomad job allocs -json kv-watcher | jq -r '.[0].ID')
nomad alloc logs -f "$ALLOC" watcher

# Terminal B: update the KV key; Terminal A will pause/restart and print the new MESSAGE
curl -s -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data 'Hello for the third time 🚀' \
  http://127.0.0.1:8500/v1/kv/app/message
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
