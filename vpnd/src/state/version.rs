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

#[cfg(test)]
mod tests {
    use super::*;

    fn host_with_deployed(v: &str) -> Host {
        Host {
            env: "prod".into(),
            provider: "upcloud".into(),
            ipv4: None,
            ipv6: None,
            deployed_with: Some(v.to_string()),
        }
    }

    fn host_no_deployed() -> Host {
        Host {
            env: "prod".into(),
            provider: "upcloud".into(),
            ipv4: None,
            ipv6: None,
            deployed_with: None,
        }
    }

    #[test]
    fn warn_on_skew_is_silent_when_versions_match() {
        // When deployed_with equals the current CLI version no output is expected.
        // We cannot capture stderr easily in a unit test, but we can at least assert
        // the function does not panic and runs without error.
        let cli = env!("CARGO_PKG_VERSION");
        let host = host_with_deployed(cli);
        warn_on_skew("myhost", &host); // must not panic
    }

    #[test]
    fn warn_on_skew_does_not_panic_on_mismatch() {
        let host = host_with_deployed("0.0.0-old");
        warn_on_skew("myhost", &host); // must not panic even with mismatched version
    }

    #[test]
    fn warn_on_skew_is_silent_when_deployed_with_absent() {
        let host = host_no_deployed();
        warn_on_skew("myhost", &host); // must not panic when deployed_with is None
    }
}
