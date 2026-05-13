use anyhow::{anyhow, Context as _, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

/// Local-only host registry, persisted at `~/.config/vpn-provision/hosts.toml`.
///
/// Modeled after Meridian's per-server registry: the operator names a host once,
/// and every `vpnd <cmd> --host <name>` resolves to the same env/provider/IP.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Registry {
    #[serde(default)]
    pub hosts: BTreeMap<String, Host>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Host {
    pub env: String,
    pub provider: String,
    #[serde(default)]
    pub ipv4: Option<String>,
    #[serde(default)]
    pub ipv6: Option<String>,
    #[serde(default)]
    pub deployed_with: Option<String>,
}

impl Registry {
    pub fn path() -> Result<PathBuf> {
        let base = directories::BaseDirs::new().ok_or_else(|| anyhow!("no user config dir"))?;
        Ok(base.config_dir().join("vpn-provision").join("hosts.toml"))
    }

    pub fn load() -> Result<Self> {
        let p = Self::path()?;
        if !p.is_file() {
            return Ok(Self::default());
        }
        let s = std::fs::read_to_string(&p).with_context(|| format!("read {}", p.display()))?;
        toml::from_str(&s).with_context(|| format!("parse {}", p.display()))
    }

    pub fn save(&self) -> Result<()> {
        let p = Self::path()?;
        if let Some(dir) = p.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let s = toml::to_string_pretty(self)?;
        std::fs::write(&p, s).with_context(|| format!("write {}", p.display()))?;
        Ok(())
    }

    pub fn upsert(&mut self, name: &str, host: Host) {
        self.hosts.insert(name.to_string(), host);
    }

    pub fn remove(&mut self, name: &str) -> Option<Host> {
        self.hosts.remove(name)
    }

    pub fn get(&self, name: &str) -> Option<&Host> {
        self.hosts.get(name)
    }
}
