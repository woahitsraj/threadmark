# Threadmark for T3 Code

[![CI](https://github.com/woahitsraj/threadmark/actions/workflows/ci.yml/badge.svg)](https://github.com/woahitsraj/threadmark/actions/workflows/ci.yml)

Threadmark is a small native macOS menu-bar companion for T3 Code. It watches your paired environment and posts notifications when an agent finishes, fails, or needs attention.

## What it does

- Shows every unsettled thread, including idle, finished, and newly completed work.
- Posts native notifications for completion, failure, approval, and input states.
- Lets you reply, answer approvals, and respond to single-question pickers from notifications.
- Shows reply, approval, and structured-input controls inside the menu bar.
- Marks every unreviewed completion as read with one button.
- Checks GitHub Releases for signed updates and offers to install them.
- Defers completion while T3 reports background agents or monitoring work.
- Stores the bearer credential in macOS Keychain.
- Opens the matching thread in the native T3 Code app when you click a row or notification.
- Ignores threads that T3 has marked as settled or left inactive for its default three-day settlement window.
- Lets the menu-bar number count working threads, unreviewed Done threads, or both.
- Works with any reachable T3 endpoint, including a pairing URL routed through a T3 Connect managed tunnel, Tailscale, or Cloudflare Tunnel.

The app requests `orchestration:read` and `orchestration:operate`. It polls `/api/orchestration/shell`, then reads thread detail for pending interactions and newly finished turns. It uses the latest assistant message in notifications but does not persist message text. Replies and responses go through `/api/orchestration/dispatch` using T3's public command shapes.

The interactive grant belongs to the paired T3 client session and can be revoked in T3 Code or with `t3 auth session revoke`. Disconnecting removes Threadmark's credential from Keychain. Connections created by older Threadmark versions remain read-only until you disconnect and pair again with an interactive link.

## Build and run

Requirements: macOS 14 or newer and Xcode 26 or newer.

```sh
./scripts/build-app.sh
open "dist/Threadmark.app"
```

Move `Threadmark.app` to `/Applications` before enabling Launch at Login.

To build an installable disk image, run:

```sh
./scripts/build-dmg.sh
```

Open the resulting file in `dist`, then drag Threadmark onto the Applications shortcut.

Opening an exact desktop thread currently uses macOS Accessibility because T3 Code does not yet handle external thread deep links. Allow Threadmark in System Settings > Privacy & Security > Accessibility when prompted.

## Pair

1. In T3 Code, open Settings, then Connections.
2. Create a pairing link that grants orchestration read and operate access.
3. Open the Threadmark menu-bar item and paste the link.
4. Allow notifications when macOS asks.

The first thread click also asks for Accessibility access. T3 Code does not yet accept external thread routes, so Threadmark uses Accessibility to select the matching sidebar row in the native app. Grant access, then click the thread again.

## Done and review state

Done is a separate state managed by Threadmark. A thread becomes Done only when the app first observes it Working and later observes that work stop. Threads that were already idle when discovered do not qualify. Opening a Done thread from Threadmark marks that work reviewed and removes it from the Done count. A later Working-to-stopped transition on the same thread becomes Done again.

Pairing links contain a one-time token. The app exchanges it immediately and never persists the link itself.

## Development

```sh
swift test
swift run Threadmark
```

The transport sits behind `ActivitySource`, so a future T3 Connect aggregate-stream adapter can replace polling without changing the UI or notification logic.

macOS notification actions can host buttons and one text field, but not a multi-step form. A notification can answer one single-select question directly. Multi-select and multi-question requests open as full pickers in the menu bar.

## Releases

GitHub Actions runs the test suite and validates the disk image on every push and pull request. A new version tag builds separate Apple Silicon and Intel DMGs, signs them with Developer ID, notarizes them, creates a Sparkle appcast with signed updates and a SHA-256 manifest, then publishes a GitHub release with generated notes.

Configure release signing once using the manual checklist below. Keep the source files and passwords in 1Password, then copy their values into GitHub Actions secrets through the repository settings page.

1. Create or reuse a `Developer ID Application` certificate. Export the certificate and private key as a password-protected `.p12`, save both in 1Password, and add its single-line base64 value as `DEVELOPER_ID_P12_BASE64`.
2. Add the `.p12` password as `DEVELOPER_ID_P12_PASSWORD`. Generate a separate random password and add it as `CI_KEYCHAIN_PASSWORD`.
3. Create or reuse a team App Store Connect API key. Save the `.p8`, Key ID, and Issuer ID in 1Password. Add them as `APP_STORE_CONNECT_API_KEY_BASE64`, `APP_STORE_CONNECT_KEY_ID`, and `APP_STORE_CONNECT_ISSUER_ID`. The `.p8` value must be single-line base64.
4. Run Sparkle's pinned `generate_keys` tool with account `com.rajan.threadmark`. Save the exported private key in 1Password and add it as the `SPARKLE_PRIVATE_KEY` secret. Add the public key as the non-secret repository variable `SPARKLE_PUBLIC_ED_KEY`.
5. In GitHub, confirm all seven Actions secrets and the one Actions variable exist before creating a release tag.

Do not commit any certificate, password, API key, or Sparkle private key. GitHub only displays secret names after they are saved, so verification checks presence rather than values.

To publish a release:

1. Set `CFBundleShortVersionString` in `Resources/Info.plist` to the release version.
2. Increment `CFBundleVersion`.
3. Commit the version change.
4. Create and push the matching tag, such as `v0.2.2`.

The first Sparkle-enabled release is a manual bridge install. Later releases are discovered automatically through the `appcast.xml` asset attached to the latest GitHub release. Users can also choose Check for Updates in Threadmark settings.

## Current limits

- One paired environment at a time.
- Polls every two seconds. T3 Connect does not currently expose a supported desktop activity stream.
- Requires the T3 environment endpoint to be reachable from this Mac.
- Native thread opening requires Accessibility permission and the matching thread row to be available in T3 Code's sidebar.

## Publishing

This is an unofficial companion and is not affiliated with or endorsed by T3 Tools, Inc. T3 Code's source is MIT licensed, but its current terms reserve the T3 trademarks. Get written permission before publishing under a name that includes T3. A distinct product name with a plain compatibility statement is the safer route.
