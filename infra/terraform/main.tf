# =============================================================================
# HealthTech — sovereign in-country hosting (Terraform)
# Implements ADR 0005 — Storage & sovereign hosting.
# Environments & secret injection: ADR 0007 — Secrets management & environments (#4).
#
# RESIDENCY (non-negotiable): every resource below MUST live physically in
# Côte d'Ivoire, on an ARTCI-eligible national datacenter / licensed local
# operator (e.g. VITIB-Grand-Bassam). NO foreign managed cloud anywhere in the
# data path. NO real provider credentials and NO secret VALUES belong in this repo.
#
# ENVIRONMENTS (ADR 0007): select an environment with a per-env var-file, e.g.
#   terraform plan  -var-file=environments/staging.tfvars
#   terraform apply -var-file=environments/staging.tfvars
# Secret VALUES are injected at apply time from the SOPS/age vault as TF_VAR_*,
# never from a committed plaintext, e.g.
#   sops exec-env secrets/staging/services.sops.yaml \
#     'terraform apply -var-file=environments/staging.tfvars'
# State can embed secret values, so the state backend MUST be encrypted and
# in-country (TODO(#8)); local *.tfstate is gitignored but that alone is not enough.
#
# In-country data-path footprint to provision (ADR 0005):
#   - Axum backend            x2   (HA, behind the reverse proxy)
#   - MinIO                    x1   (S3-compatible encrypted-blob + media store)
#   - PostgreSQL primary       x1   (non-identifying metadata only)
#   - PostgreSQL replica       x1   (read replica / warm standby for HA)
#   - Caddy / TLS reverse proxy x1  (terminates TLS, fronts the two backends)
#   - WAF                      x1   (in front of the reverse proxy)
#   - In-country encrypted backups (for MinIO + Postgres)
#
# TODO(#8): replace this placeholder with the real local-operator provider,
# VM/bare-metal definitions, private networking, security groups, backup
# volumes, and the encrypted in-country state backend. Long-lead procurement.
# =============================================================================

terraform {
  required_version = ">= 1.9"

  # TODO(#8): pin the ARTCI-licensed local operator's provider here. No foreign
  # cloud providers (aws / google / azurerm) in the data path.
  # TODO(#8): configure an ENCRYPTED, in-country state backend (state may embed
  # secret values). Do NOT use a foreign managed backend (S3/GCS/Azure).
  # required_providers {
  #   <local_operator> = {
  #     source  = "<registry>/<local_operator>"
  #     version = "~> x.y"
  #   }
  # }
}

# --- Residency guardrail (non-negotiable) -----------------------------------
# `country` is deliberately NOT exposed in the per-environment tfvars: it is
# pinned here so it cannot be overridden per environment. The validation rejects
# any value other than CI, so staging AND prod are always in-country.
variable "country" {
  description = "Hosting country — pinned to Côte d'Ivoire for ARTCI / loi 2013-450. Do NOT set this in any environment tfvars."
  type        = string
  default     = "CI"

  validation {
    condition     = var.country == "CI"
    error_message = "Residency violation: hosting country must be CI (Côte d'Ivoire); it cannot be overridden per environment (ADR 0005/0007)."
  }
}

# --- Environment selection (ADR 0007) ---------------------------------------
variable "environment" {
  description = "Deployment environment. One of dev | staging | prod (select via -var-file=environments/<env>.tfvars)."
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# --- Non-secret, per-environment sizing (set in environments/<env>.tfvars) ---
variable "backend_instance_count" {
  description = "Number of Axum backend instances (HA). Set per environment."
  type        = number
  default     = 2
}

variable "postgres_replica_count" {
  description = "Number of PostgreSQL read replicas / warm standbys. Set per environment."
  type        = number
  default     = 1
}

# --- Injected secrets (ADR 0007) --------------------------------------------
# These carry NO value in the repo. They are injected at apply time from the
# SOPS/age vault as TF_VAR_* (e.g. via `sops exec-env`). `default = null` keeps
# credential-free `validate`/`plan` working; `sensitive = true` keeps any value
# out of CLI/log output. The real backend (#8/#9) consumes them.
variable "postgres_app_password" {
  description = "Injected at apply time from the vault (TF_VAR_postgres_app_password). Never committed."
  type        = string
  default     = null
  sensitive   = true
}

variable "minio_root_secret" {
  description = "Injected at apply time from the vault (TF_VAR_minio_root_secret). Never committed."
  type        = string
  default     = null
  sensitive   = true
}

variable "presigned_url_signing_key" {
  description = "Injected at apply time from the vault (TF_VAR_presigned_url_signing_key). Never committed."
  type        = string
  default     = null
  sensitive   = true
}

# --- Derived naming ----------------------------------------------------------
locals {
  name_prefix = "healthtech-${var.environment}"

  # Surface (without leaking values) which injected secrets are present, so a
  # plan/apply can be sanity-checked. Booleans only — never the secret itself;
  # `nonsensitive` unwraps the (sensitive) value into a plain present/absent flag.
  injected_secrets_present = {
    postgres_app_password     = nonsensitive(var.postgres_app_password != null)
    minio_root_secret         = nonsensitive(var.minio_root_secret != null)
    presigned_url_signing_key = nonsensitive(var.presigned_url_signing_key != null)
  }
}

# No resources are declared yet — see TODO(#8) above.

output "residency_note" {
  description = "Compliance reminder surfaced by `terraform output`."
  value       = "All HealthTech infrastructure is hosted in ${var.country}; no foreign cloud in the data path (ADR 0005)."
}

output "environment" {
  description = "The selected deployment environment."
  value       = var.environment
}

output "name_prefix" {
  description = "Per-environment resource name prefix."
  value       = local.name_prefix
}

output "injected_secrets_present" {
  description = "Booleans indicating which vault-injected secrets were supplied (never the values)."
  value       = local.injected_secrets_present
}
