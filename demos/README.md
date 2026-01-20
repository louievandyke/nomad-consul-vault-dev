# Nomad Demo Tutorials

Hands-on tutorials for learning Nomad, Consul, and Vault integration patterns. Each demo builds on core concepts with progressive exercises.

## Prerequisites

Ensure the stack is running and environment variables are set:

```bash
# In terminal 1: Start the stack
./ncv-dev.sh

# In terminal 2: Load environment variables
source /private/tmp/ncv-dev.sh.*/stack.env

# Verify connectivity
nomad status
consul members
vault status
```

---

## 📚 Tutorial Index

1. [**web.nomad**](#1-webnomad---rolling-deployments--service-discovery) - Rolling deployments, health checks, and service discovery
2. [**kv-watcher.nomad**](#2-kv-watchernomad---dynamic-configuration-with-consul-kv) - Dynamic configuration with Consul KV templating
3. [**vault-token.nomad**](#3-vault-tokennomad---vault-workload-identity) - Vault Workload Identity and secrets injection
4. [**cron-hello.nomad**](#4-cron-hellonomad---periodic-batch-jobs) - Periodic batch jobs (cron-style scheduling)

---

## 1. web.nomad - Rolling Deployments & Service Discovery

**Learning Objectives:**
- Deploy a web service with Consul health checks
- Perform zero-downtime rolling updates
- Scale services horizontally
- Understand auto-revert on deployment failures

### Basic Deployment

Deploy the web service:

```bash
nomad job run demos/web.nomad
```

**Expected output:**
```
==> 2026-01-20T09:30:00-08:00: Monitoring evaluation "abc123"
    Evaluation triggered by job "web"
==> 2026-01-20T09:30:00-08:00: Evaluation within deployment: "def456"
==> 2026-01-20T09:30:01-08:00: Allocation "ghi789" created: node "node1", group "g"
==> 2026-01-20T09:30:06-08:00: Evaluation status changed: "pending" -> "complete"
==> Evaluation "abc123" finished with status "complete"
```

Check the service status:

```bash
nomad job status web
```

View the service in Consul:

```bash
curl -s "http://127.0.0.1:8500/v1/health/service/web?passing" \
  -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" | jq '.[].Service'
```

**Expected output:**
```json
{
  "ID": "web-ghi789-g-server-http",
  "Service": "web",
  "Port": 12345,
  "Address": "127.0.0.1"
}
```

Test the web service:

```bash
# Get the allocation ID
ALLOC=$(nomad job status -short web | grep running | awk '{print $1}' | head -1)

# Get the port
PORT=$(nomad alloc status $ALLOC | grep "http:" | awk '{print $3}' | cut -d'=' -f2)

# Test the endpoint
curl http://127.0.0.1:$PORT
```

**Expected output:**
```
v1
```

### Exercise 1: Rolling Update (v1 → v2)

Edit `demos/web.nomad` and change line 27:

```diff
- args    = ["-c", "echo v1 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
+ args    = ["-c", "echo v2 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
```

Preview the changes:

```bash
nomad job plan demos/web.nomad
```

**Expected output:**
```
+/- Job: "web"
+/- Task Group: "g" (1 create/destroy update)
  +/- Task: "server" (forces create/destroy update)
    +/- Config {
      +/- args[1]: "echo v1 > index.html && python3 -m http.server ${NOMAD_PORT_http}" => "echo v2 > index.html && python3 -m http.server ${NOMAD_PORT_http}"
        }

Scheduler dry-run:
- All tasks successfully allocated.
```

Apply the update:

```bash
nomad job run demos/web.nomad
```

Watch the deployment:

```bash
nomad deployment status $(nomad job status web | grep "Latest Deployment" | awk '{print $4}')
```

Verify the new version:

```bash
curl http://127.0.0.1:$PORT
```

**Expected output:**
```
v2
```

### Exercise 2: Scale to 3 Instances

Edit `demos/web.nomad` line 5:

```diff
- count = 1
+ count = 3
```

Deploy:

```bash
nomad job run demos/web.nomad
```

Verify all instances are healthy:

```bash
nomad job status web
```

**Expected output:**
```
Allocations
ID        Node ID   Task Group  Version  Desired  Status   Created    Modified
abc123    node1     g           2        run      running  10s ago    5s ago
def456    node1     g           2        run      running  10s ago    5s ago
ghi789    node1     g           2        run      running  10s ago    5s ago
```

Check Consul service catalog:

```bash
curl -s "http://127.0.0.1:8500/v1/health/service/web?passing" \
  -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" | jq 'length'
```

**Expected output:**
```
3
```

### Exercise 3: Simulate Failed Deployment

Edit `demos/web.nomad` line 27 to cause a failure:

```diff
- args    = ["-c", "echo v2 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
+ args    = ["-c", "exit 1"]
```

Deploy and watch auto-revert:

```bash
nomad job run demos/web.nomad
nomad deployment status -verbose $(nomad job status web | grep "Latest Deployment" | awk '{print $4}')
```

**Expected behavior:**
- New allocation starts but fails immediately
- Health check never passes
- After `healthy_deadline` (1m), deployment is marked as failed
- `auto_revert = true` triggers rollback to previous version
- Service remains available throughout

### Exercise 4: Canary Deployment

Edit `demos/web.nomad` to add canary deployment:

```diff
  update {
    max_parallel     = 1
+   canary           = 1
    min_healthy_time = "5s"
    healthy_deadline = "1m"
    auto_revert      = true
+   auto_promote     = false
  }
```

Change version to v3:

```diff
- args    = ["-c", "echo v2 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
+ args    = ["-c", "echo v3 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
```

Deploy:

```bash
nomad job run demos/web.nomad
```

Check deployment status:

```bash
DEPLOYMENT=$(nomad job status web | grep "Latest Deployment" | awk '{print $4}')
nomad deployment status $DEPLOYMENT
```

**Expected output:**
```
ID          = abc123
Job ID      = web
Status      = running
Description = Deployment is running but requires manual promotion

Deployed
Task Group  Promoted  Desired  Canaries  Placed  Healthy  Unhealthy
g           false     3        1         1       1        0
```

Test the canary:

```bash
# Find canary allocation
CANARY=$(nomad deployment status $DEPLOYMENT | grep "Canary" | awk '{print $1}')
CANARY_PORT=$(nomad alloc status $CANARY | grep "http:" | awk '{print $3}' | cut -d'=' -f2)

curl http://127.0.0.1:$CANARY_PORT
```

**Expected output:**
```
v3
```

Promote the canary:

```bash
nomad deployment promote $DEPLOYMENT
```

Watch the rolling update complete:

```bash
nomad deployment status $DEPLOYMENT
```

### Cleanup

```bash
nomad job stop -purge web
```

---

## 2. kv-watcher.nomad - Dynamic Configuration with Consul KV

**Learning Objectives:**
- Use Consul KV for dynamic configuration
- Template Consul data into environment variables
- Trigger task restarts on configuration changes
- Understand change detection and propagation

### Basic Deployment

Seed initial configuration in Consul KV:

```bash
curl -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data 'Hello Nomad!' \
  http://127.0.0.1:8500/v1/kv/app/message
```

Deploy the watcher:

```bash
nomad job run demos/kv-watcher.nomad
```

View the logs:

```bash
nomad alloc logs -f -job kv-watcher
```

**Expected output:**
```
Mon Jan 20 09:35:00 PST 2026 MESSAGE=Hello Nomad!
Mon Jan 20 09:35:05 PST 2026 MESSAGE=Hello Nomad!
Mon Jan 20 09:35:10 PST 2026 MESSAGE=Hello Nomad!
```

### Exercise 1: Update Configuration

In a new terminal, update the KV value:

```bash
curl -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data 'Configuration updated!' \
  http://127.0.0.1:8500/v1/kv/app/message
```

Watch the logs (in the first terminal):

**Expected behavior:**
- Nomad detects the KV change within ~5 seconds
- Task is restarted (`change_mode = "restart"`)
- New logs show updated message:

```
Mon Jan 20 09:36:15 PST 2026 MESSAGE=Configuration updated!
Mon Jan 20 09:36:20 PST 2026 MESSAGE=Configuration updated!
```

### Exercise 2: Track Restart Events

Get the allocation ID:

```bash
ALLOC=$(nomad job status -short kv-watcher | grep running | awk '{print $1}')
```

View restart events:

```bash
nomad alloc status -json $ALLOC | jq -r '
  .TaskStates["watcher"].Events[] 
  | select(.Type=="Restart Signaled" or .Type=="Restarting")
  | "\(.Time | strftime("%Y-%m-%d %H:%M:%S"))  \(.Type)  \(.Message)"
' | tail -5
```

**Expected output:**
```
2026-01-20 09:36:15  Restart Signaled  Template with change_mode restart re-rendered
2026-01-20 09:36:15  Restarting  Task restarting in 0s
```

### Exercise 3: Multiple KV Keys

Modify `demos/kv-watcher.nomad` to watch multiple keys:

```diff
  template {
    data = <<EOH
- MESSAGE="{{ key "app/message" }}"
+ MESSAGE="{{ key "app/message" }}"
+ ENVIRONMENT="{{ key "app/environment" }}"
+ VERSION="{{ key "app/version" }}"
  EOH
    destination = "local/env"
    env         = true
    change_mode = "restart"
  }
```

Update the task command:

```diff
- args    = ["-c", "while true; do echo \"$(date) MESSAGE=$MESSAGE\"; sleep 5; done"]
+ args    = ["-c", "while true; do echo \"$(date) ENV=$ENVIRONMENT VER=$VERSION MSG=$MESSAGE\"; sleep 5; done"]
```

Seed the new keys:

```bash
curl -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data 'production' http://127.0.0.1:8500/v1/kv/app/environment

curl -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  --data '1.0.0' http://127.0.0.1:8500/v1/kv/app/version
```

Redeploy:

```bash
nomad job run demos/kv-watcher.nomad
nomad alloc logs -f -job kv-watcher
```

**Expected output:**
```
Mon Jan 20 09:40:00 PST 2026 ENV=production VER=1.0.0 MSG=Configuration updated!
```

### Exercise 4: Change Mode Comparison

Try different `change_mode` values:

**Option 1: Signal (graceful reload)**
```hcl
change_mode = "signal"
change_signal = "SIGHUP"
```

**Option 2: Noop (no action)**
```hcl
change_mode = "noop"
```

**Option 3: Restart (current behavior)**
```hcl
change_mode = "restart"
```

Test each mode and observe the behavior when updating KV values.

### Cleanup

```bash
nomad job stop -purge kv-watcher

# Optional: Clean up KV data
curl -X DELETE -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  http://127.0.0.1:8500/v1/kv/app?recurse
```

---

## 3. vault-token.nomad - Vault Workload Identity

**Learning Objectives:**
- Understand Vault Workload Identity integration
- Access Vault secrets from Nomad tasks
- Use short-lived, automatically rotated tokens
- Template Vault data into task environment

### Basic Deployment

Deploy the job:

```bash
nomad job run demos/vault-token.nomad
```

View the logs:

```bash
nomad alloc logs -stdout -job vault-token
```

**Expected output:**
```
VAULT_TOKEN prefix: hvs.CAES
{
  "request_id": "abc-123",
  "data": {
    "accessor": "xyz789",
    "creation_time": 1737403200,
    "creation_ttl": 3600,
    "display_name": "token",
    "entity_id": "",
    "expire_time": "2026-01-20T10:40:00Z",
    "explicit_max_ttl": 0,
    "id": "hvs.CAESxxx...",
    "issue_time": "2026-01-20T09:40:00Z",
    "meta": null,
    "num_uses": 0,
    "orphan": true,
    "path": "auth/token/create",
    "policies": ["default"],
    "renewable": true,
    "ttl": 3599,
    "type": "service"
  }
}
```

### Understanding the Token

The task receives a Vault token via Workload Identity:

1. **Nomad** requests a token from **Vault** on behalf of the task
2. Token is written to `secrets/token.env` via the template block
3. Token is automatically injected as `VAULT_TOKEN` environment variable
4. Token is short-lived (default TTL: 1 hour) and automatically renewed

### Exercise 1: Access Vault Secrets

Create a secret in Vault:

```bash
vault kv put secret/myapp/config \
  database_url="postgresql://localhost:5432/mydb" \
  api_key="super-secret-key-123"
```

Modify `demos/vault-token.nomad` to read the secret:

```diff
  template {
    data = <<EOH
  VAULT_TOKEN={{ with secret "auth/token/lookup-self" }}{{ .Data.id }}{{ end }}
+ DATABASE_URL={{ with secret "secret/data/myapp/config" }}{{ .Data.data.database_url }}{{ end }}
+ API_KEY={{ with secret "secret/data/myapp/config" }}{{ .Data.data.api_key }}{{ end }}
  EOH
    destination = "secrets/token.env"
    env         = true
  }
```

Update the task command:

```diff
  args = [
    "-c",
    <<-EOT
      echo "VAULT_TOKEN prefix: $(printf '%s' "$VAULT_TOKEN" | cut -c1-8)"
+     echo "DATABASE_URL: $DATABASE_URL"
+     echo "API_KEY: ${API_KEY:0:10}..."
      curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/auth/token/lookup-self" || true
      sleep 60
    EOT
  ]
```

Redeploy and check logs:

```bash
nomad job run demos/vault-token.nomad
nomad alloc logs -stdout -job vault-token
```

**Expected output:**
```
VAULT_TOKEN prefix: hvs.CAES
DATABASE_URL: postgresql://localhost:5432/mydb
API_KEY: super-secr...
```

### Exercise 2: Dynamic Database Credentials

Configure Vault database secrets engine (example with PostgreSQL):

```bash
# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL connection (adjust for your setup)
vault write database/config/mydb \
  plugin_name=postgresql-database-plugin \
  allowed_roles="readonly" \
  connection_url="postgresql://{{username}}:{{password}}@localhost:5432/mydb" \
  username="vault" \
  password="vault-password"

# Create a role
vault write database/roles/readonly \
  db_name=mydb \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

Update the template to fetch dynamic credentials:

```hcl
template {
  data = <<EOH
VAULT_TOKEN={{ with secret "auth/token/lookup-self" }}{{ .Data.id }}{{ end }}
{{ with secret "database/creds/readonly" }}
DB_USERNAME={{ .Data.username }}
DB_PASSWORD={{ .Data.password }}
{{ end }}
EOH
  destination = "secrets/token.env"
  env         = true
}
```

### Exercise 3: Token Renewal

Observe automatic token renewal:

```bash
# Get allocation ID
ALLOC=$(nomad job status -short vault-token | grep running | awk '{print $1}')

# Watch the token TTL decrease and renew
watch -n 5 "nomad alloc exec $ALLOC sh -c 'curl -s -H \"X-Vault-Token: \$VAULT_TOKEN\" \$VAULT_ADDR/v1/auth/token/lookup-self | jq .data.ttl'"
```

**Expected behavior:**
- TTL counts down from 3600 seconds
- When TTL reaches ~1800 seconds (50%), Nomad automatically renews it
- TTL resets back to 3600 seconds

### Cleanup

```bash
nomad job stop -purge vault-token

# Optional: Clean up Vault secrets
vault kv delete secret/myapp/config
```

---

## 4. cron-hello.nomad - Periodic Batch Jobs

**Learning Objectives:**
- Schedule periodic batch jobs (cron-style)
- Understand batch vs service job types
- Prevent overlapping job runs
- View historical job runs and logs

### Basic Deployment

Deploy the periodic job:

```bash
nomad job run demos/cron-hello.nomad
```

Check the job status:

```bash
nomad job status cron-hello
```

**Expected output:**
```
ID            = cron-hello
Name          = cron-hello
Type          = batch
Priority      = 50
Datacenters   = dc1
Status        = running
Periodic      = true
Next Periodic Launch = 2026-01-20T09:45:30-08:00 (in 25s)

Children Job Summary
Pending  Running  Dead
0        1        5
```

### Understanding Periodic Jobs

The job runs every 30 seconds based on the cron expression:

```hcl
periodic {
  crons = ["*/1 * * * * *"]  # Format: second minute hour day month weekday
  prohibit_overlap = true     # Prevents concurrent runs
}
```

### Exercise 1: View Job History

List all child jobs (individual runs):

```bash
nomad job status cron-hello
```

View a specific run:

```bash
# Get the latest child job ID
CHILD_JOB=$(nomad job status cron-hello | grep "cron-hello/periodic" | head -1 | awk '{print $1}')

nomad job status $CHILD_JOB
```

View logs from a specific run:

```bash
nomad alloc logs -job $CHILD_JOB
```

**Expected output:**
```
hello Mon Jan 20 09:45:30 PST 2026
```

### Exercise 2: Aggregate Logs

View logs from all runs:

```bash
# Get all child job IDs
nomad job status cron-hello | grep "cron-hello/periodic" | awk '{print $1}' | while read job; do
  echo "=== $job ==="
  nomad alloc logs -job $job 2>/dev/null || echo "No logs available"
done
```

### Exercise 3: Change Schedule

Modify the cron expression to run every 5 minutes:

```diff
  periodic {
-   crons = ["*/1 * * * * *"]       # every 30s
+   crons = ["0 */5 * * * *"]       # every 5 minutes
    prohibit_overlap = true
  }
```

Redeploy:

```bash
nomad job run demos/cron-hello.nomad
nomad job status cron-hello
```

**Common cron expressions:**
```
*/30 * * * * *     # Every 30 seconds
0 */5 * * * *      # Every 5 minutes
0 0 * * * *        # Every hour
0 0 0 * * *        # Every day at midnight
0 0 9 * * MON-FRI  # Weekdays at 9 AM
```

### Exercise 4: Prohibit Overlap

Test the `prohibit_overlap` setting:

Modify the task to run longer:

```diff
  config {
    command = "bash"
-   args    = ["-c", "echo hello $(date) | tee -a local/out.log"]
+   args    = ["-c", "echo hello $(date) | tee -a local/out.log && sleep 120"]
  }
```

Set a short interval:

```diff
  periodic {
-   crons = ["0 */5 * * * *"]
+   crons = ["*/30 * * * * *"]  # Every 30 seconds
    prohibit_overlap = true
  }
```

Redeploy and observe:

```bash
nomad job run demos/cron-hello.nomad
nomad job status cron-hello
```

**Expected behavior:**
- First run starts and takes 120 seconds
- Second run is scheduled but skipped (overlap prevented)
- Third run starts after first completes

Try with `prohibit_overlap = false` to see concurrent runs.

### Exercise 5: Time Zone Configuration

Uncomment and set the time zone:

```diff
  periodic {
    crons = ["0 0 9 * * *"]  # 9 AM
-   #time_zone = "America/Los_Angeles"
+   time_zone = "America/Los_Angeles"
    prohibit_overlap = true
  }
```

This schedules the job at 9 AM Pacific Time instead of UTC.

### Cleanup

```bash
nomad job stop -purge cron-hello
```

---

## 🔧 Troubleshooting

### Common Issues

#### 1. Job Fails to Start

**Symptom:** Allocation status shows "failed"

**Debug:**
```bash
ALLOC=$(nomad job status -short <job-name> | grep failed | awk '{print $1}' | head -1)
nomad alloc status $ALLOC
nomad alloc logs -stderr $ALLOC
```

**Common causes:**
- Missing dependencies (e.g., Python not installed)
- Port conflicts
- Insufficient resources

#### 2. Health Checks Failing

**Symptom:** Deployment stuck, health checks never pass

**Debug:**
```bash
# Check allocation events
nomad alloc status $ALLOC

# Test the health check endpoint manually
PORT=$(nomad alloc status $ALLOC | grep "http:" | awk '{print $3}' | cut -d'=' -f2)
curl -v http://127.0.0.1:$PORT/
```

**Common causes:**
- Service not listening on expected port
- Health check path incorrect
- Timeout too short

#### 3. Template Rendering Errors

**Symptom:** Task fails with template error

**Debug:**
```bash
nomad alloc status $ALLOC
```

**Common causes:**
- Consul KV key doesn't exist
- Vault secret path incorrect
- Missing Vault permissions

**Fix:**
```bash
# Verify Consul KV
curl -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  http://127.0.0.1:8500/v1/kv/app/message

# Verify Vault secret
vault kv get secret/myapp/config
```

#### 4. Vault Token Issues

**Symptom:** "permission denied" errors when accessing Vault

**Debug:**
```bash
# Check Vault token
nomad alloc exec $ALLOC env | grep VAULT_TOKEN

# Test token manually
nomad alloc exec $ALLOC sh -c 'curl -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/auth/token/lookup-self'
```

**Common causes:**
- Token expired (shouldn't happen with auto-renewal)
- Insufficient Vault policies
- Vault integration not configured

### Useful Commands

```bash
# View all jobs
nomad job status

# Detailed allocation info
nomad alloc status -verbose $ALLOC

# Follow logs in real-time
nomad alloc logs -f -job <job-name>

# Execute command in running allocation
nomad alloc exec $ALLOC <command>

# View deployment progress
nomad deployment status $DEPLOYMENT

# Force garbage collection
nomad system gc

# View Nomad server logs
tail -f /tmp/ncv-dev.sh.*/nomad.log
```

---

## 📖 Additional Resources

- [Nomad Documentation](https://developer.hashicorp.com/nomad/docs)
- [Consul Documentation](https://developer.hashicorp.com/consul/docs)
- [Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Nomad Job Specification](https://developer.hashicorp.com/nomad/docs/job-specification)
- [Consul Template](https://github.com/hashicorp/consul-template)

---

## 🎯 Next Steps

After completing these tutorials, try:

1. **Combine patterns** - Create a web service that uses Consul KV for config and Vault for secrets
2. **Add monitoring** - Integrate Prometheus metrics and Grafana dashboards
3. **Multi-region** - Deploy across multiple datacenters
4. **Service mesh** - Enable Consul Connect for mTLS between services
5. **Advanced scheduling** - Use constraints, affinities, and spread for placement control

Happy learning! 🚀