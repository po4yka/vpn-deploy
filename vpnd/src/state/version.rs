use owo_colors::OwoColorize;

use crate::state::Host;

/// Compare the CLI's compiled version against a host's last-deployed version.
/// Warn-once-per-invocation (no persistence — re-warn each session is fine for v1).
pub fn warn_on_skew(name: &str, host: &Host) {
    let cli = env!("CARGO_PKG_VERSION");
    if let Some(deployed) = &host.deployed_with {
        if deployed != cli {
            eprintln!(
                "{} host '{}' was deployed with vpnd {}; current CLI is {}",
                "warning:".yellow().bold(),
                name,
                deployed,
                cli
            );
        }
    }
}
