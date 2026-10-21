# Khisso

Khisso is dadi's Apple app for iPhone, Mac and Apple Watch (shown as dadi; khisso is the internal name), and the network layer that joins those devices to dadi. See the Khisso and dadi Tunnel specs.

The network layer runs dadi's Tailscale node against the box's Headscale, so the app never touches networking itself. On macOS and iOS it is the engine inside the dadi packet-tunnel extension (the OS lists it as a VPN named dadi) or, for builds signed without the Network Extension entitlement, an in-app node that only the app's own traffic uses. The watch has no node: the iPhone app relays for it. Windows and Linux are thaali's, which runs the stock `tailscaled` itself.

## Dependencies

- Headscale on the box (the control server in each setup code).
- Tailscale `v1.82.0` (`tailscale.com`), used as a library: `ipn/ipnlocal`, `wgengine`, `ipn/store`, `wgengine/router`, and `tsnet` for the in-app node.
- Apple: NetworkExtension, with an app signed for the Network Extension entitlement that embeds the extension. The in-app node needs no entitlement. WatchConnectivity between the iPhone and the watch.

## Layout

```
khisso/
  internal/node/      the node on a packet-tunnel extension's utun: Start, Status
  internal/inapp/     the in-app node: tsnet, a loopback CONNECT proxy to *.dadi, MagicDNS lookups
  internal/utun/      finds the extension's utun descriptor (macOS, iOS)
  cmd/dadi/           C interface, built into Dadi.xcframework
  apple/              DadiTunnel Swift package: the packet-tunnel provider
  app/                the dadi app (XcodeGen project.yml)
    Dadi/Types/       Hath, Yaad, planner, Ghar, Chaavi and Nas contracts
    Dadi/Shared/      API clients, Connection (setup code, in-app node), design, components, the watch link
    Dadi/Features/    Join, Home (iPhone drawer, Mac sidebar and tiles), Dadi, Thread, Timeline, Ghar,
                      Chaavi, System, Agents and Memory (Mac), Watch (the iPhone's relay)
    DadiWatch/        the watch app: Talk to Dadi, Today, Agents, Box
    DadiTests/        setup codes, errors, events, planner, folders, force layout, Nas status
  scripts/            build-xcframework.sh
```

## Config vs env

There is no environment configuration.

- **Extension:** the app writes `control_url`, `hostname`, `app_group` and `keychain_group` into the VPN configuration's `providerConfiguration`; the auth key lives in the shared Keychain (service `com.dadi.tunnel`, account `auth_key`); node state is `tailscale/` in the app-group container. A missing value fails the tunnel start with its name.
- **In-app node:** `dadi_app_start` takes the same `node.Config` JSON (`control_url`, `hostname`, `auth_key`, `state_dir`) and returns the proxy port. The app points its HTTP client's CONNECT proxy at `127.0.0.1:<port>`; the proxy refuses any target that is not `*.dadi` or a `100.64.0.0/10` address.

The auth key is used only for the first login. A saved node restarts with its own key, so an expired setup code never breaks a restart.

## Local run + CI/CD

The app (iPhone, Mac and the watch it carries) joins dadi with the in-app node, so it needs no paid Apple account: a free Personal Team signs it, and the first join has to happen on the box's network.

```sh
./scripts/build-xcframework.sh                      # build/Dadi.xcframework, linked by the app
cp app/Signing.xcconfig.example app/Signing.xcconfig # set DEVELOPMENT_TEAM (gitignored)
(cd app && xcodegen generate && open Khisso.xcodeproj)
xcodebuild -project app/Khisso.xcodeproj -scheme Dadi -destination 'platform=macOS,arch=arm64' test
```

```sh
go test ./...
./scripts/build-xcframework.sh          # build/Dadi.xcframework
(cd apple && swift build)               # DadiTunnel against the local xcframework
```

| Workflow | When | What |
| --- | --- | --- |
| `ci.yml` → `ci` | PR + push to `main` | `go vet` for Linux and macOS; `go test` |
| `ci.yml` → `apple` | after `ci` | build `Dadi.xcframework`; compile DadiTunnel for macOS and iOS; test the dadi app on macOS and build it for iOS, unsigned |
| `ci.yml` → `release` | `main` after `apple` | GitHub Release `khisso-network-<sha>` with the xcframework and its checksum |

## Logging / error codes

Every log line is JSON with `time`, `level`, `service` (`dadi`) and `msg`. The extension hands lines to the provider, which writes them to `os.Logger` under the extension's bundle ID; the app logs to `os.Logger` under `com.dadi.khisso`. Service errors reach the app as `{error: {type, message}}` and are shown with their message.
