use anyhow::{anyhow, Result};
use owo_colors::OwoColorize;
use std::ffi::OsString;
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

/// Fluent builder for an external process invocation.
///
/// The shape mirrors `tokio::process::Command` but carries a human-readable
/// description and supports `--explain` (print-don't-run).
#[derive(Debug, Clone)]
pub struct Cmd {
    program: String,
    args: Vec<OsString>,
    env: Vec<(String, String)>,
    cwd: Option<PathBuf>,
    description: Option<String>,
}

impl Cmd {
    pub fn new(program: impl Into<String>) -> Self {
        Self {
            program: program.into(),
            args: Vec::new(),
            env: Vec::new(),
            cwd: None,
            description: None,
        }
    }

    pub fn arg(mut self, a: impl Into<OsString>) -> Self {
        self.args.push(a.into());
        self
    }

    #[allow(dead_code)] // bulk-arg helper, used by future commands
    pub fn args<I, S>(mut self, items: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<OsString>,
    {
        self.args.extend(items.into_iter().map(Into::into));
        self
    }

    pub fn env(mut self, k: impl Into<String>, v: impl Into<String>) -> Self {
        self.env.push((k.into(), v.into()));
        self
    }

    pub fn cwd(mut self, p: PathBuf) -> Self {
        self.cwd = Some(p);
        self
    }

    pub fn describe(mut self, d: impl Into<String>) -> Self {
        self.description = Some(d.into());
        self
    }

    /// Shell-quoted form suitable for `--explain` output.
    pub fn explain(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        for (k, v) in &self.env {
            parts.push(format!("{}={}", k, shell_words::quote(v)));
        }
        parts.push(shell_words::quote(&self.program).into_owned());
        for a in &self.args {
            parts.push(shell_words::quote(&a.to_string_lossy()).into_owned());
        }
        let mut s = parts.join(" ");
        if let Some(cwd) = &self.cwd {
            s = format!("(cd {} && {})", shell_words::quote(&cwd.to_string_lossy()), s);
        }
        s
    }

    /// Print to stderr in the `--explain` style. Always called for the `--explain` flag,
    /// and useful as a status line in interactive runs.
    pub fn print_explain(&self) {
        if let Some(d) = &self.description {
            eprintln!("{} {}", "→".cyan(), d.bold());
        }
        eprintln!("  {} {}", "$".dimmed(), self.explain().dimmed());
    }

    /// Run interactively, streaming stdout/stderr to the parent terminal.
    pub async fn run(&self, explain_only: bool) -> Result<i32> {
        self.print_explain();
        if explain_only {
            return Ok(0);
        }

        let mut cmd = Command::new(&self.program);
        cmd.args(self.args.iter());
        for (k, v) in &self.env {
            cmd.env(k, v);
        }
        if let Some(cwd) = &self.cwd {
            cmd.current_dir(cwd);
        }
        let status = cmd.status().await?;
        let rc = status.code().unwrap_or(-1);
        if !status.success() {
            return Err(anyhow!(
                "command failed (rc={}): {}",
                rc,
                self.description.as_deref().unwrap_or(&self.program)
            ));
        }
        Ok(rc)
    }

    /// Run capturing stdout, returning it as a String. Stderr is streamed to the terminal.
    pub async fn capture(&self, explain_only: bool) -> Result<Output> {
        self.print_explain();
        if explain_only {
            return Ok(Output { rc: 0, stdout: String::new() });
        }

        let mut cmd = Command::new(&self.program);
        cmd.args(self.args.iter()).stdout(Stdio::piped()).stderr(Stdio::inherit());
        for (k, v) in &self.env {
            cmd.env(k, v);
        }
        if let Some(cwd) = &self.cwd {
            cmd.current_dir(cwd);
        }
        let mut child = cmd.spawn()?;
        let stdout = child.stdout.take().ok_or_else(|| anyhow!("no stdout"))?;
        let mut buf = String::new();
        let mut reader = BufReader::new(stdout).lines();
        while let Some(line) = reader.next_line().await? {
            buf.push_str(&line);
            buf.push('\n');
        }
        let status = child.wait().await?;
        let rc = status.code().unwrap_or(-1);
        if !status.success() {
            return Err(anyhow!(
                "command failed (rc={}): {}",
                rc,
                self.description.as_deref().unwrap_or(&self.program)
            ));
        }
        Ok(Output { rc, stdout: buf })
    }
}

#[allow(dead_code)] // rc surfaced for callers that distinguish 0 vs non-zero with --explain semantics
#[derive(Debug)]
pub struct Output {
    pub rc: i32,
    pub stdout: String,
}
