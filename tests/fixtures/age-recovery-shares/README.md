# age-recovery-shares — test fixture

These five files are the Shamir secret shares produced by
`scripts/age-recovery-split.sh 3 5` from the **test-only** age private key
stored at `tests/fixtures/age-test.key`.

The secret reconstructed by any 3-of-5 shares is:

```
AGE-SECRET-KEY-1V070XMWMW3TKQZFQCEUK8ZV82VFRD4EG8Z7LHECG5VP7CXP7XP2QMMQY9M
```

The matching public key is:

```
age1edntzfaa5lmj9k33fyvxkm3jg3d3t659us60e8a43r5at6htaddsw88leq
```

**This key is TEST-ONLY and has never encrypted any real secrets.**
Do not use it for anything outside the test suite.

To verify reconstruction locally:

```sh
printf '%s\n%s\n%s\n' \
  "$(cat tests/fixtures/age-recovery-shares/share-1.txt | tr -d '\n')" \
  "$(cat tests/fixtures/age-recovery-shares/share-3.txt | tr -d '\n')" \
  "$(cat tests/fixtures/age-recovery-shares/share-5.txt | tr -d '\n')" \
  | ssss-combine -t 3
```

Expected output: `Resulting secret: AGE-SECRET-KEY-1V070XMWM...`
