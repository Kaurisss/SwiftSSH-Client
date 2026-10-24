# SwiftSSH development notes

This fork targets iPhone/iPad only (iOS 18+), based on nirasnet/mssh.
See README.md and UPSTREAM.md. Keep LICENSE and the upstream copyright.

## Build

- `project.yml` is the source of truth. Run `xcodegen generate` on macOS before building.
- Open `SwiftSSH.xcodeproj`, scheme `SwiftSSH`; do not use the upstream `mssh.xcodeproj`.
- Never manually edit generated project.pbxproj or Info.plist.
- `DESTINATION='platform=iOS Simulator,name=iPhone 16' bash build.sh` generates and runs tests.
- `python scripts/check_baseline.py` is a source/configuration self-check, not a Swift compiler.
- Windows cannot execute Xcode, SwiftData or device Keychain tests.
- Set a unique Bundle ID and your own Team before installing on a device.
- No CloudKit/iCloud Keychain capability or App Store product configuration is required.

## Boundaries

The active target excludes the upstream macOS UI, automatic imports, cloud services,
tip jar and placeholder port forwarding. Original distribution scripts and store
metadata are reference material only. No macOS target is generated.

Do not re-enable sync by changing a UserDefaults default: the upstream password
save path also wrote to iCloud Keychain regardless of that flag. Current credentials
use device-only storage, and the cloud save APIs have been removed.

LocalStore.open(at:) throws on failure. Show the error and allow retry; never
delete SQLite/WAL/SHM files or fall back to a writable in-memory database.

Retain all five upstream model types in the local schema to avoid unnecessary
schema changes. PortForward and SSHKey.syncAcrossDevices remain as inert metadata.

SSH/terminal behavior stays in the existing Services/ViewModels/Terminal layers.
Keep the serialized terminal AsyncStream writer, host-key reject-on-disconnect,
and meaningful terminal error messages. Do not replace them with per-key Tasks.

Citadel 0.12.1 fixes the handshake deadline at 10 seconds. Keep host-key approval
outside the timed handshake, then reconnect with the exact approved key pinned.
Ignore duplicate PTY close only after output handling finishes; retain setup and
output errors. Each connection attempt owns its client, prompt and write stream.
