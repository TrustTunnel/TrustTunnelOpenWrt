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
- [REFERENCE.md](REFERENCE.md) — the LuCI pages, every setting and where
  the files live
- [BEHAVIOUR.md](BEHAVIOUR.md) — how the routing, the profiles and the
  killswitch work, plus the limitations
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — what to check when something
  does not work
- [UPDATING.md](UPDATING.md) — keep the packages current and pin a client
  version
- [UNINSTALLING.md](UNINSTALLING.md) — remove the packages and the
  repository setup

---

## Introduction

TrustTunnel client daemon for OpenWrt routers: it runs the tunnel, exposes
a LuCI control page and delivers the tunnel to the LAN. Targets OpenWrt
**22.03 and newer** (`apk`-based systems 25.12+, `opkg`-based 22.03–24.10).

The tunnel runs in one of two operation modes: **TUN** (the default)
routes the LAN through the tunnel, **proxy** runs a SOCKS5 listener
instead. Named routing profiles decide which destinations use the tunnel.
[BEHAVIOUR.md](BEHAVIOUR.md) describes the routing, the profiles and the
killswitch.

---

## Requirements

- **OpenWrt 22.03 or newer**: `apk`-based systems need 25.12+,
  `opkg`-based systems 22.03–24.10. The installer figures out which
  package manager is in use.
- **CPU**: one of the five families the vendor builds for. The installer
  probes `uname -m` first and aborts before anything changes on
  unsupported hardware:

  | `uname -m`          | Covers                                        |
  | ------------------- | --------------------------------------------- |
  | `x86_64`            | mini-PCs, virtual machines, x86 gateways      |
  | `aarch64` / `arm64` | modern 64-bit ARM routers                     |
  | `armv7l` / `armv8l` | 32-bit ARM routers of the previous generation |
  | `mips` / `mipsel`   | MIPS-based routers, e.g. ath79/ramips boards  |

  Anything else — ARMv5/ARMv6 boards, `mips64`, `riscv64` or `powerpc` —
  is refused before a single file is changed.
- **Internet access from the router**: needed once at install time.

---

## Installation

Run the installer:

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/TrustTunnel/TrustTunnelOpenWrt/master/install.sh)"
```

Routers configured with an older installer URL can switch to the current
repository by running this command again — it re-points the package
manager at the current feed (settings and service state are preserved).

The script then:

1. Checks the environment — OpenWrt release, CPU family, package manager
   (apk or opkg). The architecture gate runs before anything is changed.
2. Points the package manager at the signed package repositories served
   from this project's GitHub Pages site — one feed directory per device
   architecture, in the official OpenWrt layout — and installs the signing
   key.
3. Installs the required packages `kmod-tun ip-full nftables curl
   ca-bundle`, then `luci-app-trusttunnel` with the `trusttunnel`
   runtime (the service and the routing) and `trusttunnel-client` as
   its dependencies (binaries in `/opt/trusttunnel_client`).
4. Restarts `rpcd` so the new backend code is loaded, and runs
   `/etc/uci-defaults/40-luci-trusttunnel` immediately: it creates the
   firewall zone, the `lan → trusttunnel` forwarding and the Default
   routing profile. Idempotent — the same run at the next boot changes
   nothing.
5. Returns the service to its previous state — a first install leaves it
   disabled. Configure the endpoint first (see
   [CONFIGURATION.md](CONFIGURATION.md)), then turn the switch on and
   start the service.

Run the installer again to pull a newer package and client binary and to
refresh the signing keys; `/etc/config/trusttunnel` is left alone.

The Diagnose and Tools pages are an optional add-on; install the
`luci-app-trusttunnel-diagnostics` package separately from the same
repository (`apk add luci-app-trusttunnel-diagnostics` on OpenWrt 25.12+,
`opkg install luci-app-trusttunnel-diagnostics` on 22.03–24.10). The core
app works without it.

---

## Testing and feedback

The package is actively tested on **x86_64** virtual machines and
**mipsel** routers. The remaining vendor-supported families (`aarch64`,
`armv7l`/`armv8l`, `mips`) are covered by the release pipeline's
per-architecture builds but have seen less hands-on verification on real
devices — reports from those platforms are especially valuable.

Usage reports, bug reports and pull requests are welcome: open an
[issue](https://github.com/TrustTunnel/TrustTunnelOpenWrt/issues) for
anything that does not behave, and
[pull requests](https://github.com/TrustTunnel/TrustTunnelOpenWrt/pulls)
for fixes and improvements. When reporting a problem on a platform other
than x86_64/mips, mention the router model and the OpenWrt release —
device-specific quirks usually reproduce only with that context.

---

## Acknowledgements

- [`TrustTunnel/TrustTunnel`](https://github.com/TrustTunnel/TrustTunnel)
  — the server component (Apache-2.0)
- [`TrustTunnel/TrustTunnelClient`](https://github.com/TrustTunnel/TrustTunnelClient)
  — the client binary (Apache-2.0)
- [`NooBiToo/TrustTunnelOpenWrt`](https://github.com/NooBiToo/TrustTunnelOpenWrt)
  — the LuCI package that inspired this implementation
- [`iamvladdy/trusttunnel-openwrt`](https://github.com/iamvladdy/trusttunnel-openwrt)
  — a netifd-based implementation that pairs the client with
  [podkop](https://podkop.net) for selective routing

---

## License

Apache-2.0 (see `LICENSE`).
