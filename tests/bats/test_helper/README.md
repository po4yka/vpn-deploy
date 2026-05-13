# tests/bats/test_helper — vendored bats libraries

Vendored copies of bats-support and bats-assert. Update manually when a new
release is needed (low cadence expected).

## Pinned versions

| Library     | Version | Tarball SHA256                                                   | Date pinned |
|-------------|---------|------------------------------------------------------------------|-------------|
| bats-support | v0.3.0 | 7815237aafeb42ddcc1b8c698fc5808026d33317d8701d5ec2396e9634e2918f | 2026-05-13  |
| bats-assert  | v2.1.0 | 98ca3b685f8b8993e48ec057565e6e2abcc541034ed5b0e81f191505682037fd | 2026-05-13  |

## Sources

- https://github.com/bats-core/bats-support/releases/tag/v0.3.0
- https://github.com/bats-core/bats-assert/releases/tag/v2.1.0

## How to update

```sh
# Replace bats-support
curl -sSL https://github.com/bats-core/bats-support/archive/refs/tags/vX.Y.Z.tar.gz \
  -o /tmp/bats-support-X.Y.Z.tar.gz
shasum -a 256 /tmp/bats-support-X.Y.Z.tar.gz
tar -xzf /tmp/bats-support-X.Y.Z.tar.gz -C /tmp
rm -rf tests/bats/test_helper/bats-support
cp -r /tmp/bats-support-X.Y.Z tests/bats/test_helper/bats-support

# Replace bats-assert similarly, then update the version table above.
```
