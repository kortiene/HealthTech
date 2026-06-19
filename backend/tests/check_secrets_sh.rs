// Integration tests for scripts/check-secrets.sh (ADR 0007, issue #4).
//
// Each test copies the real script into an isolated temporary directory so the
// script's `cd "$(dirname "$0")/.."` lands in the tmpdir (not the real repo).
// Since those dirs are not git repositories the script falls back to `find .`
// instead of `git ls-files`, which is sufficient to exercise all five checks.
//
// Tests are self-contained: no network, no real secrets, no crypto operations.
// Synthetic file content is used throughout; nothing here resembles a real key.

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
        let path = std::env::temp_dir().join(format!("healthtech_test_{tag}_{pid}"));
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

/// Copy `scripts/check-secrets.sh` into `<base>/scripts/` and mark it executable.
/// The script does `cd "$(dirname "$0")/.."` which resolves to `<base>/`.
fn install_script(base: &Path) {
    let scripts_dir = base.join("scripts");
    fs::create_dir_all(&scripts_dir).unwrap();

    let src = workspace_root().join("scripts/check-secrets.sh");
    let dst = scripts_dir.join("check-secrets.sh");
    fs::copy(&src, &dst).unwrap_or_else(|e| panic!("copy check-secrets.sh to {dst:?}: {e}"));

    let mut perms = fs::metadata(&dst).unwrap().permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&dst, perms).unwrap();
}

/// Run the script and return its `Output` (exit status + stderr).
fn run_script(base: &Path) -> std::process::Output {
    Command::new("bash")
        .arg(base.join("scripts/check-secrets.sh"))
        .output()
        .expect("failed to spawn check-secrets.sh — is bash available?")
}

/// Write `content` to `<base>/<rel>`, creating parent directories as needed.
fn write(base: &Path, rel: &str, content: &str) {
    let p = base.join(rel);
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(&p, content).unwrap_or_else(|e| panic!("write {p:?}: {e}"));
}

// ─── check 0 — baseline: empty repo passes ───────────────────────────────────

#[test]
fn clean_dir_with_no_violations_passes() {
    let tmp = TmpDir::new("clean");
    install_script(tmp.path());

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "expected ok on a clean dir; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── check 1 — no committed Terraform state ──────────────────────────────────

#[test]
fn committed_tfstate_fails() {
    let tmp = TmpDir::new("tfstate");
    install_script(tmp.path());
    write(tmp.path(), "infra/terraform/terraform.tfstate", "{}");

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "expected failure for committed *.tfstate"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("tfstate"),
        "error message should mention tfstate; got:\n{stderr}"
    );
}

#[test]
fn committed_tfstate_backup_fails() {
    let tmp = TmpDir::new("tfstate_backup");
    install_script(tmp.path());
    write(tmp.path(), "infra/terraform/terraform.tfstate.backup", "{}");

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "*.tfstate.backup must also be rejected"
    );
}

// ─── check 2 — no committed real .env files ──────────────────────────────────

#[test]
fn committed_env_file_fails() {
    let tmp = TmpDir::new("env_file");
    install_script(tmp.path());
    write(
        tmp.path(),
        ".env",
        "DATABASE_URL=postgres://real:secret@host/db",
    );

    let out = run_script(tmp.path());
    assert!(!out.status.success(), "expected failure for committed .env");
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains(".env"),
        "error should mention .env; got:\n{stderr}"
    );
}

#[test]
fn committed_env_dev_file_fails() {
    // `.env.dev`, `.env.prod`, etc. are also real env files, not templates.
    let tmp = TmpDir::new("env_dev");
    install_script(tmp.path());
    write(
        tmp.path(),
        ".env.dev",
        "DATABASE_URL=postgres://real:secret@host/db",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        ".env.dev must be rejected as a real env file"
    );
}

#[test]
fn env_example_template_is_allowed() {
    // `.env.example` is the committed placeholder template — it must not trigger the check.
    let tmp = TmpDir::new("env_example");
    install_script(tmp.path());
    write(
        tmp.path(),
        ".env.example",
        "DATABASE_URL=placeholder_not_real",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        ".env.example must be allowed; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── check 3 — only encrypted / example files under secrets/ ─────────────────

#[test]
fn decrypted_secret_bundle_under_secrets_fails() {
    // A plain YAML (no .sops.yaml suffix) inside secrets/ is a decrypted bundle.
    let tmp = TmpDir::new("decrypted_bundle");
    install_script(tmp.path());
    write(
        tmp.path(),
        "secrets/staging/services.yaml",
        "database_url: postgres://real:LEAKED_PASSWORD@host/db\n",
    );
    // Provide .sops.yaml so check 5 doesn't also fail (isolate check 3).
    write(
        tmp.path(),
        ".sops.yaml",
        "creation_rules:\n  - path_regex: secrets/staging/\n    age: age1test\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "expected failure for a decrypted bundle under secrets/"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("unexpected") || stderr.contains("decrypted"),
        "error should mention unexpected/decrypted file; got:\n{stderr}"
    );
}

#[test]
fn encrypted_sops_bundle_is_allowed() {
    // A *.sops.yaml file under secrets/ is the SOPS-encrypted form — allowed.
    let tmp = TmpDir::new("sops_bundle");
    install_script(tmp.path());
    write(
        tmp.path(),
        "secrets/staging/services.sops.yaml",
        "env: staging\ndatabase_url: ENC[AES256_GCM,data:FAKECIPHERTEXT,iv:aaa,tag:bbb,type:str]\n",
    );
    write(
        tmp.path(),
        ".sops.yaml",
        "creation_rules:\n  - path_regex: secrets/staging/\n    age: age1test\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "encrypted SOPS bundle must be allowed; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn example_placeholder_under_secrets_is_allowed() {
    // *.sops.yaml.example are committed plaintext placeholders — allowed.
    let tmp = TmpDir::new("secrets_example");
    install_script(tmp.path());
    write(
        tmp.path(),
        "secrets/dev/services.sops.yaml.example",
        "env: dev\ndatabase_url: REPLACE_ME\n",
    );
    write(
        tmp.path(),
        ".sops.yaml",
        "creation_rules:\n  - path_regex: secrets/dev/\n    age: age1test\n",
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "*.sops.yaml.example placeholder must be allowed; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── check 4 — no committed private-key material ─────────────────────────────

#[test]
fn committed_pem_private_key_fails() {
    let tmp = TmpDir::new("pem_key");
    install_script(tmp.path());
    // Synthetic PEM block — obviously fake, but matches the grep pattern.
    write(
        tmp.path(),
        "tls/server.pem",
        "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAsyntheticnottreal\n-----END RSA PRIVATE KEY-----\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "expected failure for committed PEM private key"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("private key"),
        "error should mention 'private key'; got:\n{stderr}"
    );
}

#[test]
fn committed_ec_private_key_fails() {
    let tmp = TmpDir::new("ec_key");
    install_script(tmp.path());
    write(
        tmp.path(),
        "tls/ec.pem",
        "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEISYNTHETICKEYDATAnotreal==\n-----END EC PRIVATE KEY-----\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "EC private key block must be rejected"
    );
}

#[test]
fn committed_age_secret_key_fails() {
    let tmp = TmpDir::new("age_key");
    install_script(tmp.path());
    // AGE-SECRET-KEY-1 prefix is what `age-keygen` emits for private keys.
    write(
        tmp.path(),
        "ops/keys/dev.txt",
        "# created: 2026-01-01T00:00:00Z\n# public key: age1fakepubkeyfortest\nAGE-SECRET-KEY-1FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "expected failure for committed age secret key"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("private key"),
        "error should mention 'private key'; got:\n{stderr}"
    );
}

// ─── check 5 — .sops.yaml covers every secrets/<env>/ namespace ──────────────

#[test]
fn missing_sops_yaml_with_secrets_dir_fails() {
    // secrets/ exists but there is no .sops.yaml at the repo root.
    let tmp = TmpDir::new("no_sops_yaml");
    install_script(tmp.path());
    write(
        tmp.path(),
        "secrets/dev/services.sops.yaml.example",
        "env: dev\n",
    );
    // deliberately do NOT create .sops.yaml

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "expected failure when .sops.yaml is absent but secrets/ exists"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains(".sops.yaml"),
        "error should mention .sops.yaml; got:\n{stderr}"
    );
}

#[test]
fn sops_yaml_missing_coverage_for_env_fails() {
    // .sops.yaml exists but has no rule matching secrets/staging/.
    let tmp = TmpDir::new("sops_no_coverage");
    install_script(tmp.path());
    write(
        tmp.path(),
        "secrets/staging/services.sops.yaml.example",
        "env: staging\n",
    );
    // .sops.yaml only covers `dev`, not `staging`
    write(
        tmp.path(),
        ".sops.yaml",
        "creation_rules:\n  - path_regex: secrets/dev/\n    age: age1test\n",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "expected failure when .sops.yaml lacks a rule for secrets/staging/"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("staging"),
        "error should mention the uncovered env 'staging'; got:\n{stderr}"
    );
}

// ─── check 1 extra: non-standard tfstate extensions ─────────────────────────

#[test]
fn committed_tfstate_with_numeric_suffix_fails() {
    // `terraform.tfstate.12345` (timestamp-suffixed backups) must also be rejected.
    let tmp = TmpDir::new("tfstate_num");
    install_script(tmp.path());
    write(tmp.path(), "infra/terraform/terraform.tfstate.12345", "{}");

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "*.tfstate.12345 must be rejected as Terraform state"
    );
}

// ─── check 2 extra: env files in subdirs and with *.env suffix ───────────────

#[test]
fn committed_env_file_in_subdirectory_fails() {
    // `backend/.env` — nested env file, same danger as a root-level .env.
    let tmp = TmpDir::new("nested_env");
    install_script(tmp.path());
    write(
        tmp.path(),
        "backend/.env",
        "DATABASE_URL=postgres://real:secret@host/db",
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "committed .env in a subdirectory must be rejected"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains(".env"),
        "error should mention .env; got:\n{stderr}"
    );
}

#[test]
fn committed_dotenv_suffix_file_fails() {
    // `myservice.env` matches the `*.env` branch and must be rejected.
    let tmp = TmpDir::new("env_suffix");
    install_script(tmp.path());
    write(tmp.path(), "myservice.env", "SECRET_KEY=supersecret");

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "a file with .env suffix must be rejected as a real env file"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains(".env") || stderr.contains("myservice"),
        "error should mention the offending file; got:\n{stderr}"
    );
}

// ─── check 4 extra: OPENSSH private key (modern ssh-keygen default) ──────────

#[test]
fn committed_openssh_private_key_fails() {
    // `ssh-keygen` now defaults to OPENSSH format; the grep pattern `BEGIN [A-Z ]*PRIVATE KEY`
    // covers `BEGIN OPENSSH PRIVATE KEY` and must detect it.
    let tmp = TmpDir::new("openssh_key");
    install_script(tmp.path());
    write(
        tmp.path(),
        "deploy/keys/id_ed25519",
        concat!(
            "-----BEGIN OPENSSH PRIVATE KEY-----\n",
            "b3BlbnNzaC1rZXktdjEAAAAASYNTHETICDATAnotreal==\n",
            "-----END OPENSSH PRIVATE KEY-----\n"
        ),
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "BEGIN OPENSSH PRIVATE KEY must be detected as private key material"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("private key"),
        "error should mention 'private key'; got:\n{stderr}"
    );
}

// ─── accumulation: multiple violations are all reported ─────────────────────

#[test]
fn multiple_violations_all_reported_and_exits_nonzero() {
    // The script uses `fail=1` + `note()` to accumulate all violations before
    // exiting, so every hit should appear in stderr, not just the first.
    let tmp = TmpDir::new("multi_violation");
    install_script(tmp.path());
    // Check 1: Terraform state
    write(tmp.path(), "infra/terraform.tfstate", "{}");
    // Check 2: committed .env
    write(tmp.path(), ".env", "SECRET=leaked");
    // Check 4: PEM private key
    write(
        tmp.path(),
        "tls/key.pem",
        concat!(
            "-----BEGIN RSA PRIVATE KEY-----\n",
            "MIIEowIBAAKCAQEASYNTHETIC\n",
            "-----END RSA PRIVATE KEY-----\n"
        ),
    );

    let out = run_script(tmp.path());
    assert!(
        !out.status.success(),
        "multiple violations must cause a non-zero exit"
    );
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(
        stderr.contains("tfstate"),
        "tfstate violation not reported; stderr:\n{stderr}"
    );
    assert!(
        stderr.contains(".env"),
        ".env violation not reported; stderr:\n{stderr}"
    );
    assert!(
        stderr.contains("private key"),
        "private key violation not reported; stderr:\n{stderr}"
    );
}

// ─── scaffold tolerance: secrets/ with only a README + .sops.yaml ────────────

#[test]
fn secrets_dir_with_only_readme_and_sops_yaml_passes() {
    // Before any encrypted bundles are created, secrets/ may contain only a
    // README.md (whitelisted by check 3) and no <env>/ subdirs (check 5 loop
    // has nothing to iterate). This verifies the scaffold-tolerant design.
    let tmp = TmpDir::new("readme_only");
    install_script(tmp.path());
    write(
        tmp.path(),
        "secrets/README.md",
        "# Secrets — see ADR 0007. No encrypted bundles committed yet.\n",
    );
    // .sops.yaml must exist when secrets/ exists (check 5 requires it), but the
    // for-loop over secrets/*/ finds no subdirs, so no coverage check runs.
    write(
        tmp.path(),
        ".sops.yaml",
        concat!(
            "creation_rules:\n",
            "  - path_regex: secrets/dev/.*\\.sops\\.ya?ml$\n",
            "    age: age1aaafakerecipient\n",
        ),
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "secrets/ with only README + .sops.yaml must pass all checks; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}

// ─── combined: full valid secrets structure passes all five checks ────────────

#[test]
fn full_valid_secrets_structure_passes_all_checks() {
    let tmp = TmpDir::new("full_valid");
    install_script(tmp.path());

    write(tmp.path(), ".env.example", "DATABASE_URL=placeholder\n");
    write(tmp.path(), "secrets/README.md", "# see ADR 0007\n");
    write(
        tmp.path(),
        "secrets/dev/services.sops.yaml.example",
        "env: dev\ndatabase_url: REPLACE_ME\n",
    );
    write(
        tmp.path(),
        "secrets/staging/services.sops.yaml.example",
        "env: staging\ndatabase_url: REPLACE_ME\n",
    );
    // prod has an already-encrypted bundle (only encrypted form committed)
    write(
        tmp.path(),
        "secrets/prod/services.sops.yaml",
        "env: prod\ndatabase_url: ENC[AES256_GCM,data:FAKECIPHERTEXT,iv:aaa,tag:bbb,type:str]\n",
    );
    write(
        tmp.path(),
        ".sops.yaml",
        concat!(
            "creation_rules:\n",
            "  - path_regex: secrets/dev/.*\\.sops\\.ya?ml$\n",
            "    age: age1aaafakerecipient\n",
            "  - path_regex: secrets/staging/.*\\.sops\\.ya?ml$\n",
            "    age: age1bbbfakerecipient\n",
            "  - path_regex: secrets/prod/.*\\.sops\\.ya?ml$\n",
            "    age: age1cccfakerecipient\n",
        ),
    );

    let out = run_script(tmp.path());
    assert!(
        out.status.success(),
        "expected all five checks to pass for a valid structure; stderr:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
}
