#![allow(dead_code)] // builders intentionally kept for future commands and tests

use crate::config::Context;
use crate::runner::Cmd;

/// Builder for `ansible-playbook playbooks/<name>.yml` pinned to the repo's ansible config.
pub fn playbook(ctx: &Context, name: &str) -> Cmd {
    let path = ctx.ansible_dir.join("playbooks").join(format!("{name}.yml"));
    Cmd::new("ansible-playbook")
        .arg(path.to_string_lossy().to_string())
        .env("ANSIBLE_CONFIG", ctx.ansible_cfg().to_string_lossy().to_string())
        .env("VPN_SECRETS_FILE", ctx.secrets_file.to_string_lossy().to_string())
        .describe(format!("ansible-playbook playbooks/{name}.yml"))
}

pub fn site(ctx: &Context) -> Cmd {
    playbook(ctx, "site")
}

pub fn verify(ctx: &Context) -> Cmd {
    playbook(ctx, "verify")
}

pub fn smoke(ctx: &Context) -> Cmd {
    playbook(ctx, "smoke-test")
}

pub fn rotate(ctx: &Context) -> Cmd {
    playbook(ctx, "rotate-credentials")
}

pub fn dry_run(ctx: &Context) -> Cmd {
    site(ctx).arg("--check").arg("--diff").describe("ansible-playbook site.yml --check --diff")
}
