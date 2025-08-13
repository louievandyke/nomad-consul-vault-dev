job "vault-token" {
  datacenters = ["dc1"]

  group "g" {
    task "t" {
      driver = "raw_exec"

      config {
        command = "bash"
        args    = ["-c", "echo VAULT_TOKEN prefix: ${VAULT_TOKEN:0:8}; curl -s -H \"X-Vault-Token: $VAULT_TOKEN\" $VAULT_ADDR/v1/auth/token/lookup-self || true; sleep 60"]
      }

      template {
        data = <<EOH
VAULT_TOKEN={{ with secret "auth/token/lookup-self" }}{{ .Data.id }}{{ end }}
EOH
        destination = "secrets/token.env"
        env         = true
      }
    }
  }
}
