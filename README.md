# Threadmark for T3 Code

[![CI](https://github.com/woahitsraj/threadmark/actions/workflows/ci.yml/badge.svg)](https://github.com/woahitsraj/threadmark/actions/workflows/ci.yml)

Threadmark is a small native macOS menu-bar companion for T3 Code. It watches your paired environment and posts notifications when an agent finishes, fails, or needs attention.

## What it does

- Shows every unsettled thread, including idle, finished, and newly completed work.
- Posts native notifications for completion, failure, approval, and input states.
- Defers completion while T3 reports background agents or monitoring work.
- Stores the bearer credential in macOS Keychain.
- Opens the matching thread in the native T3 Code app when you click a row or notification.
- Ignores threads that T3 has marked as settled or left inactive for its default three-day settlement window.
- Lets the menu-bar number count working threads, unreviewed Done threads, or both.
- Works with any reachable T3 endpoint, including a pairing URL routed through a T3 Connect managed tunnel, Tailscale, or Cloudflare Tunnel.

The app reads only `/api/orchestration/shell` with the `orchestration:read` scope. It does not read messages or final responses.

## Build and run

Requirements: macOS 14 or newer and Xcode 26 or newer.

```sh
./scripts/build-app.sh
open "dist/Threadmark.app"
```

Move `Threadmark.app` to `/Applications` before enabling Launch at Login.

Opening an exact desktop thread currently uses macOS Accessibility because T3 Code does not yet handle external thread deep links. Allow Threadmark in System Settings > Privacy & Security > Accessibility when prompted.

## Pair

1. In T3 Code, open Settings, then Connections.
2. Create or copy a pairing link for the environment you want to monitor.
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

## Releases

GitHub Actions runs the test suite and validates the app bundle on every push and pull request. Version tags build separate Apple Silicon and Intel archives, create a SHA-256 manifest, and publish a GitHub release with generated notes.

To publish a release:

1. Set `CFBundleShortVersionString` in `Resources/Info.plist` to the release version.
2. Commit the version change.
3. Create and push the matching tag, such as `v0.1.0`.

If GitHub delays the tag event, open the Release workflow in Actions, choose Run workflow, and enter the existing tag.

Release builds are ad hoc signed but not notarized. Public distribution without macOS security warnings requires an Apple Developer ID certificate and notarization credentials.

## Current limits

- One paired environment at a time.
- Polls every two seconds. T3 Connect does not currently expose a supported desktop activity stream.
- Requires the T3 environment endpoint to be reachable from this Mac.
- Native thread opening requires Accessibility permission and the matching thread row to be available in T3 Code's sidebar.

## Publishing

This is an unofficial companion and is not affiliated with or endorsed by T3 Tools, Inc. T3 Code's source is MIT licensed, but its current terms reserve the T3 trademarks. Get written permission before publishing under a name that includes T3. A distinct product name with a plain compatibility statement is the safer route.
