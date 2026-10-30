# Khisso

Khisso is dadi's app for iPhone and Apple Watch (shown as dadi; khisso is the internal name), and the network layer that joins the phone to dadi. It is the phone's own product: the device that is always on you, and what the watch and later wearables tether to. The Mac, Windows and Linux use thaali. See the Khisso and dadi Tunnel specs.

The network layer runs dadi's Tailscale node against the box's Headscale, so the app never touches networking itself. On iOS it is the engine inside the dadi packet-tunnel extension (the OS lists it as a VPN named dadi) or, for builds signed without the Network Extension entitlement, an in-app node that only the app's own traffic uses. The watch has no node: the iPhone app relays for it. Desktops are thaali's, which runs the stock `tailscaled` itself.

## Dependencies

- Headscale on the box (the control server in each setup code).
- Tailscale `v1.82.0` (`tailscale.com`), used as a library: `ipn/ipnlocal`, `wgengine`, `ipn/store`, `wgengine/router`, and `tsnet` for the in-app node.
- MarkdownView `3.0.0` (`github.com/LiYanan2004/MarkdownView`, MIT, on swift-markdown with Highlightr and SwiftMath) renders agent messages and Markdown attachments on the iPhone: CommonMark and GitHub tables, task lists, strikethrough and autolinks, LaTeX math (`\(…\)`, `$$…$$`, `\[…\]`, and `$…$` only when it reads as LaTeX, by thaali's rule, so prices stay prices), highlighted code, links, images and SVG, matching thaali's Streamdown. The watch does not link it (it cannot typeset math there); its previews, and the drawer's, read math as Unicode, the H.264 splitter, activity wakes.
- Apple: NetworkExtension, with an app signed for the Network Extension entitlement that embeds the extension. The in-app node needs no entitlement. WatchConnectivity between the iPhone and the watch.

## Layout

```
khisso/
  internal/node/      the node on a packet-tunnel extension's utun: Start, Status
  internal/inapp/     the in-app node: tsnet, a loopback CONNECT proxy to *.dadi, MagicDNS lookups
  internal/utun/      finds the extension's utun descriptor
  cmd/dadi/           C interface, built into Dadi.xcframework
  apple/              DadiTunnel Swift package: the packet-tunnel provider
  app/                the dadi app for iPhone and its watch app (XcodeGen project.yml)
    Dadi/Types/       Hath, Yaad timeline, Ghar, Chaavi and Nas contracts
    Dadi/Shared/      API clients, Connection (setup code, in-app node), design, components, the watch link
    Dadi/Features/    Join, Home (the dock and the drawer), Dadi, Thread, Agent (the sheet behind an agent's name: status block, live browser, schedules, prompt, tools, activity), Timeline, Ghar, Chaavi, System (status, drives, helper tasks with their live screens, devices, errors), Watch (the relay)
    DadiWatch/        the watch app: Talk to Dadi, Today, Agents, Box
    DadiTests/        setup codes, errors, events, planner layout, timeline items, folders, new Chaavi items, Nas status, agent status block, math as Unicode
  scripts/            build-xcframework.sh
```

## Config vs env

There is no environment configuration.

- **Extension:** the app writes `control_url`, `hostname`, `app_group` and `keychain_group` into the VPN configuration's `providerConfiguration`; the auth key lives in the shared Keychain (service `com.dadi.tunnel`, account `auth_key`); node state is `tailscale/` in the app-group container. A missing value fails the tunnel start with its name.
- **In-app node:** `dadi_app_start` takes the same `node.Config` JSON (`control_url`, `hostname`, `auth_key`, `state_dir`) and returns the proxy port. The app points its HTTP client's CONNECT proxy at `127.0.0.1:<port>`; the proxy refuses any target that is not `*.dadi` or a `100.64.0.0/10` address.

The auth key is used only for the first login. A saved node restarts with its own key, so an expired setup code never breaks a restart.

## Local run + CI/CD

The app (iPhone and the watch it carries) joins dadi with the in-app node, so it needs no paid Apple account: a free Personal Team signs it. Setup codes carry the control URL `https://<relay hostname>`, so a device joins from any network.

```sh
./scripts/build-xcframework.sh                      # build/Dadi.xcframework, linked by the app
cp app/Signing.xcconfig.example app/Signing.xcconfig # set DEVELOPMENT_TEAM (gitignored)
(cd app && xcodegen generate && open Khisso.xcodeproj)
xcodebuild -project app/Khisso.xcodeproj -scheme Dadi -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

```sh
go test ./...
./scripts/build-xcframework.sh          # build/Dadi.xcframework
(cd apple && xcodebuild -scheme DadiTunnel -destination 'generic/platform=iOS' build)   # DadiTunnel against the local xcframework
```

| Workflow | When | What |
| --- | --- | --- |
| `ci.yml` → `ci` | PR + push to `main` | `go vet` and `go test`; build `Dadi.xcframework`; compile DadiTunnel; test the app in the iOS Simulator and build it, with the watch app, for iOS, unsigned |
| `ci.yml` → `publish` | `main` after `ci` | GitHub Release `khisso-network-<sha>` with the xcframework and its checksum |

## Logging / error codes

Every log line is JSON with `time`, `level`, `service` (`dadi`) and `msg`. The extension hands lines to the provider, which writes them to `os.Logger` under the extension's bundle ID; the app logs to `os.Logger` under `com.dadi.khisso`. Service errors reach the app as `{error: {type, message}}` and are shown with their message.
