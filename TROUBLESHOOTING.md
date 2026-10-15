# Troubleshooting

Work through the entry that matches the symptom. The
[Diagnostics page](REFERENCE.md#diagnostics-page) reports the state of
most of these checks.

- **The service will not start.** Read the client log with
  `logread -e trusttunnel`. A missing `ca-bundle` refuses the start,
  unless a certificate is pinned or verification is skipped. A missing
  `/opt/trusttunnel_client/trusttunnel_client` means the client package
  is not installed. Run install.sh in that case. The automatic starts
  (boot, WAN up, a config reload) refuse while `main.enabled` is off. The
  "start on boot" switch is the service switch, not only a boot
  preference. The Start button on the Status page is an explicit start.
  It runs the tunnel on demand, even while the switch is off, and the
  tunnel stays off at the next boot.
- **Handshakes fail on a freshly flashed router.** The client validates
  the server certificate against the wall clock. The service waits up to
  30 seconds for the clock to catch up and logs a warning when the clock
  stays behind. Synchronize the clock (NTP) and restart the service.
- **The device exists but the tunnel never comes up.** The client creates
  the device, not the package. If the device exists but the carrier is
  down, the client has not established the connection. The client log
  says why.
- **Marked traffic is dropped.** While the tun device exists but its
  route is not attached, marked traffic falls into the blackhole. The
  "Route attached to the device" check reports it. Restart the service.
  When the tun device is gone entirely, the default fail-open mode
  removes the blackhole with it, and marked traffic falls through to the
  direct route. With the *Strict killswitch* option on, the traffic
  stays dropped until the client re-attaches.
- **Nothing goes through the tunnel.** Check the marking chain. The
  traffic must be forwarded from a listed LAN interface into the
  `trusttunnel` zone (the `lan → trusttunnel` forwarding rule), and the
  assigned routing profile must route it (no profile means direct).
  "Compare the external address" shows the same IP both ways when the
  tunnel is not used.
- **The firewall zone is missing from the live ruleset.** The kernel
  checks report it. Run `/etc/init.d/firewall reload`. The uci-defaults
  script recreates the zone on the next boot, and the routing helper
  binds it to the attached tun device on service start.
- **The interface shows a new value, the client behaves as before.**
  Save & Apply updates the applied state only after it regenerates the
  client configuration. When the interface and the applied state
  diverge, the service log shows where the apply failed.
