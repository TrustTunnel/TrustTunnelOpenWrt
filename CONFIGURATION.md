# Configuring TrustTunnel

Open **Services → TrustTunnel → Settings** in LuCI. The page has six
tabs:

- **General**: holds a read-only service line, the **operation mode**
  switch, the service switch ("start on boot"), the log level and the
  **Active server** selector. The operation mode switch selects TUN mode
  (the whole LAN uses the tunnel) or Proxy mode (a SOCKS5 listener
  instead). The service starts at boot only while the switch is on. The
  Start button on the Status page runs the service on demand, even while
  the switch is off. The **Active server** selector picks the saved
  server that the tunnel uses now. After Save & Apply, start the service
  with the Start button on the Status page.
- **Server**: holds the saved servers. You can store several servers,
  but only one is active (see General). Every server is its own block
  with **Connection** and **Security** inner tabs, a unique **name**,
  its own routing-profile picker and DNS upstreams. **Add** stores
  another server, and **Delete** removes one. You can also type every
  field by hand, and the **Test connection** button pings the addresses
  of the ACTIVE server. The **Import…** button takes the output of your
  server, for example the text of a config file or a `tt://` link, and
  fills these fields of that server:
    - the addresses, the TLS host name and the credentials
    - the transport, `custom_sni` and `client_random`
    - the anti-DPI, IPv6 and certificate-verification switches
- **Proxy**: holds the SOCKS5 listener for proxy mode. Set the listen
  address (`IP:port`, default `127.0.0.1:1080`) and the optional
  user/pass authentication. Set both the user name and the password, or
  neither. Bind `0.0.0.0:1080` (or the LAN address of the router) to
  serve the whole LAN. The client then **requires** the user/pass pair
  and refuses to start without it. `127.0.0.1:1080` serves the router
  itself and needs no credentials.
- **Routing profiles**: holds the Default profile (bypass mode, no
  rules). A fresh install routes nothing until you add rules, so
  BitTorrent and other non-SNI traffic stays direct unless you route it
  explicitly. Every profile gets a mode — **VPN** (the tunnel carries
  everything except the bypass-list entries) or **Bypass** (the tunnel
  carries only the VPN-list entries) — and two rule lists. The **Rule
  preview** button shows how the system treats each entry of the
  profile. Assign the profile to a server with the picker on the Server
  tab (each server carries its own). The Status page offers the same
  preview for the assigned profile.
- **Advanced**: rarely needed. It holds the MTU, the LAN interfaces, the
  strict-killswitch switch and router-traffic routing. It also holds the
  DNS upstreams of the client and the internal routing parameters
  (firewall mark and routing table). The routing options apply in TUN
  mode only.
- **Versions**: shows what is installed. It lists the app package and
  the client package versions exactly as the package manager reports
  them, plus the version of the client binary. The page is read-only.
  Updates arrive through the package repository (see
  [UPDATING.md](UPDATING.md)).

The options behind every tab are in [REFERENCE.md](REFERENCE.md). Rule
entries accept domains, wildcards, IP addresses and CIDR ranges. The
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

The routing-profile block is optional. Without it (or with a name that
matches no profile), the client uses the direct-by-default rule in TUN
mode. Traffic goes out directly until a profile routes it. In proxy mode
the fallback keeps the legacy `domains.direct` list as the "do not
bypass" exclusions.

You can save several servers, but only one is active. The shipped
`endpoint` section already carries `name 'Default'`, and
`main.endpoint` selects it. To save another server, add a second
`endpoint` section with its own unique `name`. You can switch the active
server at any time. The service uses the new server after the next
reload:

```sh
uci add trusttunnel endpoint
uci set trusttunnel.@endpoint[-1].name='Backup'
uci set trusttunnel.@endpoint[-1].hostname='tt.example.net'
uci add_list trusttunnel.@endpoint[-1].address='198.51.100.8:443'
uci set trusttunnel.main.endpoint='Backup'
uci commit trusttunnel
/etc/init.d/trusttunnel reload
```

Only the settings of the ACTIVE server apply. Only its credentials and
its pinned certificate reach the generated client configuration.

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

Point the SOCKS5-capable app or device at `0.0.0.0:1080` (the LAN
address of the router) with the credentials above.
