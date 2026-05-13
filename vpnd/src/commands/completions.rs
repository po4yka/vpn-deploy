use anyhow::{bail, Result};
use clap::CommandFactory;
use clap_complete::{generate, shells};

use crate::cli::{Cli, CompletionsArgs};

pub fn run(args: CompletionsArgs) -> Result<()> {
    let mut cmd = Cli::command();
    let shell = args.shell.to_ascii_lowercase();
    let mut out = std::io::stdout();
    match shell.as_str() {
        "bash" => generate(shells::Bash, &mut cmd, "vpnd", &mut out),
        "zsh" => generate(shells::Zsh, &mut cmd, "vpnd", &mut out),
        "fish" => generate(shells::Fish, &mut cmd, "vpnd", &mut out),
        "powershell" | "pwsh" => generate(shells::PowerShell, &mut cmd, "vpnd", &mut out),
        other => bail!(
            "unknown shell '{}'; supported: bash, zsh, fish, powershell",
            other
        ),
    }
    Ok(())
}
