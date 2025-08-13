job "web" {
  datacenters = ["dc1"]

  group "g" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "web"
      port = "http"
      check {
        type     = "http"
        path     = "/"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "raw_exec"
      config {
        command = "bash"
        args    = ["-c", "python3 -m http.server 8080"]
      }
      resources {
        cpu    = 100
        memory = 64
      }
    }

    update {
      max_parallel     = 1
      min_healthy_time = "5s"
      healthy_deadline = "1m"
      auto_revert      = true
    }
  }
}
