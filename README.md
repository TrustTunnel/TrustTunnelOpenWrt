<!-- markdownlint-disable MD041 -->
<p align="center">
<picture>
<source media="(prefers-color-scheme: dark)" srcset="https://cdn.adguardcdn.com/website/github.com/TrustTunnel/logo_dark.svg" width="300px" alt="TrustTunnel" />
<img src="https://cdn.adguardcdn.com/website/github.com/TrustTunnel/logo_light.svg" width="300px" alt="TrustTunnel" />
</picture>
</p>

<p align="center">TrustTunnel client packages for OpenWrt routers</p>

<p align="center"><a href="#installation">Install</a>
  · <a href="https://trusttunnel.github.io/TrustTunnelOpenWrt/">Package repositories</a>
  · <a href="https://github.com/TrustTunnel/TrustTunnel">Server</a>
  · <a href="https://github.com/TrustTunnel/TrustTunnelClient">CLI client</a>
  · <a href="https://trusttunnel.org">Website</a>
</p>

---

## Documentation

- [CONFIGURATION.md](CONFIGURATION.md) — configure the tunnel through LuCI
  or UCI
- [REFERENCE.md](REFERENCE.md) — the packages, the LuCI pages, every
  setting and where the files live
- [BEHAVIOUR.md](BEHAVIOUR.md) — how the routing, the profiles and the
  killswitch work, plus the limitations
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — what to check when something
  does not work
- [UPDATING.md](UPDATING.md) — keep the packages current and pin a client
  version
- [UNINSTALLING.md](UNINSTALLING.md) — remove the packages and the
  repository configuration

---

## Introduction

TrustTunnel client daemon for OpenWrt routers. It runs the tunnel, exposes
a LuCI control page and delivers the tunnel to the LAN. It supports OpenWrt
**22.03 and newer** (`apk`-based systems 25.12+, `opkg`-based 22.03–24.10).

The tunnel runs in one of two operation modes. **TUN** mode (the default)
routes the LAN through the tunnel. **Proxy** mode runs a SOCKS5 listener
instead. Named routing profiles decide which destinations use the tunnel.
[BEHAVIOUR.md](BEHAVIOUR.md) describes the routing, the profiles and the
killswitch.

---

## Requirements

- **OpenWrt 22.03 or newer**: `apk`-based systems need 25.12+,
  `opkg`-based systems 22.03–24.10. The installer detects which package
  manager the router uses.
- **CPU**: one of the five families the vendor builds for. The installer
  probes `uname -m` first. It stops before it changes anything on
  unsupported hardware:

  | `uname -m`          | Covers                                        |
  | ------------------- | --------------------------------------------- |
  | `x86_64`            | mini-PCs, virtual machines, x86 gateways      |
  | `aarch64` / `arm64` | modern 64-bit ARM routers                     |
  | `armv7l` / `armv8l` | 32-bit ARM routers of the previous generation |
  | `mips` / `mipsel`   | MIPS-based routers such as ath79/ramips boards |

  The installer refuses anything else — ARMv5/ARMv6 boards, `mips64`,
  `riscv64` or `powerpc` — before it changes a single file.
- **Internet access from the router**: the installer needs it once, at
  install time.

---

## Packages

The project ships four packages. Three of them are mandatory:

- `luci-app-trusttunnel` — the LuCI app: the pages, the backend and the
  menu entry
- `trusttunnel` — the runtime: the service, the routing and the UCI
  config
- `trusttunnel-client` — the client binaries in `/opt/trusttunnel_client`

The app depends on the runtime, and the runtime depends on the client
package. One install therefore pulls all three. The optional fourth
package is `luci-app-trusttunnel-diagnostics`, which adds the Diagnostics
and Tools pages. Install it separately (see Installation).

[REFERENCE.md](REFERENCE.md#packages) lists every package, its contents
and its dependencies.

---

## Installation

Run the installer:

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/TrustTunnel/TrustTunnelOpenWrt/master/install.sh)"
```

If your router uses an older installer URL, run this command again. The
command points the package manager at the current feed. The settings and
the service state stay the same.

The script does these steps:

1. Checks the environment: the OpenWrt release, the CPU family and the
   package manager (apk or opkg). The architecture check runs before any
   change.
2. Points the package manager at the signed package repositories on the
   GitHub Pages site of this project. Each device architecture has one
   feed directory in the official OpenWrt layout. The script also installs
   the signing key.
3. Installs the packages `kmod-tun ip-full nftables curl ca-bundle`, and
   then `luci-app-trusttunnel`. The `trusttunnel` runtime (the service and
   the routing) and `trusttunnel-client` (the binaries in
   `/opt/trusttunnel_client`) arrive as dependencies.
4. Restarts `rpcd` to load the new backend code. It runs
   `/etc/uci-defaults/40-luci-trusttunnel` immediately. That script
   creates the firewall zone, the `lan → trusttunnel` forwarding and the
   Default routing profile. The script is idempotent: the same run at the
   next boot changes nothing.
5. Returns the service to its previous state. A first install leaves the
   service disabled. Configure the endpoint first (see
   [CONFIGURATION.md](CONFIGURATION.md)). Then set the service switch to
   on and start the service.

Run the installer again to update the package and the client binary, and
to refresh the signing keys. The installer does not touch
`/etc/config/trusttunnel`. Stable client releases publish automatically:
the scheduled updater bumps the vendor pin, runs the test suites, and
publishes a `client-vX.Y.Z` release.

Each feed keeps the newest three releases, because the published site
has a hard 1 GB limit. The newest LuCI app release is always kept.
Older versions stay on their GitHub releases. [UPDATING.md](UPDATING.md)
shows how to install one of them.

The Diagnose and Tools pages are an optional add-on. Install the
`luci-app-trusttunnel-diagnostics` package separately from the same
repository: `apk add luci-app-trusttunnel-diagnostics` on OpenWrt 25.12+,
or `opkg install luci-app-trusttunnel-diagnostics` on 22.03–24.10. The
core app works without it.

---

## Testing and feedback

The package is tested on **x86_64** virtual machines and **mipsel**
routers. The release pipeline builds the remaining vendor-supported
families (`aarch64`, `armv7l`/`armv8l`, `mips`), but the project has
verified them less on real devices. Reports from those platforms are
especially valuable.

Usage reports, bug reports and pull requests are welcome. Open an
[issue](https://github.com/TrustTunnel/TrustTunnelOpenWrt/issues) for
anything that does not behave, and send a
[pull request](https://github.com/TrustTunnel/TrustTunnelOpenWrt/pulls)
for a fix or an improvement. If you report a problem on a platform other
than x86_64/mips, include the router model and the OpenWrt release.
Device-specific quirks usually reproduce only with that context.

---

## Acknowledgements

- [`TrustTunnel/TrustTunnel`](https://github.com/TrustTunnel/TrustTunnel)
  — the server component (Apache-2.0)
- [`TrustTunnel/TrustTunnelClient`](https://github.com/TrustTunnel/TrustTunnelClient)
  — the client binary (Apache-2.0)
- [`NooBiToo/TrustTunnelOpenWrt`](https://github.com/NooBiToo/TrustTunnelOpenWrt)
  — a conceptually similar LuCI package with selective domain-list bypass
- [`iamvladdy/trusttunnel-openwrt`](https://github.com/iamvladdy/trusttunnel-openwrt)
  — a netifd-based implementation with selective routing

---

## License

Apache-2.0 (see `LICENSE`).
