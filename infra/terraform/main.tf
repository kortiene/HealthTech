# =============================================================================
# HealthTech — sovereign in-country hosting (Terraform)
# Implements ADR 0005 — Storage & sovereign hosting.
#
# RESIDENCY (non-negotiable): every resource below MUST live physically in
# Côte d'Ivoire, on an ARTCI-eligible national datacenter / licensed local
# operator (e.g. VITIB-Grand-Bassam). NO foreign managed cloud anywhere in the
# data path. NO real provider credentials belong in this repo.
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
# VM/bare-metal definitions, private networking, security groups, and backup
# volumes. Long-lead procurement — on the launch critical path; start early.
# =============================================================================

terraform {
  required_version = ">= 1.9"

  # TODO(#8): pin the ARTCI-licensed local operator's provider here. No foreign
  # cloud providers (aws / google / azurerm) in the data path.
  # required_providers {
  #   <local_operator> = {
  #     source  = "<registry>/<local_operator>"
  #     version = "~> x.y"
  #   }
  # }
}

# Placeholder inputs so `terraform validate` passes with no credentials.
# TODO(#8): expand into real region/zone (must resolve to CI soil), instance
# sizes, network CIDRs, and backup retention.
variable "country" {
  description = "Hosting country — MUST remain Côte d'Ivoire for ARTCI / loi 2013-450 compliance."
  type        = string
  default     = "CI"

  validation {
    condition     = var.country == "CI"
    error_message = "Residency violation: hosting country must be CI (Côte d'Ivoire)."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. staging, prod)."
  type        = string
  default     = "staging"
}

# No resources are declared yet — see TODO(#8) above.
output "residency_note" {
  description = "Compliance reminder surfaced by `terraform output`."
  value       = "All HealthTech infrastructure is hosted in ${var.country}; no foreign cloud in the data path (ADR 0005)."
}
