# Behaviour

How the package routes traffic, what it touches on the router, and the
limits that follow. For the tasks, see [CONFIGURATION.md](CONFIGURATION.md).
For the exact options, see [REFERENCE.md](REFERENCE.md).

---

## How it works

### Operation modes

The package delivers the tunnel in one of two **operation modes**
(`main.mode`):

- **TUN mode** (the default) routes the LAN through the tunnel. The
  package marks LAN traffic with fwmark `0x9527`. A policy rule sends
  marked packets to routing table `880`, and the tun device of the client
  carries them. A blackhole killswitch backs the tunnel.
- **Proxy mode** runs a SOCKS5 listener on the router instead. Nothing is
  routed automatically. Apps and devices that support a proxy connect to
  the listener address. There is no tun device and no kernel routing.

### Routing profiles

Both modes share the same server settings and the same **named routing
profiles**. Each profile has a mode — **VPN** (the tunnel carries
everything except the bypass list) or **Bypass** (the tunnel carries
only the VPN list) — and two rule lists. You can save several servers,
but only one is **active** at a time (`main.endpoint`). A switch takes
effect on the next reload. You assign one profile to each server with
`endpoint.routing_profile`, and the client enforces it. The profile also
decides what the kernel marks (see
[Marking and routing](#marking-and-routing)). **Traffic goes out
directly unless a profile routes it.** Without an assigned profile (or
with a stale name) the kernel marks nothing, and nothing enters the
tunnel in TUN mode. The proxy keeps tunneling everything except the
legacy flat `domains.direct` list.

### What the package touches

On the router the package touches only the LuCI app, the client package
(binaries under `/opt/trusttunnel_client`) and `/etc/config/trusttunnel`.
In TUN mode it also touches a `trusttunnel` firewall zone and the routing
chain above. The zone is bound to the attached tun device and carries a
`lan → trusttunnel` forwarding rule. Proxy mode uses none of the routing
or firewall parts.

### Marking and routing

In TUN mode the routing helper binds the `trusttunnel` zone to the
attached tun device. It never uses a `tun+` wildcard, which would absorb
foreign tun devices such as OpenVPN's. LAN traffic is marked with fwmark
`0x9527`, but only as far as the assigned routing profile allows. A
VPN-mode profile marks everything except the IP/CIDR entries of its
bypass list. A bypass-mode profile whose VPN list is purely IP/CIDR
marks only those destinations. A bypass profile with a domain entry
marks everything and lets the client split by SNI. **With no profile the
kernel marks nothing.** A policy rule sends marked packets to table
`880`. The default route of that table leads to the tun device of the
client. The package does not mark traffic that the router itself
originates (`include_router_traffic` is off). That traffic leaves
through the ordinary default route.

### Selective routing

Inside the tunnel the client decides where each connection goes. VPN mode
keeps everything in the tunnel except the entries in the bypass list.
Bypass mode puts only the VPN-list entries into the tunnel. The client
matches domain entries by TLS SNI and IP addresses and CIDR ranges by the
destination. The kernel already keeps IP/CIDR bypass entries out: listed
destinations never enter the tun at all, so they work even while the
client is down.

### Killswitch

The package arms the blackhole route (metric `1000`) in table `880` while
a tun device is attached. The `attach` subcommand arms it, and `detach`
removes it. By default the blackhole exists only then: while the client
is connecting or dead, marked traffic falls through to the direct route
instead of being swallowed. A crashed client must not blackhole the LAN.
The *Strict killswitch* option on the Advanced tab (`blackhole_on_down`)
arms the blackhole even without a device. Marked traffic is then dropped
instead of leaking to the provider whenever it cannot reach the tunnel.
The generated config turns the client's own killswitch off
(`killswitch_enabled = false`). The routing table does the protecting
while the tunnel is up.

### DNS

Nothing intercepts or rewrites DNS. The generated config sets
`change_system_dns = false`, and the resolver of the router keeps serving
the LAN.

### Applying changes

Save & Apply regenerates only what the changed keys require. LAN-interface
and routing-parameter tweaks keep the tunnel up. `main.enabled`,
`main.mode`, `network.table` and `network.fwmark` tear the routing down
and rebuild it. Everything else (endpoint, routing profiles, proxy, MTU,
log level, the pinned certificate) restarts the client while the routing
survives. Anything outside the schema gets the fullest action, a full
restart, because a silently unapplied setting is worse than downtime.

### Proxy mode

With `main.mode=proxy` the generated config carries `[listener.socks]`
instead of `[listener.tun]`, because the client accepts exactly one
listener. The routing helper, the hotplug reattach and the firewall zone
are not involved. The killswitch, MTU, LAN-interface and routing options
have no effect.

---

## Limitations

- Only forwarded LAN traffic is routed by default. Traffic that the
  router itself originates leaves through the ordinary default route
  unless `include_router_traffic` is on.
- The client matches domain rules by the TLS SNI of the connection once
  the traffic is inside the tunnel. Connections without a TLS SNI (plain
  IP, non-TLS) can be matched only by IP or CIDR rules. DNS is not
  involved in the selection. BitTorrent peer connections have no SNI, so
  they stay direct unless an IP/CIDR rule routes them. The default bypass
  profile routes nothing.
- The client creates and names its own tun device. The package attaches
  the tunnel route to whatever client device appears, with hotplug and
  the ifindex snapshot written at service start. It records the device in
  `/var/etc/trusttunnel/device`. The package never attaches foreign tun
  devices (OpenVPN and similar). The firewall zone binds the attached
  device by name, never a `tun+` wildcard.
- **Proxy mode** does not route anything automatically. Only apps and
  devices that you configure for the SOCKS5 listener get the tunnel. The
  client resolves DNS for proxied connections through the tunnel
  (`endpoint.dns_upstream`). Apps that resolve locally and send bare IPs
  do not get that DNS. An open listener (no credentials) bound to
  `0.0.0.0` is reachable by the whole LAN. The client itself refuses to
  bind anything outside the loopback without the user/pass pair, so
  protect LAN-exposed listeners with credentials.

---

## Notes and caveats

- **Firewall zone.** The routing helper binds the zone to the concrete
  attached tun device, so the package never claims tun devices that other
  software creates. The zone section itself stays in the firewall config
  without a device binding while the service is off.
- **Repositories and signing.** The repositories are served from the
  GitHub Pages site of this project
  (`https://trusttunnel.github.io/TrustTunnelOpenWrt`), in the official
  OpenWrt layout `releases/<version>/packages/<arch>/trusttunnel/`. The
  `25.12.5` tree holds the apk feeds, and the `22.03.7` tree holds the
  opkg feeds. Each device architecture has one signed feed directory. A
  release is a `vX.Y.Z` tag push on master. The release workflow builds
  the packages, verifies them end to end, and publishes the repositories,
  the site and a GitHub release from the tag. The pipeline refuses runs
  that are not tag pushes. The site is served straight from CI, and no
  branch ever holds the packages.
- **Manual downloads.** Check a `.apk` or `.ipk` file from the release
  assets against the SHA-256 sums in the release notes.
- **Key rotation.** The signing keys rotate. Run the installer once more
  to refresh the copies on the router.
