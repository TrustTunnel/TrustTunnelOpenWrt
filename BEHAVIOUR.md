# Behaviour

How the package routes traffic, what it touches on the router, and the
limits that follow. For the tasks, see [CONFIGURATION.md](CONFIGURATION.md).
For the exact options, see [REFERENCE.md](REFERENCE.md).

---

## How it works

### Operation modes

The tunnel is delivered in one of two **operation modes** (`main.mode`):

- **TUN mode** (the default) routes the LAN through the tunnel: LAN
  traffic is marked with fwmark `0x9527`, a policy rule sends marked
  packets to routing table `880`, and the client's tun device carries
  them, backed by a blackhole killswitch.
- **Proxy mode** runs a SOCKS5 listener on the router instead. Nothing is
  routed automatically — apps and devices that support a proxy point at
  the listener address. There is no tun device and no kernel routing.

### Routing profiles

Both modes share the same server settings and the same **named routing
profiles**: each profile has a mode — **VPN** (everything through the
tunnel except the bypass list) or **Bypass** (only the VPN list through
the tunnel) — and two rule lists. Several servers can be saved; one is
**active** at a time (`main.endpoint`), and switching it takes effect on
the next reload. One profile is assigned to each server via its
`endpoint.routing_profile` and enforced by the client itself; the profile
also decides what the kernel marks (see
[Marking and routing](#marking-and-routing)). **Traffic goes out directly
unless a profile explicitly routes it**: without an assigned profile (or
with a stale name) nothing is marked and nothing enters the tunnel in TUN
mode, while the proxy keeps tunneling everything except the legacy flat
`domains.direct` list.

### What the package touches

On the router the package touches only the LuCI app, the client package
(binaries under `/opt/trusttunnel_client`) and `/etc/config/trusttunnel` —
plus, in TUN mode, a `trusttunnel` firewall zone bound to the attached
tun device with a `lan → trusttunnel` forwarding rule and the routing
chain above. Proxy mode uses none of the routing or firewall parts.

### Marking and routing

In TUN mode the `trusttunnel` zone is bound to the attached tun device
(never a `tun+` wildcard, which would absorb foreign tun devices like
OpenVPN's). LAN traffic is marked with fwmark `0x9527` — but only as far
as the assigned routing profile allows: a VPN-mode profile marks
everything except the IP/CIDR entries of its bypass list; a bypass-mode
profile whose VPN list is purely IP/CIDR marks only those destinations; a
bypass profile with a domain entry marks everything and lets the client
split by SNI; **no profile marks nothing**. A policy rule sends marked
packets to table `880`, whose default route leads to the client's tun
device. Traffic originating on the router itself is not marked by default
(`include_router_traffic` is off); it leaves through the ordinary default
route.

### Selective routing

Inside the tunnel the client decides where each connection goes. VPN mode
keeps everything in the tunnel except the entries in the bypass list;
Bypass mode puts only the VPN-list entries into the tunnel. Domain
entries are matched by TLS SNI; IP addresses and CIDR ranges by the
destination — and IP/CIDR bypass entries are already kept out at the
kernel: listed destinations never enter the tun at all, so they work even
while the client is down.

### Killswitch

The blackhole route (metric `1000`) in table `880` is armed while a tun
device is attached (attach arms it, detach removes it). By default it
exists only then: while the client is connecting or dead, marked traffic
falls through to the direct route instead of being swallowed — a crashed
client must not blackhole the LAN. The Advanced-tab *Strict killswitch*
option (`blackhole_on_down`) arms the blackhole even without a device:
marked traffic is then dropped instead of leaking to the provider
whenever it cannot reach the tunnel. The generated config turns the
client's own killswitch off (`killswitch_enabled = false`); the routing
table does the protecting while the tunnel is up.

### DNS

Nothing intercepts or rewrites DNS: the generated config sets
`change_system_dns = false`, and the router's resolver keeps serving the
LAN.

### Applying changes

Save & Apply regenerates only what the changed keys require: LAN-interface
and routing-parameter tweaks keep the tunnel up; `main.enabled`,
`main.mode`, `network.table` and `network.fwmark` tear the routing down
and rebuild it; everything else (endpoint, routing profiles, proxy, MTU,
log level, the pinned certificate) restarts the client while the routing
survives. Anything outside the schema gets the fullest action — a full
restart — because a silently unapplied setting is worse than downtime.

### Proxy mode

With `main.mode=proxy` the generated config carries `[listener.socks]`
instead of `[listener.tun]` — the client accepts exactly one listener.
The routing helper, the hotplug reattach and the firewall zone are not
involved; the killswitch, MTU, LAN-interface and routing options have no
effect.

---

## Limitations

- Only forwarded LAN traffic is routed by default; traffic originating on
  the router itself leaves through the ordinary default route unless
  `include_router_traffic` is on.
- Domain rules are matched by the connection's TLS SNI once the traffic is
  inside the tunnel. Connections without a TLS SNI (plain IP, non-TLS)
  can be matched only by IP or CIDR rules. DNS is not involved in the
  selection. BitTorrent peer connections have no SNI: they stay direct
  unless an IP/CIDR rule routes them (the default bypass profile routes
  nothing).
- The client's tun device is created and named by the client itself; the
  package attaches the tunnel route to whatever client device appears (via
  hotplug, judged by the ifindex snapshot written at service start) and
  records it in `/var/etc/trusttunnel/device`. Foreign tun devices
  (OpenVPN and friends) are never attached, and the firewall zone binds
  the attached device by name, never a `tun+` wildcard.
- **Proxy mode** does not route anything automatically: only apps and
  devices explicitly configured to use the SOCKS5 listener get the
  tunnel. DNS for proxied connections is resolved by the client through
  the tunnel (`endpoint.dns_upstream`); apps that resolve locally and
  send bare IPs do not get that DNS. An open listener (no credentials)
  bound to `0.0.0.0` is reachable by the whole LAN — the client itself
  refuses to bind anything outside the loopback without the user/pass
  pair, so protect LAN-exposed listeners with credentials.

---

## Notes and caveats

- **Firewall zone.** The zone is bound to the concrete attached tun
  device by the routing helper on attach, so tun devices created by
  other software are never claimed by the package. The zone section
  itself stays in the firewall config without a device binding while
  the service is off.
- **Repositories and signing.** The repositories are served from the
  GitHub Pages site of this project
  (`https://trusttunnel.github.io/TrustTunnelOpenWrt`), in the official
  OpenWrt layout `releases/<version>/packages/<arch>/trusttunnel/`: the
  `25.12.5` tree holds the apk feeds, the `22.03.7` tree the opkg feeds —
  one signed feed directory per device architecture. A release is a
  `vX.Y.Z` tag push on master: the release workflow builds the packages,
  verifies them end to end, and publishes the repositories, the site and
  a GitHub release from the tag (the pipeline refuses runs that are not
  tag pushes). The site is served straight from CI, and no branch ever
  holds the packages.
- **Manual downloads.** A `.apk` or `.ipk` fetched from the release assets
  must be checked against the SHA-256 sums in the release notes.
- **Key rotation.** The signing keys rotate; run the installer once more
  to refresh the copies on the router.
