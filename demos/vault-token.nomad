job "vault-token" {
  datacenters = ["dc1"]

  group "g" {
    task "t" {
      driver = "raw_exec"

      config {
        command = "bash"
        args = [
          "-c",
          <<-EOT
            echo "VAULT_TOKEN prefix: $(printf '%s' "$VAULT_TOKEN" | cut -c1-8)"
            curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/auth/token/lookup-self" || true
            sleep 60
          EOT
        ]
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
