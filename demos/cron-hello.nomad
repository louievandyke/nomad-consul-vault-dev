job "cron-hello" {
  datacenters = ["dc1"]
  type = "batch"

  periodic {
    crons = ["*/1 * * * * *"]       # every 30s (seconds field first)
    #time_zone = "America/Los_Angeles" # optional; computes schedule in your TZ (default is UTC)
    prohibit_overlap = true
  }

  group "g" {
    task "hello" {
      driver = "raw_exec"
      config {
        command = "bash"
        args    = ["-c", "echo hello $(date) | tee -a local/out.log"]
      }
      resources {
        cpu = 50
        memory = 64
      }
    }
  }
}
