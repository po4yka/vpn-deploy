#![allow(dead_code)] // builders intentionally kept for future commands and tests

use crate::config::Context;
use crate::runner::Cmd;

pub fn init(ctx: &Context) -> Cmd {
    Cmd::new("terraform")
        .arg("-chdir")
        .arg(ctx.tf_root.to_string_lossy().to_string())
        .arg("init")
        .describe(format!("terraform init in {}", ctx.tf_root.display()))
}

pub fn plan(ctx: &Context) -> Cmd {
    let tfvars = format!("environments/{}.tfvars", ctx.env);
    let tfplan = format!("{}.tfplan", ctx.env);
    Cmd::new("terraform")
        .arg(format!("-chdir={}", ctx.tf_root.display()))
        .arg("plan")
        .arg(format!("-var-file={}", tfvars))
        .arg(format!("-out={}", tfplan))
        .describe(format!("terraform plan -out={}", tfplan))
}

pub fn apply(ctx: &Context) -> Cmd {
    let tfplan = format!("{}.tfplan", ctx.env);
    Cmd::new("terraform")
        .arg(format!("-chdir={}", ctx.tf_root.display()))
        .arg("apply")
        .arg(tfplan.clone())
        .describe(format!("terraform apply {}", tfplan))
}

pub fn output(ctx: &Context) -> Cmd {
    Cmd::new("terraform")
        .arg(format!("-chdir={}", ctx.tf_root.display()))
        .arg("output")
        .arg("-json")
        .describe("terraform output -json")
}
