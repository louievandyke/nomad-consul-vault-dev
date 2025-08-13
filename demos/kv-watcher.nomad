job "kv-watcher" {
  datacenters = ["dc1"]

  group "g" {
    task "watcher" {
      driver = "raw_exec"

      config {
        command = "bash"
        args    = ["-c", "while true; do echo \"$(date) MESSAGE=$MESSAGE\"; sleep 5; done"]
      }

      template {
        data = <<EOH
MESSAGE="{{ key "app/message" }}"
EOH
        destination = "local/env"
        env         = true
        change_mode = "restart"
      }
    }
  }
}
