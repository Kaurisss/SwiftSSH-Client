# Upstream provenance

- Repository: https://github.com/nirasnet/mssh
- Baseline commit: `e5a2063f704bd217aef063f8592b8b159a8511dd`
- Original license: MIT, copyright (c) 2026 M4ck Jsd (nirasnet).
- Original LICENSE is preserved unchanged.
- Fork: https://github.com/Kaurisss/SwiftSSH-Client (private), default branch `main`.

## This iteration

Prepare an iOS-only, local-storage development baseline called SwiftSSH.
Keep the existing host management, SSH/PTY terminal, key management and SFTP.
Use a new placeholder Bundle ID and Keychain namespace; no original-app data migration.

Replace destructive startup recovery with a throwing local store and an error/retry
screen. Remove automatic cloud access, sync UI and credential sync paths from the
active app. Exclude original monetization and unimplemented forwarding UI/runtime.
Keep the original five-model schema.

The upstream Xcode project, macOS/cloud-only files and store/release material remain
as reference, not supported build entrypoints. Generate the fork project from project.yml.
The MIT license does not require adopting the original author's developer signing identity.

## Verification boundary

Windows verification covers configuration invariants, Swift syntax parsing and shell
syntax/failure propagation. It does not run Swift type checking, XcodeGen generation,
iOS unit tests, code signing or SSH/SFTP device integration. Use build.sh on a Mac
and the smoke checklist in README.md for those checks.
