terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
      version = "~> 3.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Create a Vault secret engine
resource "vault_mount" "surrealdb" {
  path = "surrealdb"
  type = "kv"
  options = {
    version = "2"
  }
}

# Store SurrealDB credentials in Vault
resource "vault_kv_secret_v2" "surrealdb_creds" {
  mount = vault_mount.surrealdb.path
  name  = "tenant-service"
  
  data_json = jsonencode({
    url      = var.surrealdb_url
    user     = var.surrealdb_user
    password = var.surrealdb_password
    ns       = var.surrealdb_ns
    db       = var.surrealdb_db
  })
}

# Create Kubernetes secret
resource "kubernetes_secret" "surrealdb_creds" {
  metadata {
    name = "surrealdb-creds"
    namespace = var.k8s_namespace
  }

  data = {
    SURREALDB_URL  = var.surrealdb_url
    SURREALDB_USER = var.surrealdb_user
    SURREALDB_PASS = var.surrealdb_password
    SURREALDB_NS   = var.surrealdb_ns
    SURREALDB_DB   = var.surrealdb_db
  }
} 