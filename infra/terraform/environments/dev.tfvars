# Terraform — DEV environment (ADR 0007, #4).
# NON-secret parameters only. Secret values are injected as TF_VAR_* from the
# SOPS vault at apply time (see infra/terraform/main.tf header). NEVER set
# `country` here — it is pinned to CI in main.tf and must not be overridden.
#
# `dev` is a developer laptop with synthetic data + throwaway secrets; the local
# `infra/dev/compose.yaml` stack stands in for the real footprint.
environment            = "dev"
backend_instance_count = 1
postgres_replica_count = 0
