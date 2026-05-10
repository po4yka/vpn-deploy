# secrets/

**Real secrets do NOT live in this directory.** They live outside the repo,
under `~/.config/vpn-provision/`, encrypted with SOPS + age.

This directory only holds:

- `prod.secrets.example.yaml` — placeholder structure showing every field the
  Ansible roles will look up. Copy it to `~/.config/vpn-provision/prod.secrets.yaml`,
  fill in real values, then `sops --encrypt` it.
- `.gitkeep` — keeps the empty dir in git.
- This README.

The `.gitignore` excludes everything else under `secrets/` to make accidental
commits hard.

## Workflow

```bash
mkdir -p ~/.config/vpn-provision
cp secrets/prod.secrets.example.yaml ~/.config/vpn-provision/prod.secrets.yaml

# Generate an age keypair (one-time)
age-keygen -o ~/.config/vpn-provision/age.key
# Public recipient is printed at the top of age.key (line "# public key: age1...")
RECIPIENT=$(grep '^# public key:' ~/.config/vpn-provision/age.key | awk '{print $4}')

# Edit ~/.config/vpn-provision/prod.secrets.yaml in your editor.

# Encrypt
sops --encrypt --age "$RECIPIENT" \
  ~/.config/vpn-provision/prod.secrets.yaml \
  > ~/.config/vpn-provision/prod.secrets.sops.yaml

# Wipe plaintext
shred -u ~/.config/vpn-provision/prod.secrets.yaml || rm -f ~/.config/vpn-provision/prod.secrets.yaml
```

For day-to-day editing of an already-encrypted file, use `sops <file>` —
it decrypts to a temp file, opens your $EDITOR, re-encrypts on save, and
never writes plaintext to disk.

See `docs/SECRETS.md` for the full lifecycle, recovery, and rotation
procedure.
