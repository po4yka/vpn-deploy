---
name: rust-async-patterns
description: Async Rust patterns for the vpnd convenience CLI — tokio runtime, anyhow/thiserror error handling, graceful shutdown, and timeout wrappers. Use when editing vpnd/src/**, adding a new subcommand, or debugging async behaviour. vpn-deploy project variant.
---

# Rust Async Patterns (vpn-deploy)

The `vpnd` crate is a thin async CLI in front of Make / Terraform / Ansible / SOPS.
It is NOT a long-running server. Patterns here are scoped to what this binary actually does:
spawn subprocesses, render templates, snapshot-test output. Network-server patterns
(JoinSet pools, broadcast channels, connection pools) are usually wrong here.

## Project context

- Binary: `vpnd/src/main.rs` -> `vpnd/src/cli.rs` (Clap `Command` enum) -> `vpnd/src/commands/*.rs`.
- Each subcommand: `pub async fn run(ctx: &Context, args: ...) -> Result<()>`.
- Runtime: `#[tokio::main]` on `main`; single-threaded scheduler is acceptable.
- Error type: `anyhow::Result<T>` everywhere (binary). Library crates (none yet) would use `thiserror`.
- Tests: `cargo insta` snapshot tests for any subcommand that renders output (recipient page, summaries).

## Patterns that fit this repo

### Subprocess invocation (the most common pattern here)

```rust
use anyhow::{Context, Result};
use tokio::process::Command;

pub async fn run_make(ctx: &Context, target: &str) -> Result<()> {
    let status = Command::new("make")
        .arg(target)
        .current_dir(&ctx.repo_root)
        .status()
        .await
        .with_context(|| format!("failed to spawn `make {target}`"))?;

    if !status.success() {
        anyhow::bail!("make {target} exited with {status}");
    }
    Ok(())
}
```

Always `with_context` on the spawn and bail with a non-zero exit. Never `.unwrap()` outside tests.

### Timeout wrapper for external calls

Cloud-provider APIs and SSH probes hang. Wrap them.

```rust
use tokio::time::{timeout, Duration};

let result = timeout(Duration::from_secs(30), probe_node(&ip))
    .await
    .context("probe timed out")??;
```

### Graceful shutdown (when wrapping a long-running watcher)

Use `tokio::signal::ctrl_c()` + `CancellationToken`. The pattern only applies to commands that
poll something (e.g., a hypothetical `vpnd watch`). Most subcommands are short-lived.

### Streams: only for chunked output rendering

If you ever stream lines from a deploy log, use `tokio::io::BufReader` + `lines()`. Don't reach
for `futures::stream::buffer_unordered` — there is no concurrent work to batch.

## Don'ts

- **No SQL, no HTTP server, no connection pools.** This is a CLI, not a service.
- **Don't introduce `async_trait`** until there are multiple impls. We have one.
- **Don't hold a `Mutex` across an `await`** — same rule everywhere.
- **Don't `tokio::spawn` and forget** — every spawn needs a join handle or a `CancellationToken`.
- **Don't add `tracing-subscriber` defaults that log to stderr in CLI output paths** — it breaks snapshot tests.

## Snapshot tests for async output

```rust
#[tokio::test]
async fn renders_recipient_page() {
    let html = render_recipient(&fixture()).await.unwrap();
    insta::assert_snapshot!(html);
}
```

Run with `cargo insta review` before committing. Snapshot files live in `vpnd/src/snapshots/`.

## See also

- `vpnd/CLAUDE.md` — architectural decisions for the crate
- `[[rust-best-practices]]` — borrowing, error handling, clippy gates
