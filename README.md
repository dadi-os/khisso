# Khisso

Khisso is dadi's Apple app for iPhone and Mac (shown as dadi; khisso is the internal name). This repo holds the app's network layer and, as it is built, the app's Xcode project. See the Khisso and dadi Tunnel specs.

The network layer is how a dadi device joins dadi. It runs dadi's Tailscale node, so the apps never touch networking themselves: on macOS and iOS it is the engine inside the dadi packet-tunnel extension (the OS lists it as a VPN named dadi) or, for builds signed without the Network Extension entitlement, an in-app node that only the app's own traffic uses; on Windows and Linux it is `dadid`, a system service that creates the `dadi` tunnel interface and configures routes and `*.dadi` DNS. thaali and khisso only provision the device, turn dadi on or off, and read status.

## Dependencies

- Headscale on the box (the control server in each setup code).
- Tailscale `v1.82.0` (`tailscale.com`), used as a library: `ipn/ipnlocal`, `wgengine`, `ipn/store`, `net/dns`, `wgengine/router`, `safesocket`, and `tsnet` for the in-app node.
- Apple: NetworkExtension, with an app signed for the Network Extension entitlement that embeds the extension. The in-app node needs no entitlement.
- Windows: Wintun (`wintun.dll` beside `dadid.exe`).

## Layout

```
khisso/
  internal/node/      the node: Start with ExtensionNetwork (Apple) or SystemNetwork (Windows, Linux), Status
  internal/inapp/     the in-app node: tsnet, a loopback CONNECT proxy to *.dadi, MagicDNS lookups
  internal/service/   dadid's settings, node lifecycle and local API
  internal/utun/      finds the extension's utun descriptor (macOS, iOS)
  cmd/dadi/           C interface, built into Dadi.xcframework
  cmd/dadid/          Windows and Linux service
  apple/              DadiTunnel Swift package: the packet-tunnel provider
  packaging/linux/    systemd unit
  scripts/            build-xcframework.sh
```

## Config vs env

There is no environment configuration.

- **Extension:** the app writes `control_url`, `hostname`, `app_group` and `keychain_group` into the VPN configuration's `providerConfiguration`; the auth key lives in the shared Keychain (service `com.dadi.tunnel`, account `auth_key`); node state is `tailscale/` in the app-group container. A missing value fails the tunnel start with its name.
- **In-app node:** `dadi_app_start` takes the same `node.Config` JSON (`control_url`, `hostname`, `auth_key`, `state_dir`) and returns the proxy port. The app points its HTTP client's CONNECT proxy at `127.0.0.1:<port>`; the proxy refuses any target that is not `*.dadi` or a `100.64.0.0/10` address.
- **dadid:** `--state-dir` and `--socket` are required flags; it exits at startup without them. The setup code arrives through `POST /provision` and is saved in `<state-dir>/dadi.json` (mode 0600) with the on/off choice. Node state is `<state-dir>/node/`.

The auth key is used only for the first login. A saved node restarts with its own key, so an expired setup code never breaks a restart.

### dadid local API

Served on a Unix socket (Linux) or named pipe (Windows).

| Method | Path | Body | Returns | Errors |
| --- | --- | --- | --- | --- |
| `GET` | `/status` | — | `{provisioned, want_running, node_name, node, last_error}` | — |
| `POST` | `/provision` | `{control_url, auth_key, node_name}` | status | `invalid_request` |
| `POST` | `/up` | — | status | `not_provisioned` |
| `POST` | `/down` | — | status | `not_provisioned` |
| `POST` | `/forget` | — | status | `internal_error` |

`node` is null while dadi is off or the node failed to start; `last_error` then carries the reason. `/provision` gives the device a fresh node identity.

## Local run + CI/CD

```sh
go test ./...
./scripts/build-xcframework.sh          # build/Dadi.xcframework
(cd apple && swift build)               # DadiTunnel against the local xcframework
sudo go run ./cmd/dadid --state-dir=/tmp/dadid --socket=/tmp/dadid.sock   # Linux
```

| Workflow | When | What |
| --- | --- | --- |
| `ci.yml` → `ci` | PR + push to `main` | `go vet` for Linux, Windows and macOS; `go test` |
| `ci.yml` → `apple` | after `ci` | build `Dadi.xcframework`; compile DadiTunnel for macOS and iOS |
| `ci.yml` → `service` | after `ci` | `dadid` for Linux amd64/arm64 and Windows amd64, the systemd unit, `wintun.dll` |
| `ci.yml` → `release` | `main` after both | GitHub Release `khisso-network-<sha>` with every artifact and checksums |

The Khisso app builds the xcframework from this repo; the `dadid` release is what Windows and Linux clients install.

## Logging / error codes

Every log line is JSON with `time`, `level`, `service` (`dadi` in the extension, `dadid` for the service) and `msg`. The extension hands lines to the provider, which writes them to `os.Logger` under the extension's bundle ID; `dadid` writes to stdout for systemd or the Windows service log. API errors are `{error: {type, message}}` with `type` one of `invalid_request`, `not_provisioned`, `internal_error`.
