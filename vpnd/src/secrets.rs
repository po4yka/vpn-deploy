use anyhow::{anyhow, Context as _, Result};
use serde::Deserialize;
use std::path::Path;

/// Minimal typed view of the SOPS-decrypted payload at `/tmp/vpn-<env>.secrets.yaml`.
///
/// This is read-only and intentionally tolerant: unknown keys are preserved as raw YAML
/// so the schema lives in `scripts/validate-secrets.py`, not here.
#[derive(Debug, Deserialize)]
pub struct Secrets {
    #[serde(default)]
    pub clients: Vec<Client>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub xhttp_host: Option<String>,
    #[serde(flatten)]
    pub _extra: serde_yaml::Mapping,
}

#[allow(dead_code)] // uuid and short_id are deserialized but not yet consumed; Phase 2 share-bundle expansion will read them to construct per-client VLESS URIs
#[derive(Debug, Deserialize, Clone)]
pub struct Client {
    pub name: String,
    #[serde(default)]
    pub uuid: Option<String>,
    #[serde(default)]
    pub short_id: Option<String>,
    #[serde(flatten)]
    pub _extra: serde_yaml::Mapping,
}

impl Secrets {
    pub fn load(path: &Path) -> Result<Self> {
        if !path.is_file() {
            return Err(anyhow!(
                "decrypted secrets not found at {} — run `vpnd ... ` (which will call `make decrypt`)",
                path.display()
            ));
        }
        let bytes = std::fs::read(path).with_context(|| format!("read {}", path.display()))?;
        let s: Secrets = serde_yaml::from_slice(&bytes).context("parse decrypted secrets YAML")?;
        Ok(s)
    }

    pub fn find_client(&self, name: &str) -> Option<&Client> {
        self.clients.iter().find(|c| c.name == name)
    }
}
