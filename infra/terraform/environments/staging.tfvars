# Terraform — STAGING environment (ADR 0007, #4).
# NON-secret parameters only. Secret values are injected as TF_VAR_* from the
# SOPS vault at apply time (see infra/terraform/main.tf header). NEVER set
# `country` here — it is pinned to CI in main.tf and must not be overridden.
#
# Residency: in-country (ARTCI / loi n°2013-450, ADR 0005). Full live bring-up
# depends on #8 (sovereign hosting provisioning).
environment            = "staging"
backend_instance_count = 2
postgres_replica_count = 1
