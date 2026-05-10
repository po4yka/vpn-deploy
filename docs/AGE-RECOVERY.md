# age key recovery — Shamir split

The single point of failure in the SOPS+age model is the operator's age
private key. Lose it → see `RUNBOOK-incident.md § Lost age key` — the only
recovery is full credential rotation.

For team or solo-with-redundancy setups, split the age private key into
k-of-n Shamir shares so any **k** shares can reconstruct it, but fewer
than k cannot.

## When to use

- **Solo operator, paranoid:** 2-of-3 across (1Password Documents),
  (sealed envelope in a fire-proof safe), (Bitwarden Send to a trusted
  family member).
- **Two operators:** 2-of-3 where each operator holds one share and the
  third lives in shared escrow (1Password Shared Vault, Vaultwarden).
- **Three operators on call rotation:** 2-of-4 — each operator one share,
  one in escrow. Any two operators can recover.

## Prerequisites

- `ssss` (Shamir Secret Sharing Scheme):
  - macOS: `brew install ssss`
  - Debian/Ubuntu: `apt install ssss`

The `ssss` tool is purpose-built; it splits a secret string of up to 128
characters into n shares with threshold t.

## Initial split

```bash
# Generate age key normally if you haven't yet
age-keygen -o ~/.config/vpn-provision/age.key
chmod 0600 ~/.config/vpn-provision/age.key

# Split 2-of-3
./scripts/age-recovery-split.sh 2 3
```

The script prints n shares — each line starts with a number and a dash:

```
1-12abc...
2-34def...
3-56789...
```

Distribute one share per storage location. Never put two shares in the
same location.

## Test recovery before you need it

```bash
# Pretend you've lost the original. Pick any 2 shares and reconstruct.
./scripts/age-recovery-combine.sh 2 > /tmp/recovered-age.key
chmod 0600 /tmp/recovered-age.key

# Verify it decrypts the SOPS file
SOPS_AGE_KEY_FILE=/tmp/recovered-age.key sops --decrypt \
  ~/.config/vpn-provision/prod.secrets.sops.yaml > /dev/null && echo OK

# Wipe the temp copy
shred -u /tmp/recovered-age.key
```

If `OK` did not print, the shares are bad — re-split before relying on
this.

## Storage discipline

- **Each share goes to a different storage system.** Two shares in
  1Password = effective 1-of-1 because anyone with 1Password access has
  both. The point is failure-mode independence.
- **Encrypted at rest.** Sealed envelope in a safe is fine; sticky note on
  monitor is not.
- **Authenticated retrieval.** A 1Password vault with weak MFA defeats
  the share. Use hardware-key MFA on every storage.
- **Track the threshold.** Lose more than (n-t) shares and recovery is
  impossible.

## Rotating the age key

When the age key itself is rotated (because a share was compromised, or
recipients changed):

1. Generate a new age keypair: `age-keygen -o ~/.config/vpn-provision/age.key.new`.
2. Re-encrypt the SOPS file under the new recipient: `sops updatekeys`
   pointing to the new public key.
3. Split the new private key with `age-recovery-split.sh`.
4. Distribute fresh shares; revoke old ones from their storage.
5. Delete the old age key and any old shares.

## What NOT to do

- Don't email shares.
- Don't paste shares into chat.
- Don't store all shares in a single password manager.
- Don't reduce the threshold below 2 — single-share recovery is no
  better than not splitting at all.
