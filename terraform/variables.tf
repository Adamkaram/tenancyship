variable "vault_addr" {
  description = "Vault server address"
  type        = string
}

variable "vault_token" {
  description = "Vault authentication token"
  type        = string
  sensitive   = true
}

variable "surrealdb_url" {
  description = "SurrealDB connection URL"
  type        = string
  sensitive   = true
}

variable "surrealdb_user" {
  description = "SurrealDB username"
  type        = string
  sensitive   = true
}

variable "surrealdb_password" {
  description = "SurrealDB password"
  type        = string
  sensitive   = true
}

variable "surrealdb_ns" {
  description = "SurrealDB namespace"
  type        = string
  sensitive   = true
}

variable "surrealdb_db" {
  description = "SurrealDB database name"
  type        = string
  sensitive   = true
}

variable "k8s_namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "default"
} 