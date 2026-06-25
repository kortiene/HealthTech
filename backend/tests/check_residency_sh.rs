// Integration tests for scripts/check-residency.sh (ADR 0005/0007, issue #8).
//
// Each test copies the real script into an isolated temporary directory so the
// script's `cd "$(dirname "$0")/.."` lands in the tmpdir (not the real repo).
// Since those dirs are not git repositories the script falls back to `find .`
// instead of `git ls-files`, which is sufficient to exercise all four checks.
//
// Tests are self-contained: no network, no real cloud credentials, no IaC apply.
// Synthetic file content is used throughout; nothing here represents a real
// cloud deployment or real secret.
//
// Checks exercised:
//   1. Foreign IaC provider in the data path (provider "aws|google|azurerm|…")
//   2. Foreign managed state backend (backend "gcs|azurerm|oss|cos")
//   3. Foreign cloud endpoint/host in infra/ config files (amazonaws.com, …)
//   4. Residency pin `country` overridden to a non-CI value in tfvars/yml/yaml

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

// ─── helpers ─────────────────────────────────────────────────────────────────

/// Returns the monorepo workspace root (parent of `backend/`).
fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("backend/ has a parent directory")
        .to_path_buf()
}

/// A temporary directory removed (best-effort) on drop.
struct TmpDir(PathBuf);

impl TmpDir {
    fn new(tag: &str) -> Self {
        let pid = std::process::id();
        let path = std::env::temp_dir().join(format!("healthtech_residency_{tag}_{pid}"));
        fs::create_dir_all(&path).unwrap_or_else(|e| panic!("create {path:?}: {e}"));
        TmpDir(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TmpDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// Copy `scripts/check-residency.sh` into `<base>/scripts/` and mark it executable.
/// The script does `cd "$(dirname "$0")/.."` which resolves to `<base>/`.
fn install_script(base: &Path) {
    let scripts_dir = base.join("scripts");
    fs::create_dir_all(&scripts_dir).unwrap();

    let src = workspace_root().join("scripts/check-residency.sh");
    let dst = scripts_dir.join("check-residency.sh");
    fs::copy(&src, &dst).unwrap_or_else(|e| panic!("copy check-residency.sh to {dst:?}: {e}"));

    let mut perms = fs::metadata(&dst).unwrap().permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&dst, perms).unwrap();
}

/// Run the script and return its `Output` (exit status + stderr).
fn run_script(base: &Path) -> std::process::Output {
    Command::new("bash")
        .arg(base.join("scripts/check-residency.sh"))
        .output()
        .expect("failed to spawn check-residency.sh — is bash available?")
}

/// Write `content` to `<base>/<rel>`, creating parent directories as needed.
fn write(base: &Path, rel: &str, content: &str) {
    let p = base.join(rel);
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(&p, content).unwrap_or_else(|e| panic!("write {p:?}: {e}"));
}

// ─── check 0 — baseline: empty directory (scaffold-tolerant) passes ──────────

#[test]
fn clean_dir_with_no_infra_passes() {
    let tmp = TmpDir::new("clean");
    install_script(tmp.path());

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "empty directory (no infra/) must pass the residency gate; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── check 1 — foreign IaC provider ─────────────────────────────────────────

#[test]
fn tf_aws_provider_block_fails() {
    let tmp = TmpDir::new("aws_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"aws\" { region = \"us-east-1\" }\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "provider \"aws\" block must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("foreign IaC provider"),
        "error should mention 'foreign IaC provider'; got:\n{stderr}"
    );
}

#[test]
fn tf_google_provider_block_fails() {
    let tmp = TmpDir::new("gcp_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"google\" { project = \"my-project\" }\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "provider \"google\" block must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("foreign IaC provider"),
        "error should mention 'foreign IaC provider'; got:\n{stderr}"
    );
}

#[test]
fn tf_azurerm_provider_block_fails() {
    let tmp = TmpDir::new("arm_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"azurerm\" { features {} }\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "provider \"azurerm\" block must be rejected"
    );
}

#[test]
fn tf_digitalocean_provider_block_fails() {
    let tmp = TmpDir::new("do_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"digitalocean\" { token = var.do_token }\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "provider \"digitalocean\" block must be rejected"
    );
}

#[test]
fn tf_aws_required_providers_source_fails() {
    let tmp = TmpDir::new("aws_src");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        concat!(
            "terraform {\n",
            "  required_providers {\n",
            "    aws = { source = \"hashicorp/aws\", version = \"~> 5.0\" }\n",
            "  }\n",
            "}\n"
        ),
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "source = \"hashicorp/aws\" in required_providers must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("foreign provider source"),
        "error should mention 'foreign provider source'; got:\n{stderr}"
    );
}

#[test]
fn tf_google_required_providers_source_fails() {
    let tmp = TmpDir::new("gcp_src");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "  google = { source = \"hashicorp/google\" }\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "source = \"hashicorp/google\" in required_providers must be rejected"
    );
}

#[test]
fn tf_comment_prose_no_foreign_provider_mention_passes() {
    // The pattern greps for structural `provider "X"` forms, not free-form prose.
    // A comment line like "# no aws/google/azurerm" must NOT trigger the check.
    let tmp = TmpDir::new("prose_ok");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        concat!(
            "# No foreign cloud: no aws / no google / no azurerm.\n",
            "# Only in-country ARTCI-licensed operators are admitted.\n",
        ),
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "prose comment mentioning forbidden provider names must not trigger check 1; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn tf_unknown_local_operator_provider_passes() {
    // A provider from a national/local operator not in the foreign-providers list
    // must pass — it is the intended future state once the operator is chosen.
    let tmp = TmpDir::new("local_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"vitib-cloud\" { endpoint = \"https://api.vitib.ci\" }\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "unknown local-operator provider must not be rejected; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── check 2 — foreign managed state backend ─────────────────────────────────

#[test]
fn tf_gcs_backend_fails() {
    let tmp = TmpDir::new("gcs_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        concat!(
            "terraform {\n",
            "  backend \"gcs\" { bucket = \"my-tf-state\" }\n",
            "}\n"
        ),
    );

    let out = run_script(tmp.path());
    assert!(!out.status.success(), "backend \"gcs\" must be rejected");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("foreign managed state backend"),
        "error should mention 'foreign managed state backend'; got:\n{stderr}"
    );
}

#[test]
fn tf_azurerm_backend_fails() {
    let tmp = TmpDir::new("arm_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "backend \"azurerm\" { storage_account_name = \"tfstate\" }\n",
    );

    let out = run_script(tmp.path());
    assert!(!out.status.success(), "backend \"azurerm\" must be rejected");
}

#[test]
fn tf_oss_backend_fails() {
    let tmp = TmpDir::new("oss_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "backend \"oss\" { bucket = \"terraform-state\" }\n",
    );

    let out = run_script(tmp.path());
    assert!(!out.status.success(), "backend \"oss\" must be rejected");
}

#[test]
fn tf_cos_backend_fails() {
    let tmp = TmpDir::new("cos_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "backend \"cos\" { bucket = \"terraform-state\" }\n",
    );

    let out = run_script(tmp.path());
    assert!(!out.status.success(), "backend \"cos\" must be rejected");
}

#[test]
fn tf_s3_backend_with_private_ci_endpoint_passes() {
    // backend "s3" is also used for MinIO-compatible in-country state storage.
    // A .ci private endpoint must NOT be blocked by check 2 (only check 3 would
    // catch a real amazonaws.com endpoint, which is absent here).
    let tmp = TmpDir::new("s3_minio_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        concat!(
            "terraform {\n",
            "  backend \"s3\" {\n",
            "    bucket   = \"tf-state\"\n",
            "    endpoint = \"https://minio.internal.vitib.ci\"\n",
            "    region   = \"ci\"\n",
            "  }\n",
            "}\n"
        ),
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "backend \"s3\" with a .ci endpoint (MinIO in-country) must pass; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn tf_local_backend_passes() {
    let tmp = TmpDir::new("local_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "backend \"local\" { path = \"/tmp/tf.tfstate\" }\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "backend \"local\" must pass check 2; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── check 3 — foreign cloud endpoint/host in infra/ config files ────────────

#[test]
fn infra_tf_amazonaws_endpoint_fails() {
    let tmp = TmpDir::new("aws_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "endpoint = \"https://s3.amazonaws.com\"\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "amazonaws.com endpoint in infra/*.tf must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("foreign cloud endpoint"),
        "error should mention 'foreign cloud endpoint'; got:\n{stderr}"
    );
}

#[test]
fn infra_tf_googleapis_endpoint_fails() {
    let tmp = TmpDir::new("gcp_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "url = \"https://storage.googleapis.com/bucket/object\"\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "googleapis.com endpoint in infra/*.tf must be rejected"
    );
}

#[test]
fn infra_tf_azure_blob_endpoint_fails() {
    let tmp = TmpDir::new("arm_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "url = \"https://account.blob.core.windows.net/container\"\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "blob.core.windows.net endpoint in infra/*.tf must be rejected"
    );
}

#[test]
fn infra_tf_s3_backend_with_amazonaws_endpoint_fails() {
    // backend "s3" is allowed by check 2, but if it references real AWS the
    // amazonaws.com endpoint trips check 3.
    let tmp = TmpDir::new("s3_aws_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        concat!(
            "backend \"s3\" {\n",
            "  bucket   = \"tf-state\"\n",
            "  endpoint = \"https://s3.amazonaws.com\"\n",
            "}\n"
        ),
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "backend \"s3\" pointing at amazonaws.com must be caught by the endpoint check"
    );
}

#[test]
fn infra_readme_amazonaws_endpoint_passes() {
    // Markdown files under infra/ are exempt from the endpoint check — they may
    // explain "no amazonaws.com" in prose without triggering the rule.
    let tmp = TmpDir::new("aws_md");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/README.md",
        "Do NOT use amazonaws.com or any foreign cloud in the data path.\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "amazonaws.com in infra/README.md (markdown exempt) must not trigger check 3; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn infra_txt_amazonaws_endpoint_passes() {
    // Plain text files under infra/ are also exempt from the endpoint check.
    let tmp = TmpDir::new("aws_txt");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/notes.txt",
        "Reminder: no amazonaws.com — data stays in-country.\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "amazonaws.com in infra/notes.txt (text exempt) must not trigger check 3; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn non_infra_file_amazonaws_endpoint_passes() {
    // Files outside infra/ (docs, scripts, etc.) are not part of the data-path
    // IaC scan and must not trigger check 3.
    let tmp = TmpDir::new("aws_out");
    install_script(tmp.path());
    write(
        tmp.path(),
        "docs/architecture.md",
        "The system avoids amazonaws.com by design.\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "amazonaws.com outside infra/ must not trigger check 3; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn infra_tf_ci_domain_endpoint_passes() {
    // A .ci TLD is an in-country host — not a foreign cloud endpoint.
    let tmp = TmpDir::new("ci_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "endpoint = \"https://minio.internal.vitib.ci\"\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        ".ci endpoint in infra/*.tf must pass check 3; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── check 4 — residency pin `country` overridden to a non-CI value ──────────

#[test]
fn tfvars_country_fr_fails() {
    let tmp = TmpDir::new("ctry_fr_tfv");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/environments/staging.tfvars",
        "country = \"FR\"\nenvironment = \"staging\"\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "country = \"FR\" in tfvars must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("residency pin overridden"),
        "error should mention 'residency pin overridden'; got:\n{stderr}"
    );
}

#[test]
fn tfvars_country_us_fails() {
    let tmp = TmpDir::new("ctry_us_tfv");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/environments/prod.tfvars",
        "country = \"US\"\nenvironment = \"prod\"\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "country = \"US\" in tfvars must be rejected"
    );
}

#[test]
fn yaml_country_us_fails() {
    let tmp = TmpDir::new("ctry_us_yml");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/staging.yml",
        "env: staging\ncountry: US\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "country: US in group_vars yaml must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("residency pin overridden"),
        "error should mention 'residency pin overridden'; got:\n{stderr}"
    );
}

#[test]
fn yaml_country_quoted_fr_fails() {
    let tmp = TmpDir::new("ctry_fr_yml");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/prod.yml",
        "env: prod\ncountry: \"FR\"\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "country: \"FR\" (quoted) in yaml must be rejected"
    );
}

#[test]
fn tfvars_country_ci_passes() {
    let tmp = TmpDir::new("ctry_ci_tfv");
    install_script(tmp.path());
    // The spec says `country` must not be set in per-env tfvars, but if it IS
    // set to CI the gate must not reject it — the rule is only about non-CI values.
    write(
        tmp.path(),
        "infra/terraform/environments/staging.tfvars",
        "environment = \"staging\"\ncountry = \"CI\"\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "country = \"CI\" in tfvars must pass check 4; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn yaml_country_ci_passes() {
    let tmp = TmpDir::new("ctry_ci_yml");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/staging.yml",
        "env: staging\ncountry: CI\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "country: CI in yaml must pass check 4; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn yaml_country_ci_with_inline_comment_passes() {
    // The actual group_vars files use this exact pattern — it must be accepted.
    let tmp = TmpDir::new("ctry_ci_cmt");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/prod.yml",
        "env: prod\ncountry: CI # residency pin (ARTCI / loi 2013-450); never override\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "country: CI with inline comment must pass check 4; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn yaml_with_no_country_key_passes() {
    // A yaml file that does not set `country` at all must not fail check 4.
    let tmp = TmpDir::new("no_ctry_yml");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/dev.yml",
        "env: dev\nbackend_instance_count: 1\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "yaml with no `country` key must pass check 4; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── accumulation — multiple violations all reported before exit ──────────────

#[test]
fn multiple_violations_all_reported_and_exits_nonzero() {
    // The script uses `fail=1` + `note()` to accumulate all violations before
    // exiting — every hit should appear in stderr, not just the first.
    let tmp = TmpDir::new("multi");
    install_script(tmp.path());

    // Check 1: foreign IaC provider
    // Check 2: foreign managed backend
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        concat!(
            "provider \"aws\" { region = \"us-east-1\" }\n",
            "backend \"gcs\" { bucket = \"state\" }\n",
        ),
    );
    // Check 4: country pin override
    write(
        tmp.path(),
        "infra/ansible/group_vars/prod.yml",
        "env: prod\ncountry: US\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "multiple violations must cause a non-zero exit"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("foreign IaC provider"),
        "provider violation not reported; stderr:\n{stderr}"
    );
    assert!(
        stderr.contains("foreign managed state backend"),
        "backend violation not reported; stderr:\n{stderr}"
    );
    assert!(
        stderr.contains("residency pin overridden"),
        "country-pin violation not reported; stderr:\n{stderr}"
    );
}

// ─── check 1 — additional foreign providers from the full list ───────────────

#[test]
fn tf_oci_provider_block_fails() {
    let tmp = TmpDir::new("oci_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"oci\" { tenancy_ocid = var.tenancy_ocid }\n",
    );
    let out = run_script(tmp.path());
    assert!(!out.status.success(), "provider \"oci\" block must be rejected");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("foreign IaC provider"), "got:\n{stderr}");
}

#[test]
fn tf_ibm_provider_block_fails() {
    let tmp = TmpDir::new("ibm_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"ibm\" { region = \"eu-de\" }\n",
    );
    let out = run_script(tmp.path());
    assert!(!out.status.success(), "provider \"ibm\" block must be rejected");
}

#[test]
fn tf_hcloud_provider_block_fails() {
    let tmp = TmpDir::new("hcl_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"hcloud\" { token = var.hcloud_token }\n",
    );
    let out = run_script(tmp.path());
    assert!(!out.status.success(), "provider \"hcloud\" block must be rejected");
}

#[test]
fn tf_linode_provider_block_fails() {
    let tmp = TmpDir::new("lin_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"linode\" { token = var.linode_token }\n",
    );
    let out = run_script(tmp.path());
    assert!(!out.status.success(), "provider \"linode\" block must be rejected");
}

#[test]
fn tf_vultr_provider_block_fails() {
    let tmp = TmpDir::new("vul_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"vultr\" { api_key = var.vultr_api_key }\n",
    );
    let out = run_script(tmp.path());
    assert!(!out.status.success(), "provider \"vultr\" block must be rejected");
}

#[test]
fn tf_scaleway_provider_block_fails() {
    let tmp = TmpDir::new("scw_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"scaleway\" { zone = \"fr-par-1\" }\n",
    );
    let out = run_script(tmp.path());
    assert!(!out.status.success(), "provider \"scaleway\" block must be rejected");
}

#[test]
fn tf_ovh_provider_block_fails() {
    let tmp = TmpDir::new("ovh_prov");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"ovh\" { endpoint = \"ovh-eu\" }\n",
    );
    let out = run_script(tmp.path());
    assert!(!out.status.success(), "provider \"ovh\" block must be rejected");
}

#[test]
fn tf_provider_block_case_insensitive_fails() {
    // The script uses `grep -i` so uppercase provider names must also be rejected.
    let tmp = TmpDir::new("aws_upper");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "provider \"AWS\" { region = \"us-east-1\" }\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "provider \"AWS\" (uppercase) must be rejected — grep uses -i"
    );
}

#[test]
fn tf_json_foreign_provider_fails() {
    // The script also handles the *.tf.json extension.
    let tmp = TmpDir::new("aws_json");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf.json",
        "{\"provider\": {\"aws\": {\"region\": \"us-east-1\"}}}\n",
    );
    let out = run_script(tmp.path());
    assert!(!out.status.success(), "provider \"aws\" in *.tf.json must be rejected");
}

// ─── check 2 — backends that are NOT in the blocked list should pass ──────────

#[test]
fn tf_http_backend_passes() {
    let tmp = TmpDir::new("http_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "backend \"http\" { address = \"https://terraform.internal.vitib.ci/state\" }\n",
    );
    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "backend \"http\" must pass check 2 (not in the foreign-backend list); stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn tf_consul_backend_passes() {
    let tmp = TmpDir::new("consul_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "backend \"consul\" { path = \"terraform/state\" }\n",
    );
    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "backend \"consul\" must pass check 2; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn tf_pg_backend_passes() {
    let tmp = TmpDir::new("pg_be");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "backend \"pg\" { conn_str = var.pg_conn_str }\n",
    );
    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "backend \"pg\" must pass check 2; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── check 3 — additional foreign endpoints ───────────────────────────────────

#[test]
fn infra_tf_digitalocean_spaces_endpoint_fails() {
    let tmp = TmpDir::new("do_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "endpoint = \"https://ams3.digitaloceanspaces.com\"\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "digitaloceanspaces.com endpoint in infra/*.tf must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("foreign cloud endpoint"), "got:\n{stderr}");
}

#[test]
fn infra_tf_linode_objects_endpoint_fails() {
    let tmp = TmpDir::new("lin_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "url = \"https://bucket.us-east-1.linodeobjects.com\"\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        ".linodeobjects.com endpoint in infra/*.tf must be rejected"
    );
}

#[test]
fn infra_tf_scaleway_scw_cloud_endpoint_fails() {
    let tmp = TmpDir::new("scw_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "url = \"https://s3.nl-ams.scw.cloud\"\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        ".scw.cloud endpoint in infra/*.tf must be rejected"
    );
}

#[test]
fn infra_tf_ovh_net_endpoint_fails() {
    let tmp = TmpDir::new("ovh_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "url = \"https://s3.gra.cloud.ovh.net\"\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        ".ovh.net endpoint in infra/*.tf must be rejected"
    );
}

#[test]
fn infra_tf_backblaze_b2_endpoint_fails() {
    let tmp = TmpDir::new("b2_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "url = \"https://s3.us-west-004.backblazeb2.com\"\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "backblazeb2.com endpoint in infra/*.tf must be rejected"
    );
}

#[test]
fn infra_tf_wasabi_endpoint_fails() {
    let tmp = TmpDir::new("wasabi_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "endpoint = \"https://s3.eu-central-1.wasabisys.com\"\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        ".wasabisys.com endpoint in infra/*.tf must be rejected"
    );
}

#[test]
fn infra_tf_azure_web_endpoint_fails() {
    let tmp = TmpDir::new("arm_web_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/terraform/main.tf",
        "url = \"https://myapp.azurewebsites.net\"\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        ".azurewebsites.net endpoint in infra/*.tf must be rejected"
    );
}

#[test]
fn infra_ansible_yaml_foreign_endpoint_fails() {
    // Ansible YAML files inside infra/ are NOT markdown/text, so check 3 applies.
    // An inventory or group_vars file pointing at a foreign cloud host must fail.
    let tmp = TmpDir::new("ans_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/prod.yml",
        "env: prod\ncountry: CI\nbackup_target: https://mybucket.s3.amazonaws.com\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "amazonaws.com in infra/ansible/*.yml must be caught by check 3"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("foreign cloud endpoint"), "got:\n{stderr}");
}

#[test]
fn infra_ansible_inventory_foreign_endpoint_fails() {
    // An inventory file in infra/ referencing a foreign host trips check 3.
    let tmp = TmpDir::new("ans_inv_ep");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/inventories/staging",
        "[staging]\nbackup-host ansible_host=bucket.us-east-1.linodeobjects.com\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        ".linodeobjects.com in infra/ansible/inventories/* must be caught by check 3"
    );
}

// ─── check 4 — additional country-pin edge cases ──────────────────────────────

#[test]
fn yaml_extension_country_non_ci_fails() {
    // The script also matches *.yaml (not just *.yml); this must be scanned.
    let tmp = TmpDir::new("ctry_yaml_ext");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/prod.yaml",
        "env: prod\ncountry: DE\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "country: DE in a *.yaml file must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("residency pin overridden"), "got:\n{stderr}");
}

#[test]
fn yaml_extension_country_ci_passes() {
    let tmp = TmpDir::new("ctry_yaml_ok");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/staging.yaml",
        "env: staging\ncountry: CI\n",
    );
    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "country: CI in a *.yaml file must pass; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn yaml_country_single_quoted_non_ci_fails() {
    // YAML allows `country: 'FR'` (single-quoted scalar); the regex must catch it.
    let tmp = TmpDir::new("ctry_sq_fr");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/staging.yml",
        "env: staging\ncountry: 'FR'\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "country: 'FR' (single-quoted) in yaml must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("residency pin overridden"), "got:\n{stderr}");
}

#[test]
fn yaml_country_single_quoted_ci_passes() {
    // `country: 'CI'` is valid YAML and must also be accepted.
    let tmp = TmpDir::new("ctry_sq_ci");
    install_script(tmp.path());
    write(
        tmp.path(),
        "infra/ansible/group_vars/staging.yml",
        "env: staging\ncountry: 'CI'\n",
    );
    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "country: 'CI' (single-quoted) must pass check 4; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn tfvars_outside_infra_with_non_ci_country_fails() {
    // *.tfvars files are scanned for the country pin regardless of location.
    let tmp = TmpDir::new("ctry_outpath_tfv");
    install_script(tmp.path());
    write(
        tmp.path(),
        "environments/override.tfvars",
        "country = \"SN\"\n",
    );
    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "country = \"SN\" in a *.tfvars outside infra/ must be rejected"
    );
}

// ─── smoke — real repository passes the residency check ──────────────────────

#[test]
fn real_repo_passes_residency_check() {
    // Run the script directly on the actual checked-out repository. This is the
    // canonical smoke test: no committed file must introduce a foreign-cloud
    // provider, backend, endpoint, or country-pin override.
    let repo_root = workspace_root();
    let script = repo_root.join("scripts/check-residency.sh");

    let out = Command::new("bash")
        .arg(&script)
        .output()
        .expect("failed to spawn check-residency.sh on the real repo");

    assert!(
        out.status.success(),
        "check-residency.sh must pass on the real repo; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}
