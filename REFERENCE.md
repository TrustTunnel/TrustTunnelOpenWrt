# Reference

The installed packages, the LuCI pages, every setting and the files the
package touches. To configure the tunnel, see [CONFIGURATION.md](CONFIGURATION.md).

---

## Packages

The project ships four packages. Three of them are mandatory, and one is
optional. The mandatory packages form one dependency chain:

```text
luci-app-trusttunnel-diagnostics  (optional)
  └── luci-app-trusttunnel
        └── trusttunnel
              └── trusttunnel-client
```

| Package | Required | Contents |
| --- | --- | --- |
| `luci-app-trusttunnel` | yes | the LuCI pages (Status, Settings, Client log and Versions), the rpcd backend, the ACL and the menu entry |
| `trusttunnel` | yes | the runtime: the procd service, the routing helper, the records helpers, the default UCI config, the uci-defaults script and the hotplug hook |
| `trusttunnel-client` | yes | the vendor client binaries (`trusttunnel_client` and `setup_wizard`) in `/opt/trusttunnel_client` |
| `luci-app-trusttunnel-diagnostics` | no | the Diagnostics and Tools pages |

Each package depends on the packages below it in the tree. A router that
installs `luci-app-trusttunnel` therefore gets the runtime and the client
package too. The diagnostics add-on is not a dependency of the app.
Install it separately (see [README.md](README.md#installation)).

The packages also depend on packages outside this project:

- `trusttunnel-client` depends on `kmod-tun` and `ca-bundle`.
- `trusttunnel` depends on `ip-full` and `nftables`.
- `luci-app-trusttunnel` depends on `luci-base`, `curl` and
  `ucode-mod-math`.
- `luci-app-trusttunnel-diagnostics` depends on `luci-base`.

The installer installs `kmod-tun ip-full nftables curl ca-bundle`
directly, and then installs the app.

---

## LuCI pages

The Status, Settings, Client log and Versions pages live under **Services
→ TrustTunnel**. The Diagnose and Tools pages come from the optional
`luci-app-trusttunnel-diagnostics` package (see
[README.md](README.md#installation)).

### Status page

- A verdict banner. It shows one of these states:
    - the client is not installed
    - the service is off
    - the service is enabled, but it is not running
    - the service runs, but the tunnel is not up yet ("connecting") — in
      proxy mode the banner watches the SOCKS listener instead
    - the tunnel works, with the assigned profile named
- **Current state**, refreshed every ten seconds. It holds a State row
  ("working" only when everything is), a Mode row, the server host name
  and, in proxy mode, the listener address. The Mode row names the
  assigned profile and the half of its rules that goes through the
  tunnel. Without a profile it shows "Everything through VPN". A
  **Traffic** row shows the current download and upload rates (a
  ten-second average) and the cumulative bytes. In tun mode the counters
  come from the tun device. In proxy mode they come from the listener
  port. The page also carries Start, Stop and Restart buttons.
- **Preview rules** shows how the system treats each rule of the
  assigned profile now. Without a profile it shows the legacy "do not
  bypass" list.

### Client log page

A tail of the system-log lines that the client and the service write. It
refreshes every ten seconds. The status verdicts point here when
something is wrong.

### Diagnostics page

The page runs the whole chain at once, in the order the package works. It
reports a verdict for each check: problems and remarks first, the passing
checks behind a toggle. Read the list from the top and look for the first
problem.

| Group | Checks |
| --- | --- |
| Configuration | endpoint address, credentials, TLS host name, assigned routing profile |
| Prerequisites | client binary, `/dev/net/tun` (TUN mode only) |
| Service | enabled at boot, running now |
| Kernel state | TUN mode: tunnel device and its MTU, route attached to the device, tunnel carrier, fwmark rule, routing table, nftables table, firewall zone. Proxy mode: the SOCKS listener (bound on the configured address or not) and the usage meter (counter rules on the listener port). |
| Network | endpoint reachable, traffic actually going through the tunnel (via the device in TUN mode, via the listener in proxy mode) |

Four verdicts, and the distinction matters:

- **ok** — checked and working.
- **check** — works with a remark, for example the device exists but has
  no carrier yet, because the client has not established the tunnel.
- **problem** — not working, with what to do about it.
- **skipped** — nothing to check, because an earlier link is not ready.
  A stopped service must not make the kernel checks red.

The page also carries three tools:

- **Ping the server** — loss and min/avg/max for every configured
  address.
- **Compare the external address** — the address through the tunnel next
  to the address seen directly. The same address both ways means the
  traffic is not using the tunnel. In TUN mode a request bound to the
  device can fail on a healthy tunnel, because the default route lives
  in the marked table. Use a LAN client for the test instead. In proxy
  mode the request goes through the SOCKS listener.
- **Check a domain** — the normalized name, whether the domain is
  listed, and the verdict (through the tunnel or direct) with the
  reason. An entry like `example.com` matches the domain itself and its
  subdomains. The tool only consults the rule lists. It does not resolve
  the domain and does not touch the rules.

---

## Settings reference

All settings live in `/etc/config/trusttunnel`. The service generates the
files under `/var/etc/trusttunnel/` from it. The service overwrites those
files when it starts and when it applies settings. Do not edit them.

### Section `main`

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `0` | The service switch. The service starts at boot when the switch is on. An explicit Start from the Status page runs the service even while the switch is off. The service then stays off at the next boot. The automatic starts (boot, WAN up, config reload) are still refused |
| `mode` | `tun` | The operation mode. `tun` routes the whole LAN through the client automatically. `proxy` runs a SOCKS5 listener instead (see the `proxy` section) |
| `endpoint` | `Default` | The ACTIVE server. It is the `name` of the `endpoint` section that the tunnel uses now. The other saved servers stay configured but unused |
| `log_level` | `info` | `info`, `debug` or `trace`. The last two are noisy. Set them only while you investigate a problem |

### Section `proxy`

Used in proxy mode only.

| Option | Default | Meaning |
| --- | --- | --- |
| `address` | `127.0.0.1:1080` | The `IP:port` that the SOCKS5 listener binds. `127.0.0.1:1080` serves the router itself. `0.0.0.0:1080` or the LAN address of the router serves the whole LAN. The client then requires `username` and `password` |
| `username` | — | Optional SOCKS5 authentication. Set it together with `password`, or leave both empty for an open proxy. It is mandatory for any listener outside the loopback |
| `password` | — | The SOCKS5 password. The client uses it only when `username` is set |

### Section `endpoint` (repeatable, one section per saved server)

`main.endpoint` selects the ACTIVE section by its `name`. Only the options
of the ACTIVE server take effect. Only its credentials and its pinned
certificate reach the generated client configuration.

| Option | Default | Meaning |
| --- | --- | --- |
| `name` | — | A unique name. `main.endpoint` selects the ACTIVE server by it. Required |
| `hostname` | — | The TLS host name. The client uses it for the TLS session, not for routing. Many servers refuse the connection without it. Required |
| `address` | — | `host:port` or `[ipv6]:port`. The option is repeatable. With several addresses the client measures them and picks the fastest. At least one address is required |
| `username` | — | Required. |
| `password` | — | Required. |
| `protocol` | `http2` | The transport: `http2` or `http3` (QUIC). QUIC is often faster, but some networks throttle or block UDP |
| `anti_dpi` | `0` | Countermeasures against traffic inspection. Enable it when the connection establishes but keeps dropping |
| `post_quantum` | `1` | Post-quantum key exchange |
| `custom_sni` | — | Overrides the TLS Server Name. Use it when the server answers on an address that does not match its host name, for example a CDN or an IP-only setup |
| `client_random` | — | The TLS Client Random prefix and mask in hex, for example `0a0b0c` or `0a0b0c/0f0f0f`. Anti-scan servers accept only clients with the matching prefix |
| `has_ipv6` | `1` | The server carries IPv6 |
| `skip_verification` | `0` | Accept any certificate. This option removes the protection against a substituted server. Pin the certificate instead whenever you can |
| `certificate` | — | The pinned server certificate (PEM). An empty value means the system trust store. The trust store requires the `ca-bundle` package |
| `dns_upstream` | — | The DNS that the client itself uses, for example for the exclusion domains it pre-resolves. An empty value means the client default (AdGuard DNS unfiltered) |
| `routing_profile` | `Default` | The routing profile that THIS server uses while it is active. An empty value, or a name that no longer matches a profile, uses the direct-by-default rule in TUN mode (nothing is routed) and the legacy `domains.direct` list in proxy mode |

### Section `network`

| Option | Default | Meaning |
| --- | --- | --- |
| `mtu` | `1350` | Tunnel MTU. If the value is too high, small pages load but TLS handshakes and large downloads stall |
| `lan_devices` | — | The LAN interfaces whose forwarded traffic is considered. An empty value means the device of the `lan` network, with `br-lan` as the last-resort fallback |
| `blackhole_on_down` | `0` | The fail-open default. The blackhole exists only while a tun device is attached. Marked traffic falls through to the direct route while the client connects or is down. Set the option to `1` for the strict killswitch. The blackhole then stays armed without a device. Marked traffic is dropped instead of leaking to the provider whenever it cannot reach the tunnel |
| `include_router_traffic` | `0` | Also route the traffic that the router itself originates |
| `fwmark` | `0x9527` | The firewall mark, decimal or `0x`-prefixed hex. Change it only on a conflict with mwan3, SQM or another package that marks packets |
| `table` | `880` | The routing table id. Any value is valid except `0` and the reserved `253–255` |

### Section `routing_profile` (anonymous, repeatable)

| Option | Default | Meaning |
| --- | --- | --- |
| `name` | — | A unique name. The `routing_profile` option of the ACTIVE server assigns the profile by it |
| `mode` | `bypass` | `vpn` tunnels everything except the bypass rules. `bypass` tunnels only the VPN rules. The default is `bypass`: traffic goes out directly until rules route it |
| `vpn_rules` | — | The client sends these entries through the tunnel. In bypass mode they are the only tunneled destinations. In VPN mode the list has no effect |
| `bypass_rules` | — | The client always sends these entries out directly. In VPN mode they are the only direct destinations. In bypass mode the list has no effect |

### Section `domains` (legacy)

| Option | Default | Meaning |
| --- | --- | --- |
| `direct` | — | The flat "do not bypass" list. The client applies it in proxy mode when no routing profile is assigned, or when the assigned name no longer matches a profile. In TUN mode the fallback routes nothing, so the list has no effect there |

Rule entries in every list accept a plain domain, a `*.domain` wildcard,
an IP address, an `IP:port` pair, or a CIDR range.

---

## Where things live

- `/etc/config/trusttunnel` — your settings. The package declares the
  file as a conffile, so it survives package updates
- `/opt/trusttunnel_client/` — the client binaries (`trusttunnel_client`
  and `setup_wizard`)
- `/var/etc/trusttunnel/` — generated files (`settings.tsv`,
  `client.toml`, `endpoint.pem`, `device`, `tun_since`). The service
  overwrites them when it starts and when it applies settings. Never
  edit them
