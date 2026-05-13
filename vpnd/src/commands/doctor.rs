use anyhow::Result;
use owo_colors::OwoColorize;

use crate::cli::DoctorArgs;
use crate::config::Context;
use crate::runner::{make, Cmd};

pub async fn run(ctx: &Context, args: DoctorArgs) -> Result<()> {
    let steps: Vec<Cmd> = vec![
        make::target(ctx, "fleet-status"),
        make::target(ctx, "burn-check"),
        make::target(ctx, "asn-drift"),
        make::target(ctx, "check-ip-reputation"),
        make::target(ctx, "probing-summary"),
        make::target(ctx, "audit-permissions"),
    ];

    let mut report = String::new();
    for cmd in &steps {
        let out = cmd.capture(ctx.explain).await?;
        report.push_str(&format!("### {}\n\n```\n{}\n```\n\n", cmd.explain(), out.stdout));
    }

    if ctx.explain {
        return Ok(());
    }

    if args.ai {
        let prompt = ai_prompt(ctx, args.host.as_deref(), &report);
        if args.clip {
            try_copy_to_clipboard(&prompt)?;
            eprintln!("{}", "AI prompt copied to clipboard".green());
        } else {
            println!("{prompt}");
        }
    } else {
        println!("{}", "Doctor report".bold().underline());
        println!();
        println!("{report}");
    }
    Ok(())
}

fn ai_prompt(ctx: &Context, host: Option<&str>, report: &str) -> String {
    format!(
        r#"You are debugging a vpn-deploy host running a four-tier multi-profile VPN
stack (P0 VLESS+REALITY+Vision, P1 nginx+XHTTP direct, P2 Hysteria2 + AmneziaWG).

Context:
- env: {env}
- provider: {provider}
- host: {host}
- threat model: RU / TSPU-aware. CDN is NOT the baseline; see docs/CDN-DECISION.md.
- relevant runbooks: docs/RUNBOOK-incident.md, docs/RUNBOOK-rollback.md.

Below is the output of `vpnd doctor`. Please identify the most likely root cause,
propose the smallest safe remediation, and cite which runbook or script applies.

{report}
"#,
        env = ctx.env,
        provider = ctx.provider,
        host = host.unwrap_or("(active env)"),
    )
}

fn try_copy_to_clipboard(s: &str) -> Result<()> {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let candidates: &[&[&str]] = &[&["pbcopy"], &["wl-copy"], &["xclip", "-selection", "clipboard"], &["xsel", "-b"]];
    for cmd in candidates {
        if which::which(cmd[0]).is_ok() {
            let mut child = Command::new(cmd[0]).args(&cmd[1..]).stdin(Stdio::piped()).spawn()?;
            if let Some(stdin) = child.stdin.as_mut() {
                stdin.write_all(s.as_bytes())?;
            }
            child.wait()?;
            return Ok(());
        }
    }
    eprintln!("{} no clipboard binary found (tried pbcopy, wl-copy, xclip, xsel); printing to stdout", "note:".yellow());
    println!("{s}");
    Ok(())
}
