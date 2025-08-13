job "cron-hello" {
  datacenters = ["dc1"]
  type = "batch"

  periodic {
    cron             = "@every 30s"
    prohibit_overlap = true
  }

  group "g" {
    task "say" {
      driver = "raw_exec"
      config {
        command = "bash"
        args    = ["-c", "echo Hello from $(hostname) at $(date)"]
      }
    }
  }
}
