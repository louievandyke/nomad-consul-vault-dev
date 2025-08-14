job "web" {
  datacenters = ["dc1"]

  group "g" {
    count = 1

    network {
      port "http" {
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
        args    = ["-c", "echo v1 > index.html && python3 -m http.server ${NOMAD_PORT_http}"]
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
