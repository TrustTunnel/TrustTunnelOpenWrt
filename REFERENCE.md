# Reference

The LuCI pages, every setting and the files the package touches. To
configure the tunnel, see [CONFIGURATION.md](CONFIGURATION.md).

---

## LuCI pages

The Status, Settings, Client log and Versions pages live under **Services
→ TrustTunnel**; the Diagnose and Tools pages come from the optional
`luci-app-trusttunnel-diagnostics` package (see
[README.md](README.md#installation)).

### Status page

- A verdict banner: the client is not installed; the service is off;
  the service is enabled but not running; the service runs but the
  tunnel (or, in proxy mode, the SOCKS listener) is not up yet
  ("connecting"); or the tunnel works — with the assigned profile named.
- **Current state** (refreshed every ten seconds): a State row
  ("working" only when everything is), a Mode row — the assigned profile
  and which half of its rules goes through the tunnel, or "Everything
  through VPN" without a profile — the server host name, and in proxy
  mode the listener address. A **Traffic** row shows the current
  download/upload rates (a ten-second average) and the cumulative bytes
  through the tunnel: the tun device's kernel counters in tun mode, the
  listener-port counters in proxy mode. Start / Stop / Restart buttons.
- **Preview rules**: shows how each rule of the assigned profile is
  treated right now — or the legacy "do not bypass" list when no profile
  is assigned.

### Client log page

A tail of the system-log lines written by the client and the service,
refreshed every ten seconds. The status verdicts point here when
something is wrong.

### Diagnostics page

Runs the whole chain at once, in the order the package works, and reports
a verdict per check — problems and remarks first, the passing checks
behind a toggle. Read the list top to bottom and look for the first
problem.

| Group | Checks |
| --- | --- |
| Configuration | endpoint address, credentials, TLS host name, assigned routing profile |
| Prerequisites | client binary, `/dev/net/tun` (TUN mode only) |
| Service | enabled at boot, running now |
| Kernel state | TUN mode: tunnel device and its MTU, route attached to the device, tunnel carrier, fwmark rule, routing table, nftables table, firewall zone. Proxy mode: the SOCKS listener (bound on the configured address or not) and the usage meter (counter rules on the listener port). |
| Network | endpoint reachable, traffic actually going through the tunnel (via the device in TUN mode, via the listener in proxy mode) |

Four verdicts, and the distinction matters:

- **ok** — checked and working;
- **check** — works with a remark; e.g. the device exists but has no
  carrier yet, because the client has not established the tunnel;
- **problem** — not working, with what to do about it;
- **skipped** — nothing to check, because an earlier link is not ready; a
  stopped service must not make the kernel checks red.

The page also carries three tools:

- **Ping the server** — loss and min/avg/max for every configured address.
- **Compare the external address** — the address seen through the tunnel
  next to the one seen directly. The same address both ways means the
  traffic is not using the tunnel. In TUN mode a request bound to the
  device can fail even on a healthy tunnel, because the default route
  lives in the marked table — judge by a LAN client instead. In proxy
  mode the request goes through the SOCKS listener.
- **Check a domain** — the normalized name, whether the domain is listed
  (an entry like `example.com` matches the domain itself and its
  subdomains), and the verdict — through the tunnel or direct — with the
  reason. The tool only consults the rule lists; it does not resolve the
  domain or touch the rules.

---

## Settings reference

Everything lives in `/etc/config/trusttunnel`. The files under
`/var/etc/trusttunnel/` are generated from it and overwritten whenever
the service starts or settings are applied — they must not be edited.

### Section `main`

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `0` | The service switch: the service starts at boot when it is on. An explicit Start from the Status page runs it even while it is off — but it stays off at the next boot, and the automatic starts (boot, WAN up, config reload) are still refused |
| `mode` | `tun` | The operation mode: `tun` routes the whole LAN through the client automatically; `proxy` runs a SOCKS5 listener instead (see the `proxy` section) |
| `endpoint` | `Default` | The ACTIVE server: the `name` of the `endpoint` section the tunnel uses right now. The other saved servers stay configured but unused |
| `log_level` | `info` | `info`, `debug` or `trace`; the last two are noisy, leave them on only while investigating something |

### Section `proxy`

Used in proxy mode only.

| Option | Default | Meaning |
| --- | --- | --- |
| `address` | `127.0.0.1:1080` | The `IP:port` the SOCKS5 listener binds. `127.0.0.1:1080` serves the router itself; `0.0.0.0:1080` or the router's LAN address serves the whole LAN — the client then requires `username`/`password`. |
| `username` | — | Optional SOCKS5 authentication; set it together with `password`, or leave both empty for an open proxy. Mandatory for any listener outside the loopback. |
| `password` | — | The SOCKS5 password; emitted only when `username` is set |

### Section `endpoint` (repeatable; one section per saved server)

Exactly one of the sections is ACTIVE, selected by `main.endpoint` by
its `name`. Only the ACTIVE server's options take effect, and only its
credentials and pinned certificate ever reach the generated client
configuration.

| Option | Default | Meaning |
| --- | --- | --- |
| `name` | — | Unique name; `main.endpoint` selects the ACTIVE server by it. Required. |
| `hostname` | — | TLS host name, used for the TLS session rather than for routing; many servers refuse the connection without it. Required. |
| `address` | — | `host:port` or `[ipv6]:port`, repeatable. With several addresses the client measures them and picks the fastest. At least one required. |
| `username` | — | Required. |
| `password` | — | Required. |
| `protocol` | `http2` | The transport: `http2` or `http3` (QUIC). QUIC is often faster, but some networks throttle or block UDP. |
| `anti_dpi` | `0` | Countermeasures against traffic inspection; worth enabling when the connection establishes but keeps dropping. |
| `post_quantum` | `1` | Post-quantum key exchange. |
| `custom_sni` | — | Overrides the TLS Server Name — needed when the server answers on an address that does not match its host name (a CDN or an IP-only setup). |
| `client_random` | — | TLS Client Random prefix and mask in hex, e.g. `0a0b0c` or `0a0b0c/0f0f0f`; anti-scan servers accept only clients with the matching prefix. |
| `has_ipv6` | `1` | The server carries IPv6. |
| `skip_verification` | `0` | Accept any certificate, which removes the protection against a substituted server. Pin the certificate instead whenever you can. |
| `certificate` | — | Pinned server certificate (PEM). Empty means the system trust store, which requires the `ca-bundle` package. |
| `dns_upstream` | — | DNS used by the client itself — for example the exclusion domains it pre-resolves. Empty means the client default (AdGuard DNS unfiltered). |
| `routing_profile` | `Default` | The routing profile THIS server uses while it is the active one. Empty, or a name that no longer matches any profile, falls back to the direct-by-default rule in TUN mode (nothing is routed) and to the legacy `domains.direct` list in proxy mode. |

### Section `network`

| Option | Default | Meaning |
| --- | --- | --- |
| `mtu` | `1350` | Tunnel MTU. Too high a value makes small pages load while TLS handshakes and large downloads stall. |
| `lan_devices` | — | LAN interfaces whose forwarded traffic is considered; empty means the device of the `lan` network, with `br-lan` as the last-resort fallback |
| `blackhole_on_down` | `0` | Fail-open default: the blackhole exists only while a tun device is attached, so marked traffic falls through to the direct route while the client connects or is down. Set to `1` for the strict killswitch: the blackhole stays armed without a device, so marked traffic is dropped instead of leaking to the provider whenever it cannot reach the tunnel. |
| `include_router_traffic` | `0` | Also route traffic originated by the router itself. |
| `fwmark` | `0x9527` | The firewall mark, decimal or `0x`-prefixed hex. Change only on a conflict with mwan3, SQM or another package that marks packets. |
| `table` | `880` | The routing table id; anything except `0` and the reserved `253–255`. |

### Section `routing_profile` (anonymous, repeatable)

| Option | Default | Meaning |
| --- | --- | --- |
| `name` | — | Unique name; the ACTIVE server's `routing_profile` option assigns the profile by it. |
| `mode` | `bypass` | `vpn` — tunnel everything except the bypass rules; `bypass` — tunnel only the VPN rules (the default: traffic goes out directly until rules route it). |
| `vpn_rules` | — | Sent through the tunnel. In bypass mode these are the only tunneled destinations; in VPN mode the list has no effect. |
| `bypass_rules` | — | Always sent out directly. In VPN mode these are the only direct destinations; in bypass mode the list has no effect. |

### Section `domains` (legacy)

| Option | Default | Meaning |
| --- | --- | --- |
| `direct` | — | The flat "do not bypass" list, applied in proxy mode when no routing profile is assigned (or the assigned name no longer matches any). In TUN mode the fallback routes nothing, so the list has no effect there. |

Rule entries in every list accept a plain domain, a `*.domain` wildcard,
an IP address, an `IP:port` pair, or a CIDR range.

---

## Where things live

- `/etc/config/trusttunnel` — your settings; survives package updates
  (declared as a conffile)
- `/opt/trusttunnel_client/` — the client binaries (`trusttunnel_client`
  and `setup_wizard`)
- `/var/etc/trusttunnel/` — generated files (`settings.tsv`,
  `client.toml`, `endpoint.pem`, `device`, `tun_since`); overwritten
  whenever the service starts or settings are applied — never edit them
