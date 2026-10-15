# Configuring TrustTunnel

Open **Services → TrustTunnel → Settings** in LuCI. The page has six
tabs:

- **General**: a read-only service line, the **operation mode** switch
  (TUN routes the whole LAN; Proxy runs a SOCKS5 listener instead), the
  service switch ("start on boot") — the service starts at boot only
  while it is on; the Start button on the Status page runs it on demand
  even while it is off — the log level, and the **Active server**
  selector that picks which saved server the tunnel uses right now.
  After Save & Apply, start the service with the Start button on the
  Status page.
- **Server**: the saved servers — several can be stored, one is active
  (see General). Every server is its own block with **Connection** and
  **Security** inner tabs, a unique **name**, its own routing-profile
  picker and DNS upstreams; **Add** stores another server, **Delete**
  removes one. The **Import…** button takes what your server produces —
  the text of a config file, or a `tt://` link — and populates that
  server's fields: addresses, the TLS host name, credentials, the
  transport, `custom_sni`, `client_random`, plus anti-DPI, IPv6 and
  certificate-verification switches. Everything can also be typed by
  hand, and a **Test connection** button pings the ACTIVE server's
  addresses.
- **Proxy**: the SOCKS5 listener used in proxy mode — the listen
  address (`IP:port`, default `127.0.0.1:1080`) and optional user/pass
  authentication (set both or neither). Bind `0.0.0.0:1080` (or the
  router's LAN address) to serve the whole LAN — the client then
  **requires** the user/pass pair and refuses to start without it;
  `127.0.0.1:1080` serves the router itself and needs no credentials.
- **Routing profiles**: the Default profile (bypass mode, no rules) is
  already seeded here — a fresh install routes nothing until rules are
  added, so BitTorrent and other non-SNI traffic stays direct unless you
  explicitly route it. Every profile gets a mode — **VPN** (everything is
  tunneled except the bypass-list entries) or **Bypass** (only the
  VPN-list entries are tunneled) — and two rule lists. A **Rule preview**
  button shows how each entry of the profile is treated; the profile is
  assigned to a server with its picker on the Server tab (each server
  carries its own). The Status page offers the same preview for whichever
  profile is assigned right now.
- **Advanced**: rarely needed — the MTU, the LAN interfaces, the
  strict-killswitch switch, router-traffic routing, the client's own DNS
  upstreams, and the internal routing parameters (firewall mark,
  routing table). The routing options apply in TUN mode only.
- **Versions**: what is installed — the app package and the client
  package versions exactly as the package manager reports them, plus
  the client binary's own version. Read-only: updates are delivered
  through the package repository (see [UPDATING.md](UPDATING.md)).

The options behind every tab are in [REFERENCE.md](REFERENCE.md). Rule
entries accept domains, wildcards, IP addresses and CIDR ranges — the
exact forms are in the [settings reference](REFERENCE.md#settings-reference).

The same configuration headless, over UCI:

```sh
uci set trusttunnel.endpoint.hostname='tt.example.net'
uci add_list trusttunnel.endpoint.address='198.51.100.7:443'
uci set trusttunnel.endpoint.username='router'
uci set trusttunnel.endpoint.password='change-me'
uci add_list trusttunnel.endpoint.dns_upstream='1.1.1.1'
uci set trusttunnel.endpoint.custom_sni='tt.example.net'
uci set trusttunnel.endpoint.client_random='0a1b2c'
uci add trusttunnel routing_profile
uci set trusttunnel.@routing_profile[-1].name='Direct'
uci set trusttunnel.@routing_profile[-1].mode='bypass'
uci add_list trusttunnel.@routing_profile[-1].vpn_rules='*.example.com'
uci add_list trusttunnel.@routing_profile[-1].vpn_rules='192.0.2.0/24'
uci set trusttunnel.endpoint.routing_profile='Direct'
uci set trusttunnel.main.enabled='1'
uci commit trusttunnel
/etc/init.d/trusttunnel enable
/etc/init.d/trusttunnel start
```

The routing-profile block is optional: without it (or with a name that
matches no profile), the client falls back to the direct-by-default rule
in TUN mode — traffic goes out directly until a profile explicitly
routes it. In proxy mode the fallback keeps the legacy `domains.direct`
list as the "do not bypass" exclusions.

Several servers can be saved, one active. The shipped `endpoint` section
already carries `name 'Default'` and is selected by `main.endpoint`. To
save another server, add a second `endpoint` section with its own unique
`name`, and switch the active one at any time — the service picks the
new server up on the next reload:

```sh
uci add trusttunnel endpoint
uci set trusttunnel.@endpoint[-1].name='Backup'
uci set trusttunnel.@endpoint[-1].hostname='tt.example.net'
uci add_list trusttunnel.@endpoint[-1].address='198.51.100.8:443'
uci set trusttunnel.main.endpoint='Backup'
uci commit trusttunnel
/etc/init.d/trusttunnel reload
```

Only the ACTIVE server's settings are in effect — and only its
credentials and pinned certificate ever reach the generated client
configuration.

The same configuration in **proxy mode** — a LAN-accessible SOCKS5
listener with authentication:

```sh
uci set trusttunnel.main.mode='proxy'
uci set trusttunnel.proxy.address='0.0.0.0:1080'
uci set trusttunnel.proxy.username='lan'
uci set trusttunnel.proxy.password='lan-pass'
uci set trusttunnel.main.enabled='1'
uci commit trusttunnel
/etc/init.d/trusttunnel enable
/etc/init.d/trusttunnel start
```

Point the SOCKS5-capable app or device at `0.0.0.0:1080` (the router's
address as seen from the LAN) with the credentials above.
