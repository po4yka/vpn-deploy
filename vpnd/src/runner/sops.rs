#![allow(dead_code)] // exposed for future commands that decrypt outside `make decrypt`

use crate::config::Context;
use crate::runner::Cmd;

/// `sops --decrypt <sops_file> > <secrets_file>`
///
/// `sops` writes to stdout when no `--output` is given. The wrapper here uses
/// `--output` so we don't need a shell redirection — keeps `--explain` honest.
pub fn decrypt(ctx: &Context) -> Cmd {
    Cmd::new("sops")
        .arg("--decrypt")
        .arg("--output")
        .arg(ctx.secrets_file.to_string_lossy().to_string())
        .arg(ctx.sops_file.to_string_lossy().to_string())
        .describe(format!("sops --decrypt → {}", ctx.secrets_file.display()))
}
