# Quickstart — zero to working VPN in ~30 minutes

This walks through deploying the full P0+P1+P2 stack to a single UpCloud VPS.
All commands run from your operator workstation; you should never SSH the
target VPS by hand for routine setup.

## 0. Prerequisites

```
terraform >= 1.13
ansible-core >= 2.19
sops, age, gitleaks, jq, openssl
ssh, terraform-cli, upctl (UpCloud CLI, optional but useful)
A domain you control with DNS (for nginx-xhttp + Hysteria TLS)
A public certificate for that domain (Let's Encrypt is fine; not bundled)
```

Verify in one shot:

```bash
make check-prereqs
```

## 1. Provider credentials

UpCloud authenticates via env vars. Use a sub-account, not the master:

```bash
export UPCLOUD_USERNAME='vpn-deploy'
export UPCLOUD_PASSWORD='…'
```

Putting these in a shell login file (`.zshenv`) is fine; they must NEVER
appear in `*.tfvars`, in Terraform state, or in this repo.

## 2. Generate keys

```bash
mkdir -p ~/.config/vpn-provision

# 2a. age keypair (one-time)
age-keygen -o ~/.config/vpn-provision/age.key
RECIPIENT=$(grep '^# public key:' ~/.config/vpn-provision/age.key | awk '{print $4}')
echo "age recipient: $RECIPIENT"

# 2b. operator SSH key for the VPS (separate from your daily SSH key)
ssh-keygen -t ed25519 -f ~/.ssh/vpn_deploy -N '' -C 'vpn-deploy operator'
export ANSIBLE_SSH_PRIVATE_KEY_FILE=~/.ssh/vpn_deploy

# 2c. REALITY keypair (one-time per server)
docker run --rm ghcr.io/xtls/xray-core x25519
# or, if Xray is locally installed: xray x25519
```

Record the REALITY private key for the secrets file (next step) and the
public key for client URIs.

## 3. Fill out the Terraform vars

```bash
cd ~/GitRep/vpn-deploy
cp terraform/providers/upcloud/environments/prod.tfvars.example \
   terraform/providers/upcloud/environments/prod.tfvars
$EDITOR terraform/providers/upcloud/environments/prod.tfvars
```

Required: `zone`, `plan`, `storage_template`, `admin_ssh_public_key`
(paste content of `~/.ssh/vpn_deploy.pub`), `allowed_ssh_cidrs` (your
operator IP, **never** `0.0.0.0/0`).

Find a current Debian 13 / Ubuntu 24.04 template UUID:

```bash
upctl storage list --public --template | grep -E 'Debian 13|Ubuntu 24.04'
```

## 4. Fill out the secrets file

```bash
cp secrets/prod.secrets.example.yaml ~/.config/vpn-provision/prod.secrets.yaml
$EDITOR ~/.config/vpn-provision/prod.secrets.yaml
```

Fill: Xray version + sha256 (from the GitHub release page), REALITY keypair
from step 2c, target+server_names (see `reality-target-selection-2026`),
nginx_xhttp cert/key (your public CA cert for `vpn.example.com`), Hysteria
version + sha256, AmneziaWG H1–H4 obfuscation params, restic password.

Add your first device:

```bash
SOPS_FILE=~/.config/vpn-provision/prod.secrets.yaml \
./scripts/new-client.sh phone
```

## 5. Encrypt the secrets file

```bash
sops --encrypt --age "$RECIPIENT" \
  ~/.config/vpn-provision/prod.secrets.yaml \
  > ~/.config/vpn-provision/prod.secrets.sops.yaml

shred -u ~/.config/vpn-provision/prod.secrets.yaml
```

From now on edit only the encrypted file: `sops ~/.config/vpn-provision/prod.secrets.sops.yaml`.

## 6. Deploy

```bash
make init
make validate          # must pass before continuing
make decrypt           # writes /tmp/vpn-prod.secrets.yaml
make plan
make apply
make inventory
make wait              # 30–120 s, waits for cloud-init
make dry-run           # ansible --check --diff; review what will change
make deploy            # real run
make verify            # post-deploy gates
make clean             # shred /tmp/vpn-prod.secrets.yaml
```

If `dry-run` shows changes you didn't expect, stop and investigate. Don't
proceed to `deploy`.

## 7. Generate a client config

```bash
SOPS_FILE=~/.config/vpn-provision/prod.secrets.sops.yaml \
./scripts/new-client.sh --emit-uri laptop
```

Replace the `<SERVER_IP>`, `<SNI>`, `<REALITY_PUBLIC_KEY>` placeholders in
the printed URIs with values from your tfvars and secrets file. Import the
URIs into sing-box / NekoBox / v2rayNG / husi.

For AmneziaWG, the script also prints a private key — hand it to the
device through a secure channel and put it on the device, then forget it.

## 8. External health check

```bash
SNI_TARGET=www.cloudflare.com \
HTTP_HOST=vpn.example.com \
./scripts/healthcheck.sh
```

Then connect with the real client and run a real-life traffic test (curl
through the tunnel; speedtest if useful).

## What's next

- `docs/RUNBOOK-rotate.md` — rotate UUIDs / shortIds / peer keys
- `docs/RUNBOOK-rollback.md` — config rollback, binary rollback, blue-green
- `docs/RUNBOOK-incident.md` — IP burned / key leaked / panel exposed
- `docs/RUNBOOK-restore.md` — restore from restic backup after host loss
- `docs/RUNBOOK-add-fallback.md` — add a second VPS in a different ASN

Read `docs/CDN-DECISION.md` before you reach for Cloudflare.
