use crate::config::Context;
use crate::runner::Cmd;

/// Build a `make <name> ENV=… PROVIDER=…` invocation pinned to the repo root.
pub fn target(ctx: &Context, name: &str) -> Cmd {
    Cmd::new("make")
        .arg(name)
        .arg(format!("ENV={}", ctx.env))
        .arg(format!("PROVIDER={}", ctx.provider))
        .cwd(ctx.root.clone())
        .describe(format!("make {} ENV={} PROVIDER={}", name, ctx.env, ctx.provider))
}

/// Build a `make` target with additional `KEY=VALUE` args appended.
pub fn target_with(ctx: &Context, name: &str, kvs: &[(&str, &str)]) -> Cmd {
    let mut cmd = target(ctx, name);
    for (k, v) in kvs {
        cmd = cmd.arg(format!("{}={}", k, v));
    }
    cmd
}
