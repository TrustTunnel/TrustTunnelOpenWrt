# AGENTS.md — TrustTunnelOpenWrt

Guidance for AI agents and human contributors working in this repository.

## What this project is

`TrustTunnelOpenWrt` is an independent implementation of an OpenWrt package
set for the [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel) client:

- `luci-app-trusttunnel` — a noarch LuCI application. It holds a procd
  service, a UCI-backed config, an rpcd ucode backend, four LuCI views
  and firewall/routing integration.
- `trusttunnel-client` — a per-architecture packaging of the vendor's
  prebuilt, statically-linked client binaries into `/opt/trusttunnel_client`.
- `install.sh` / `uninstall.sh` — router-side scripts that configure the
  package repositories and install/remove the packages.
- Signed package repositories (apk + opkg) and a GitHub Pages site, both
  produced by the release workflow.

Targets **OpenWrt 22.03+**: `opkg` on 22.03–24.10, `apk` on 25.12+. Supported
CPU families: `x86_64`, `aarch64`, `armv7l/armv8l`, `mips`, `mipsel`.

The package routes LAN traffic through the tunnel using **fwmark → routing
table 880 → the client's tun device**, backed by a blackhole killswitch.
It is configured through **named routing profiles** (VPN mode / Bypass mode).
See `README.md` and the topic documents next to it for the user-facing
description.

## Repository layout

```text
install.sh, uninstall.sh      Router-side installer/uninstaller (POSIX sh)
packages/
  trusttunnel/                The runtime package (the tunnel, no UI)
    Makefile                  OpenWrt package metadata
    root/etc/config/trusttunnel              Default UCI config (conffile)
    root/etc/init.d/trusttunnel              procd service script
    root/etc/uci-defaults/40-luci-trusttunnel  First-boot setup
    root/etc/hotplug.d/net/40-trusttunnel    Tun-device reattach hook
    root/usr/libexec/trusttunnel/            Runtime helpers (see below)
    root/usr/share/ucode/trusttunnel.uc      Shared ucode records module
                                              (constants + records parser)
  luci-app-trusttunnel/       The LuCI UI package (depends on the runtime)
    Makefile                  OpenWrt package metadata
    htdocs/luci-static/resources/view/trusttunnel/
      settings.js status.js log.js versions.js  LuCI client-side views
    root/usr/share/luci/menu.d/…json         Menu entry
    root/usr/share/rpcd/acl.d/…json          RPC/UCI ACL
    root/usr/share/rpcd/ucode/luci.trusttunnel  rpcd backend
  luci-app-trusttunnel-diagnostics/  The optional diagnostics add-on
    Makefile                  OpenWrt package metadata (depends on the app)
    htdocs/luci-static/resources/view/trusttunnel/
      diagnostics.js tools.js                LuCI client-side views
    root/usr/share/luci/menu.d/…json         Menu entries (Diagnostics, Tools)
  trusttunnel-client/         Per-arch packaging of vendor binaries
repo-site/                    Jekyll templates for the GitHub Pages package
                              repository site (index pages, layout)
tests/                        Shell test suite (see "Testing")
tests/backend/                Docker-based backend contract test + goldens
tests/integration/            Dockerized end-to-end suite: real install.sh
                              against a router and a TrustTunnel endpoint
                              container (see "Testing"; own workflow)
.github/workflows/ci.yml      CI gates (test + lint + contract checks)
.github/workflows/integration.yml  End-to-end suite on PRs/master/dispatch
.github/workflows/release.yml Release pipeline (build, sign, verify, publish)
key-build.pub, opkg-key.pub   PUBLIC halves of the repo signing keys (committed)
LICENSE                       Apache-2.0
```

There is no `docs/` directory. User documentation lives in the repository
root and is tracked on purpose (see the `.gitignore` comment). `README.md`
is the landing page. `CONFIGURATION.md`, `REFERENCE.md`, `BEHAVIOUR.md`,
`TROUBLESHOOTING.md`, `UPDATING.md` and `UNINSTALLING.md` carry the
how-to, reference and explanation content. The private halves of the
signing keys are GitHub secrets, never committed.

## Router-side scripts (`install.sh` / `uninstall.sh`)

The installer probes the environment (OpenWrt release, CPU family via
`uname -m`, package manager) and refuses unsupported hardware before it
changes anything. It points the package manager at the signed
repositories. For apk it writes `/etc/apk/repositories.d/trusttunnel.list`
(the `packages.adb` index URL) and `/etc/apk/keys/trusttunnel.pub`. For
opkg it writes a `src/gz trusttunnel` line in
`/etc/opkg/customfeeds.conf` and the feed key under both the stable name
and the usign fingerprint in `/etc/opkg/keys/`. It installs
`kmod-tun ip-full nftables curl ca-bundle`, and then
`luci-app-trusttunnel`. That package pulls the `trusttunnel` runtime and
`trusttunnel-client` as its dependencies. The installer restarts `rpcd`
and runs `/etc/uci-defaults/40-luci-trusttunnel` immediately. The script
is idempotent, so the boot-time run changes nothing. Finally the installer
restores the previous service state. A first install leaves the service
disabled. Re-running the installer updates the packages, the client
binary and the signing keys. `/etc/config/trusttunnel` is left alone
(conffile).

The uninstaller halts and disables the service. It removes the packages
in one call: the app, the runtime and the client, plus the optional
diagnostics package when installed. For opkg the dependents must come
first in the list. It tears down the repository configuration and the
signing keys. It deletes `/opt/trusttunnel_client`,
`/usr/share/trusttunnel`, `/var/cache/trusttunnel` and
`/var/etc/trusttunnel`. It cleans the leftovers of earlier package
versions (the stored lists, the `update_lists` cron line, any leftover
dnsmasq include). It prompts for the firewall zone (default: remove) and
the settings file (default: keep, because a reinstall keeps it). It
restarts `rpcd` and wipes the LuCI caches. It checks the kernel for
leftover routing state (the nft table, the rule for table 880, routes in
table 880). Anything still present means the service did not stop
cleanly, and a reboot will clear it. Flags: `-y` answers every prompt
with yes, and `-c` keeps `/etc/config/trusttunnel` unprompted. Shared
dependencies stay installed on purpose.

## Core architecture: the data flow

Everything on the router is driven by one UCI config, one derived TSV file,
one generated client config and one routing helper. The chain is:

```text
/etc/config/trusttunnel            (UCI: main, endpoint, network,
        |                               routing_profile*, domains)
        | uci-export                (dumps 31 fixed keys to TSV)
        v
/var/etc/trusttunnel/settings.tsv  (the "records"; consumed everywhere)
        | records.sh                (sourced accessor library: tt_get,
        |                               tt_list, tt_bool, tt_count,
        |                               tt_mode_is_proxy,
        |                               tt_assigned_profile_mode + the
        |                               shared tt_*_DEFAULT constants)
        | tt-uci.sh                 (sourced: tt_resolve_active_server,
        |                               the active-server resolution shared
        |                               by uci-export and the init script)
        | /usr/share/ucode/trusttunnel.uc (the ucode side of the same
        |                               constants + records parser)
        v
/var/etc/trusttunnel/client.toml    (gen-config; the client binary's config)
/var/etc/trusttunnel/endpoint.pem   (pinned cert, written by init script)
/var/etc/trusttunnel/device         (attached tun device name, routing helper)
/var/etc/trusttunnel/tun_since      (ifindex snapshot for hotplug ownership)
```

### The records schema

`uci-export` is the canonical emitter of the records TSV
(`section.option<TAB>value`, list options repeat their key). The emitted
key set is a hard contract: **31 keys, fixed order**. It is shared by
`records.sh`, `gen-config`, the `routing` helper, the change classifier
of the init script and the `records()` parser of the ucode backend.
Nothing outside the schema ever appears in the file (foreign UCI sections
must not leak). `endpoint.certificate` is deliberately NOT exported
(multi-line PEM). The init script writes it separately to `endpoint.pem`.

`uci-export` must never gain `set -u`: `/lib/functions.sh` reads
uninitialized variables and dies under it.

### Operation modes (tun / proxy)

`main.mode` (default `tun`, absent on upgraded installs means `tun`)
selects how the tunnel is delivered:

- **tun mode** — the classic wiring: `[listener.tun]` in `client.toml`,
  kernel routing via fwmark → table 880 → the client's tun device,
  hotplug reattach, the firewall zone bound to the attached tun device,
  MTU.
- **proxy mode** — `[listener.socks]` in `client.toml` (address and
  optional user/pass auth) instead. There is no kernel routing, no tun
  device, no hotplug and no zone. The client accepts EXACTLY ONE
  listener, so `gen-config` must never emit both blocks.

The mode gates: `gen-config` (listener block), the `mode_is_proxy()`
function of the init script (it skips `routing up`/attach in
`start_service` and installs the usage meter instead. It also skips the
routing reload in `apply_settings`), the `routing` helper (it refuses
`up` in proxy mode and `meter` in tun mode — defense in depth, the two
rulesets never coexist), the hotplug hook (exits early), the backend
(`status.mode`/`proxy_address`/`listener_up`, `probe` via
`curl --socks5-hostname`, the kernel group and tunnel check of
`diagnose`) and the views (mode picker, Proxy tab, verdict/facts).
`main.mode` maps to `restart_full` and `proxy.*` to `restart` in the
change classifier. The listener state is detected through
`/proc/net/tcp{,6}` (local port in hex, anchored grep — the fixed-width
sl column makes plain field splits unreliable).

### Routing profiles (the core feature)

`endpoint.routing_profile` names a `routing_profile` section by its `name`
option. `uci-export` (to emit the profile's records), `gen-config` and the
backend resolve the name. An empty or stale name uses the
direct-by-default rule (in tun mode nothing is routed, in proxy mode the
legacy `domains.direct` exclusions keep applying).

- **VPN mode** (`mode='vpn'`) → client `vpn_mode = "general"`, exclusions =
  `routing_profile.bypass_rules`.
- **Bypass mode** (`mode='bypass'`) → client `vpn_mode = "selective"`,
  exclusions = `routing_profile.vpn_rules` (the tunneled set).
- **No/unknown profile** → the direct-by-default fallback: in tun mode
  `vpn_mode = "selective"` with nothing tunneled. In proxy mode the
  legacy `general` with `domains.direct` exclusions stays (the SOCKS
  listener is the explicit routing there).

Rule entries accept a plain domain, `*.domain`, an IP, `IP:port`, or CIDR.
Domain matching happens inside the client (by SNI). The routing helper
additionally enforces IP/CIDR entries at the kernel (see below), so
listed destinations never enter the tun at all.

### Kernel routing state (`/usr/libexec/trusttunnel/routing`)

Subcommands: `dump | up | meter | attach | reattach | detach | down | status`.

- `up`: fwmark rule (priority 30820, guarded on the rule's own
  fwmark+table, not on the bare table number) → the nft ruleset (table
  `inet trusttunnel`, sets `tt_endpoint4/6` plus the selection sets
  `tt_route4/6` and `tt_bypass4/6`). The prerouting chain marks LAN
  traffic destined outside the endpoint sets and the private ranges.
  It marks only as far as the assigned profile allows: vpn mode marks
  everything except the IP/CIDR bypass entries, a purely address-based
  bypass profile marks only its VPN destinations, a bypass profile with
  a domain entry marks everything (the client splits by SNI), and no
  profile marks nothing (direct by default). The output chain mirrors
  the selection when `include_router_traffic` is on. The helper resolves
  endpoint addresses BEFORE the ruleset lands, because marked traffic
  would otherwise blackhole DNS. The blackhole follows
  `network.blackhole_on_down` (default `0`, fail-open). `up` removes a
  stale one, and `attach` arms it only while a tun device is attached.
  A dead or still-connecting client therefore falls through to the
  direct route instead of blackholing the LAN. With the option `1`
  (strict) `up` arms the blackhole, and only `down` removes it. Marked
  traffic is then dropped whenever it cannot reach the tunnel. `up`
  refuses to run when the records declare proxy mode.
- `meter`: the proxy-mode usage meter — byte counters on the SOCKS
  listener port in the same table: `tt_meter_in` (prerouting,
  `tcp dport <port> counter`, requests into the listener = tx) and
  `tt_meter_out` (output, `tcp sport <port> counter`, responses = rx).
  Port-only matching works for localhost and LAN-exposed listeners
  alike. A non-numeric port is refused. `meter` refuses in tun mode (the
  mirror of `up` refusing proxy mode — the two rulesets never coexist).
- `attach`: arm the blackhole (metric 1000 — the replace is idempotent
  in strict mode, and the whole killswitch is idempotent in fail-open
  mode), point table 880's default route at the client tun device
  (metric 1), bind the `trusttunnel` firewall zone to the CONCRETE
  device name (never a `tun+` wildcard, which would absorb foreign tun
  devices) and record the device name in `$OUT_DIR/device`.
- `detach`: remove the device route and the zone binding and forget the
  device record. The helper removes the blackhole only in the fail-open
  default. Strict mode keeps it armed, so the tunneled set is dropped
  instead of leaked until the client re-attaches.
- `down`: remove everything — the nft table, the fwmark rule and only
  this package's own routes. A table flush would wipe foreign routes in
  table 880. The client's device is never deleted.
- `status`: additionally reports `meter up` / `meter rx <bytes>` /
  `meter tx <bytes>` while both counter rules exist. A stale table after
  a port change reports no meter.
- Overrides for tests: `TT_IP`, `TT_NFT`, `TT_UCI`, `TT_FW`, `TT_LIBDIR`.

### Service lifecycle (`/etc/init.d/trusttunnel`)

procd service, `USE_PROCD=1`, `START=95`, `STOP=10`. Notable behaviors:

- `start_service` checks `main.enabled`. The gate applies to the
  automatic starts only. The explicit `start`/`restart` of the rpcd
  backend (the Status page buttons) sets `TT_START_NOW=1`, which
  bypasses the gate, so the tunnel runs on demand while "start on boot"
  is off (and stays off at the next boot). The function then prepares
  the client binary, the trust store, the records and the config
  regeneration. It waits for a default route and for the clock to catch
  up. It runs `routing up` in tun mode only. Proxy mode installs the
  usage meter instead. A failed meter only warns, because it must not
  take the tunnel down. Finally it starts the client with `procd` and
  attaches an already-existing tun device (tun mode only).
- `reload_service` → `apply_settings`: classifies the diff between the
  current records and the new export (`changed_keys` →
  `classify_change`). The result is one of
  `noop | reload | restart | restart_full`, and the function applies the
  cheapest correct action. Unknown keys must map to the FULLEST action,
  because a silently unapplied setting is worse than a restart.
- `restart` blocks SIGTERM and uses the `_TT_KEEP_ROUTING` handshake so
  routing survives the stop+start cycle. `abort_restart_cleanup` tears
  routing down when an interrupted restart left it hanging.
- `service_triggers`: reload on UCI change, restart on wan interface up.

### Hotplug (`/etc/hotplug.d/net/40-trusttunnel`)

On `ACTION=add` for a non-persistent tun device (`tun_flags` sysfs marker,
`IFF_PERSIST` bit 0x800 clear) belonging to a running service, the hook
reattaches the routing table's default route to the new device. It does
this only when the device's ifindex is above the `$OUT_DIR/tun_since`
snapshot. The init script writes that snapshot right before the client
starts (foreign tun devices such as OpenVPN's predate it and are never
attached). A `remove`/`unbind` event for the recorded device runs
`routing detach`. In the fail-open default the blackhole dies with the
tun device (marked traffic falls through to the direct route). In strict
mode it stays armed. The hook ignores devices that would displace a
working tunnel.

### uci-defaults (`/etc/uci-defaults/40-luci-trusttunnel`)

First-boot / reinstall setup. It dedups the `trusttunnel` firewall zone
and forwarding and creates them when missing (a DEVICE-LESS zone, `lan →
trusttunnel` forwarding. The routing helper binds the concrete tun on
attach). It clears any legacy `tt0`/`tun+` bindings the same way. It
seeds the Default routing profile. The profile uses `vpn` mode when a
legacy `domains.direct` list exists (its values move into the bypass
rules, which preserves the old full-tunnel semantics). Otherwise it uses
`bypass` mode, the direct-by-default default. The script creates the
UI-only `about` section that keys the Versions tab on the Settings page,
registers the rc.d link and clears LuCI caches. It is idempotent.
`install.sh` also runs it immediately.

### rpcd backend (`/usr/share/rpcd/ucode/luci.trusttunnel`)

The backend exposes `luci.trusttunnel` RPC methods. The ACL grants read on
`status ping probe check_domain log diagnose versions` and write on
`service import_config`:

- `status` — service state, device, rule/table/nft flags, endpoint,
  routing profile and effective `vpn_mode`, plus the cumulative usage
  counters (`rx_bytes`/`tx_bytes`, null when no counters exist: the tun
  device's `/proc/net/dev` in tun mode, the meter rules in proxy mode.
  The view diffs consecutive polls for rates).
- `versions` — what is installed, read-only: the luci app, the trusttunnel
  runtime, the optional diagnostics package (null when not installed) and
  the client package versions as apk/opkg report them (apk on 25.12+,
  opkg fallback for 22.03–24.10), plus the client binary's own
  `--version`. No network access.
- `service` — start/stop/restart/reload with a post-start liveness probe.
- `ping` — ping each configured endpoint host (or a given target).
- `probe` — external IP through the tunnel vs. direct (curl + api.ipify.org).
- `check_domain` — verdict for one domain against the effective rules.
- `log` — last N logread lines filtered by `trusttunnel`.
- `diagnose` — the chain walk: config → prerequisites → service → kernel
  → network, each check `{group, label, status, detail, hint}`, plus
  counts and an overall verdict.
- `import_config` — feeds server config text or a `tt://` link to the
  vendor's `setup_wizard`, parses the produced settings and returns the
  endpoint fields. The backend writes secrets with `write_secret_tmp`
  (mode 0600).

Imports note: the backend imports `fs` and `math` module functions
plus the shared `trusttunnel` module (constants + records parser, at
`/usr/share/ucode/trusttunnel.uc`). `ci.yml` gates that every used
module function is imported (both files) and that the backend compiles
under the pinned ucode, with an extra `-L` pointing at the tree's copy
of `/usr/share/ucode` so the named import resolves.

### LuCI views

The views are split across two packages. The core
(`luci-app-trusttunnel`) ships `status.js`, `settings.js`, `log.js` and
`versions.js`. The optional `luci-app-trusttunnel-diagnostics` ships
`diagnostics.js` and `tools.js` with their menu entries. Everything they
call (the single `luci.trusttunnel` backend object, the ACL, the menu
parent) lives in the core, so the optional package is a pure add-on.
Installing the core alone shows the four operational pages. Installing
the add-on adds the two check pages.

- `status.js` — verdict banner, facts (state/mode/server/proxy address,
  traffic), Start/Stop buttons and a rules preview for the assigned
  profile. In proxy mode without a profile the preview shows the legacy
  `domains.direct` list. In tun mode the preview states the
  direct-by-default state. The preview checks each effective rule via
  `check_domain`. The view polls every 10s. There is no restart button:
  from the UI it is stop + start, and the routing-preserving restart is
  internal to the settings apply path. The verdict is mode-aware: the
  "working" gate is `device_up` in tun mode and `listener_up` in proxy
  mode. The traffic row shows the poll-delta rates (a 10 s average) and
  the cumulative totals from `rx_bytes`/`tx_bytes`. A counter reset
  (reconnected tunnel) rebaselines the snapshot, and null counters hide
  the row.
- `log.js` — a tail of the system-log lines written by the client and
  the service (the `log` RPC). The view fetches them during `load()` so
  the first paint already shows them, and refreshes them in place with a
  10 s poll. The status verdicts and the backend diagnose hints point
  users here. The Export client logs button re-fetches the whole ring
  buffer (5000 lines) and downloads it as a timestamped text file via a
  Blob. It is purely client-side, with no backend or ACL surface.
- `settings.js` — a single tabbed `form.Map` whose sections become tabs
  (General, Server, Proxy, Routing profiles, Advanced), plus the
  Import… modal. The modal calls `import_config` and applies the results
  to pending UCI (nothing is written until Save & Apply). The endpoint
  section splits into Connection and Security inner tabs
  (`s.tab`/`s.taboption`), because map-level tabs key panes by the UCI
  section type, and two sections of the same type would collide. The
  General tab carries the operation-mode picker (`main.mode`). The Proxy
  tab carries the SOCKS5 listener settings (address and optional
  user/pass pair, validated both-or-neither). Extra tools: a read-only
  service line on General (via the `status` RPC), a Test connection
  modal on Server (`ping`), and a per-profile rule preview
  (`check_domain`) whose verdicts only apply to the assigned profile.
  The routing profile picker lives on General and `dns_upstream` on
  Advanced. Both write the endpoint section via `ucisection`. Config
  values are read via the `uci` module API (`uci.sections()`/`uci.get()`).
  Current LuCI resolves `uci.load()` with the package-name list, so the
  load() result is no data source.
- `diagnostics.js` — renders the diagnose checks grouped and ordered
  (config → prereq → service → kernel → network), problems first with a
  toggle for the rest, plus a Copy report button that serializes the last
  run into a textarea. The chain runs only on demand (Run checks).
  Backend strings are translated through the `DIAG_TEXT` map. New
  backend strings must be added there to be translatable.
- `tools.js` — the ad-hoc helpers that moved off the Diagnostics page:
  the domain verdict check, the endpoint ping and the tunnel-vs-direct
  address comparison. Each tool runs only on demand.
- `versions.js` — the Versions tab (moved out of the Settings page): a
  read-only page listing the installed TrustTunnel package, client
  package and client binary versions from the `versions` RPC. A missing
  package shows "not installed", and a failed RPC "unavailable".

## Packages and versioning

The four packages form one dependency chain:
`luci-app-trusttunnel-diagnostics` (optional) → `luci-app-trusttunnel` →
`trusttunnel` → `trusttunnel-client`. The app carries the UI, the runtime
carries the service, and the client package holds the vendor binaries.
Each section below records the exact DEPENDS of its package.

### `trusttunnel/Makefile`

- The runtime package holds the service, the routing, the records
  helpers and the UCI config, with no LuCI interface.
  `luci-app-trusttunnel` hard-depends on it (and the diagnostics add-on
  on the app), so a headless router can run the tunnel with
  `trusttunnel` alone.
- `PKG_VERSION` comes from the same `git describe --tags --abbrev=0`
  mechanism as the app (tag `vX.Y.Z` → `X.Y.Z`, same fallback, must track
  the last released version). The runtime releases with the app and can
  never be ahead of or behind it.
- `DEPENDS:=+trusttunnel-client +ip-full +nftables`. **Do not add
  `kmod-tun` or `ca-bundle` here**: they belong on
  `trusttunnel-client`'s own DEPENDS and arrive transitively. **Do not
  add `luci-base`, `curl` or `ucode-mod-math`**: they belong to the UI
  package (the runtime's files never invoke them). `test_deps.sh`
  enforces all of this.
- `PKG_BUILD_DIR` is overridden BEFORE `package.mk` is included.
  `Build/Prepare` stages the `root/` tree into it, and
  `Package/trusttunnel/install` installs from there.
- The conffiles block declares `/etc/config/trusttunnel` — the runtime
  owns the settings file, NOT the UI package (a conffile declared by two
  packages would fight over the file on upgrades).
- `Build/Compile` chmods the shipped scripts explicitly — the git index is
  NOT a reliable carrier of exec bits (zip downloads, Windows). `ci.yml`
  separately verifies index modes are `100755`.

### `luci-app-trusttunnel/Makefile`

- `PKG_VERSION` comes from `git describe --tags --abbrev=0` (tag `vX.Y.Z`
  → version `X.Y.Z`), falling back to the last released version (currently
  `1.0.33`). The fallback must track the latest release — the release
  workflow fails a tag build whose artifact does not carry the tag.
- `LUCI_DEPENDS:=+trusttunnel +luci-base +curl +ucode-mod-math`.
  **Do not add `trusttunnel-client`, `ip-full`, `nftables`, `kmod-tun` or
  `ca-bundle` here**: they belong on `trusttunnel`/`trusttunnel-client`
  and arrive transitively. `test_deps.sh` enforces this.
- No conffiles (`/etc/config/trusttunnel` is the runtime's) and no
  `Build/Compile` (no scripts ship in the UI package) — luci.mk copies
  `htdocs/` and `root/` as-is.

### `luci-app-trusttunnel-diagnostics/Makefile`

- The optional add-on ships the Diagnostics and Tools views plus their
  menu entries. Everything else (the backend, the ACL, the runtime, the
  other views) stays in the app package. It is NOT a dependency of the
  app, and the app must never `+luci-app-trusttunnel-diagnostics`. The
  add-on hard-depends on `+luci-app-trusttunnel` (the menu parent and
  the ACL live there).
- The version comes from the same tag-derived mechanism as the app
  (same fallback, must track the last released version). The package is
  released together with the app and can never be ahead of or behind it.
- No conffiles, no `Build/Compile` (no scripts to chmod). luci.mk copies
  `htdocs/` and `root/` as for the app.

### `trusttunnel-client/Makefile`

- Wraps the vendor's per-CPU-family tarballs
  (`trusttunnel_client-v$(PKG_VERSION)-linux-<family>.tar.gz`, currently
  `PKG_VERSION:=1.1.7`). On a vendor release, bump `PKG_VERSION` and the
  per-family `PKG_HASH` values together (digests come from the vendor's
  release API).
- `VENDOR_ARCH` maps `$(ARCH_PACKAGES)` (subtarget arch) → vendor family
  (x86_64 / aarch64 / armv7 / mips / mipsel). The `$(error …)` guard is
  wrapped in `ifneq ($(ARCH_PACKAGES),)` because the metadata dump
  evaluates the Makefile without target config.
- `PKG_BUILD_DIR` is overridden BEFORE `package.mk` is included (the
  tarball's top-level directory is named after the source).
- Installs `trusttunnel_client`, `setup_wizard`, their `.sig` files and
  `LICENSE` into `/opt/trusttunnel_client` (path hardcoded elsewhere).
- The vendor ships one tarball per CPU family but the package is built per
  OpenWrt subtarget arch — apk/opkg match arch byte-exactly.

## Testing

Run the full suite from the repo root:

```sh
sh tests/run.sh
```

The runner executes every `tests/test_*.sh` in its own `mktemp -d` scratch
directory (exported as `TT_TEST_TMP`) with stdin closed. It fails on any
failure. It counts and reports skipped tests (`tt_skip`, exit 77) as
"all tests passed (N skipped)". Docker-gated tests skip when docker is
absent, so the plain suite runs anywhere.

### Test conventions

- `tests/lib.sh` provides `assert_eq`, `assert_contains`, `assert_exit`,
  `_tt_pass`/`_tt_fail`, `tt_skip` (reports a skipped test, exit 77) and
  `tt_test_summary` (must be called at the end of each test). Counters
  live in files under `$TT_TEST_TMP` so assertions in subshells still
  count.
- Each test file starts with a header comment stating what contract it
  pins, and explains the WHY of tricky assertions.
- Fixtures: `tests/fixtures/records/{minimal,full,bypass}.tsv`.
- `tests/test_harness.sh` — self-test of the assertion helpers: proves
  they accept a passing and a failing check and that a failure inside a
  subshell is recorded in the counter files.
- `tests/test_hotplug.sh` — pure-shell scenario harness (no docker):
  sed-rewrites the script's hardcoded paths into a scratch tree, stubs
  init/routing/logger, and covers filters | guards | attach | invariants.
- `tests/test_views_runtime.sh` + `tests/views_runtime.js` — executes the
  views (searched across the core and the diagnostics package trees)
  against mocks that replicate the CURRENT LuCI runtime contracts
  (`uci.load()` resolving with the package-name list, no plain
  `form.Section`, `E()` reading only `arguments[2]`) and asserts the
  rendered output. Needs node (skips, exit 77, without it). This is the
  gate the syntax-only view checks cannot provide: the v1.0.16-1.0.20
  view bugs were runtime contract mismatches that parse fine and only
  fail when executed.
- Tests stub external commands (ip, nft, uci, logger, curl, logread) and
  honor `TT_*` overrides. See `test_routing.sh` (`TT_IP`, `TT_NFT`,
  `TT_LIBDIR`) and `test_uci_defaults.sh` (`TT_UCD_SCRIPT`,
  `TT_UCD_FILTER`).

### Docker-based tests

- `tests/backend/test_backend_contract.sh` — requires the pre-built
  pinned-ucode image (`docker build -q -t tt-ucode-gate -f
  tests/backend/Dockerfile tests/backend`. ci.yml builds it, locally
  build it once. The test skips — exit 77 — when it is missing). The test
  builds a rootfs lab from it (`tests/backend/lab.Dockerfile` + the stub
  tree under `tests/backend/rootfs/`), copies the LIVE backend into
  `tests/backend/mod/luci/trusttunnel.uc`, and byte-compares each method's
  output against `tests/backend/goldens/*.json` (baked rootfs state) and
  `goldens/healthy/*.json` (real tun device in a privileged container).
  **Do not edit `tests/backend/mod/luci/trusttunnel.uc`** — it is a copy
  overwritten by the test. Golden file names encode method + args
  (`golden_call` in the script). `TT_REGEN=1` rewrites the goldens from
  the live output instead of comparing. Use it only to land a deliberate
  backend change, and diff the result (a regen that touches anything
  beyond the intended files means the backend moved behavior elsewhere).
- `tests/test_uci_defaults.sh` — scenario harness running the real
  uci-defaults script in an OpenWrt rootfs container against scratch
  configs (fresh / duplicated / legacy / upgrade / side-effects /
  idempotent scenarios).
- `tests/install-harness.sh` — dry-run scenarios for `install.sh` in
  `openwrt/rootfs` containers with stubbed apk/opkg/wget/usign. NOT
  picked up by `tests/run.sh` (name has no `test_` prefix) but run as its
  own ci.yml step. Supports `TT_FILTER`.
- `tests/integration/` — the dockerized end-to-end suite. `build-sdk.sh`
  builds THIS tree's packages with the pinned OpenWrt SDK, then `run.sh`
  boots a real OpenWrt rootfs router (`/sbin/init`), runs the real
  `install.sh` against a hermetic signed repository, connects it to a
  real TrustTunnel endpoint container and asserts the install, service
  and traffic contracts (through-tunnel traffic arrives with the
  endpoint's source address, private traffic stays direct, the blackhole
  killswitch swallows marked traffic, install/uci-defaults/reload are
  idempotent). The later stages exercise the multiple-server model live.
  `switch` saves a second endpoint as the Backup server, selects it via
  `main.endpoint` + reload and asserts the records, client.toml and the
  traffic follow it (and back). `migrate` deletes the ACTIVE server's
  section, asserts the dangling selector stops the service, then runs
  the uci-defaults script exactly as the boot runs it and asserts the
  selection is re-pointed at the remaining server, which brings the
  tunnel back. An early pure-shell `archparse` stage pins the ipk
  arch/version derivation (`tests/integration/ipk-arch.sh`, shared with
  release.yml's opkg assembly) against every matrix arch-name shape — a
  last-underscore split once clipped `mipsel_24kc` to `24kc`, and the
  harness's opkg repo assembly derives its feed directory from the real
  artifact, so the regression fails the install assertions too. Knobs:
  `TT_PM=apk|opkg`, `TT_REPO_DIR`, `TT_FILTER`,
  `TT_LOGS_DIR`, `TT_RELEASE_TAG` — see `tests/integration/README.md`.
  Docker-gated (skip 77), deliberately NOT picked up by `tests/run.sh`.
  `integration.yml` runs it on PRs/master/dispatch, and the release
  pipeline reuses it against the release's own artifacts. Every network
  request in the docker harnesses is retried, because transient
  registry/mirror/lab-net failures must not fail a run: the
  `retry`/`retry_out` helpers in `run.sh`, and the same shape in
  `build-sdk.sh`, `restricted-feeds.sh`, `gui/run.sh` and
  `test_backend_contract.sh`.
- `tests/integration/restricted-feeds.sh` — the SDK feed pins. It prints
  the `EXTRA_FEEDS` value (base/packages/luci only — the
  routing/telephony/video clones are dead weight, and the client build
  uses base only). `--verify` compares the hardcoded pins against the
  SDK image's `feeds.conf.default` and fails on drift. The pins are the
  OTHER half of the SDK pin: when release.yml bumps the SDK version,
  update them together with `VERSION_PATH`.

### View contract and GUI tests

- `tests/view-contract.js` — a node gate (its own ci.yml step) that
  cross-checks the views against the backend without a browser:
  1. every `rpc.declare({object, method, params})` in the views must name
     an object/method the backend registers (parsed from
     `luci.trusttunnel.uc`) and one the ACL grants (read or write), and
     the declared params must be a subset of the backend's `args`.
  2. every literal label/detail/hint the diagnose method emits — as
     pinned by the backend contract goldens — must be a key of the
     `DIAG_TEXT` map in `diagnostics.js` (templated values like versions,
     addresses and ping averages are exempt via the allowlist, which
     documents the backend expression producing each pattern). A new
     literal string in a golden without a `DIAG_TEXT` entry fails the
     gate. Cover a new state in the backend contract test first, then
     this gate sees it.
- `tests/gui/` — the browser layer of the view contract. The REAL views
  (real `luci.js` loader, real `form.Map`, real RPC batching) run in a
  headless chromium inside the pinned `mcr.microsoft.com/playwright`
  image against a stubbed ubus backend (`tests/gui/stub/server.js`) that
  serves the backend contract goldens byte-identically, so the browser
  sees exactly the responses `tests/backend` pins. The specs
  (`specs/{status,settings,diagnostics}.spec.js`) assert on the rendered
  DOM and on the RPC frames the stub records (`/__stub` control
  endpoint). `tests/gui/run.sh` orchestrates: docker-gated (skip 77),
  fetches the pinned luci-base resources (`openwrt-25.12` commit,
  `TT_GUI_REF` to override) into `tests/gui/.cache`, installs the pinned
  `@playwright/test` into `tests/gui/node_modules`, then runs stub +
  specs inside the image. Both cache dirs are gitignored.
- `tests/gui/dev.sh` — the manual development loop. It starts the same
  stub on the host (no docker, no build, no release) against the same
  pinned luci-base cache, prints every view URL and the `/__stub` cheat
  sheet, and serves the resources with no-cache headers, so an edit +
  plain reload is the whole cycle. Router state is faked live through the
  control endpoint (for example
  `curl -X POST -d '{"set":{"status":{"running":false,"enabled":true}}}' http://127.0.0.1:8123/__stub`.
  `{"reset":true}` restores the goldens). The stub serves the views
  live from this tree — it keeps no copy — so the preview cannot
  drift from the checked-out branch. The router runs the installed
  release, so a difference just means the two are on different
  revisions (unreleased view changes here, or a branch behind main).
  The luci-base pin and fetch live in `tests/gui/lib-luci.sh`, shared
  with `run.sh` so the dev loop and the test suite can never drift.
- The luci-base pin matters: the loader, `dom.create()`'s argument
  handling (`E()` reads only `arguments[2]` — children must be arrays,
  and a DOM node as the second argument is treated as the attribute
  object) and the uci module API (`uci.load()` resolves with the
  package-name list. `TypedSection` maps sections by `s['.name']`, which
  rpcd fills in) all move between LuCI generations. When the pin is
  bumped, re-run `tests/gui/run.sh` and the suite against the old pin to
  see what changed.

## CI gates (`.github/workflows/ci.yml`)

Every step is a contract gate. The tree must pass all of them. Locally
reproducible equivalents:

- Executable bits of shipped scripts must be `100755` in the index.
- Tag pushes must not regress the release: new tag's commit must be newer
  than the previous tag's (`v*` and `client-v*` tags alike).
- Release runs are tag-gated: the release pipeline's `gate` job refuses
  any run that is not a `v*` or `client-v*` tag push. `workflow_dispatch`
  is the sole exception (main only, repositories + site, never a
  release).
- `sh tests/run.sh` (includes the node-gated views runtime test, which
  skips without node).
- `docker build -q -t tt-ucode-gate -f tests/backend/Dockerfile
  tests/backend` (the contract-test lab image), then
  `sh tests/backend/test_backend_contract.sh` and
  `sh tests/install-harness.sh` — a skip (exit 77) passes the step.
- `node tests/view-contract.js` — the RPC-surface and DIAG_TEXT gate.
- `sh tests/gui/run.sh` — the Playwright GUI suite. A skip (exit 77)
  passes the step.
- Shellcheck (pinned `koalaman/shellcheck:v0.11.0`, `-s sh
  --severity=error`) over the explicit file list — every shipped script
  and test harness file, a missing file fails the step:
  `docker run --rm -v "$PWD:/src" -w /src koalaman/shellcheck:v0.11.0 -s sh --severity=error <files>`
- `sh -n` on the init script.
- ucode gates: every used module function is imported. The file compiles
  under ucode v0.0.20250529 (built with fs+math only — see the CI recipe
  for the exact cmake flags). The compiler must also REJECT a broken file
  (negative control).
- All JSON under `packages/` must parse (menu/acl).
- Views: every used LuCI module (`ui dom rpc uci form view poll fs network
  validation`) must be declared with `'require <mod>'`. Each view must
  parse as JS via `node vm.Script` (views end in a top-level `return`, so
  the check wraps them in a function expression).

Separate from ci.yml, `.github/workflows/integration.yml` runs the
dockerized end-to-end suite on PRs, master pushes and manual dispatch. A
matrix job builds this tree's packages with the pinned SDKs (with the
`restricted-feeds.sh --verify` gate against the SDK image's
`feeds.conf.default`), then one job per package manager runs
`tests/integration/run.sh` against the built repositories. It is its own
workflow on purpose — the SDK builds are the slow part, and the fast
contract gates must not wait for them. The release pipeline reuses the
same harness against the release's own artifacts.

## Release pipeline (`.github/workflows/release.yml`)

Triggered by `v*` and `client-v*` tag pushes (both build GitHub
releases) and `workflow_dispatch` (repos + site only. Plain branch CI
never publishes).

The `gate` job runs first and refuses any run that is not a `v*` or
`client-v*` tag push. `workflow_dispatch` is the sole exception: it must
run on master and republishes the repositories and the site only, never a
GitHub release. A mis-triggered run fails before any SDK work starts.

- `build` — the LuCI app packages (`luci-app-trusttunnel` and the
  optional `luci-app-trusttunnel-diagnostics`) plus the `trusttunnel`
  runtime via
  `openwrt/gh-action-sdk@v7` on 25.12.5 (apk) and 22.03.7 (ipk). The SDK
  is pinned with `VERSION_PATH` to the release tarballs — **never the
  snapshot SDK** (snapshot feeds hit a curl Kconfig recursive dependency)
  — and the SDK feeds are restricted to the needed set via
  `tests/integration/restricted-feeds.sh`, whose `--verify` gate checks
  the hardcoded pins against the SDK image's `feeds.conf.default`
  (update them together with the SDK bump). `FEED_DIR` must be an
  absolute path and must contain `.git` (luci.mk findrev derives the
  version from it). `fail-fast: false`. Artifact file names must match
  the tag. The job is skipped on `client-v*` tags, because a client-only
  release does not touch the app.
- `build-client` — the client package per subtarget arch (the full matrix
  is in the workflow. The ipk list is the apk list minus
  `aarch64_cortex-a76`). apk files get an `-<arch>` suffix and an
  `ARCH-<arch>` marker for repository assembly. ipk names already carry
  the arch. A row first checks whether the same version is already
  published and reuses it when the recipe matches — a copy of the client
  Makefile travels at each release tree's root
  (`releases/<version>/trusttunnel-client.Makefile`, one per tree, never
  inside the feed directories) for exactly that diff, so a recipe change
  without a version bump still forces a rebuild. On a `client-v*` tag an
  extra assertion checks the built package carries the tag's version
  (the mirror of the app's tag-matching assertion, scoped to client tags
  because the client version legitimately differs from the app version).
- `verify-integration` — the same `tests/integration/run.sh` harness the
  PR workflow runs, executed against the packages THIS pipeline just
  built (no SDK rebuild. The release's own x86-64 artifacts are consumed
  directly). `publish-repo` waits for it, so only a behaviorally tested
  release ships. The job is skipped on `client-v*` tags: the app is
  unchanged (it passed the suite at its own release, and the client-bump
  PR already ran the suite against this exact tree via
  `integration.yml`), and the publish-repo verification below installs
  the new client against the repositories' current app.
- `publish-repo` — downloads the artifacts plus every prior release's
  packages via `gh release download` (only the current package set is
  merged: the early `-lite` releases are filtered out, and an ipk-less
  first release is skipped, not failed),
  assembles:
    - per-arch signed repositories in the official OpenWrt layout —
      `releases/<version>/packages/<arch>/trusttunnel/` on the site, one
      release tree per package-manager era (the tree segment is the
      OpenWrt release the packages were built against: `25.12.5` for apk,
      `22.03.7` for opkg — bump together with the SDK pins, and with the
      `TT_REPO_APK_RELEASE`/`TT_REPO_OPKG_RELEASE` constants in
      install.sh), each holding per-arch feed directories with the apk
      index (`apk mkndx --allow-untrusted` + `apk adbsign` with
      `secrets.TT_APK_SIGN_KEY`) or the opkg index, the public keys and
      every released version of the packages. Cumulative: prior client
      packages of every version are placed by their `-<arch>` asset suffix
      (apk) or their `_<arch>` name segment (ipk), and prior noarch LuCI
      packages land in every feed dir, so every released version stays
      installable — pinning or downgrading an older client stays possible.
      The package managers install the highest version unless a router
      pins one (apk: `apk add trusttunnel-client=<ver>-r<rel>`. opkg has
      no `pkg=version` CLI syntax, so pinning means installing the
      versioned ipk from the feed),
    - per-arch opkg feeds (`ipkg-make-index.sh` fetched from openwrt-22.03,
      run once per feed directory, manifest fields stripped, gzip,
      `usign -S` with `secrets.TT_OPKG_SIGN_KEY`. The signature covers the
      UNCOMPRESSED `Packages`). The two-empty-line padding works around
      usign's SHA-512 size bug — keep it. The feeds index the prior ipks
      too (every version kept). The arch/version derivation from
      the ipk file names is shared with the integration harness
      (`tests/integration/ipk-arch.sh`, sourced by both) and pinned by the
      harness's `archparse` stage — the arch names contain underscores, and
      a last-underscore split once clipped `mipsel_24kc` to `24kc`.
    - verification: installs the built repos into fresh rootfs containers
      exactly as `install.sh` sets them up (25.12.0 apk, 23.05.6 and
      24.10.8 opkg) and asserts the installed client's `--version` matches
      the version the build shipped. On a `client-v*` release this is what
      proves the repositories now serve the new client (installed together
      with the current app via the unversioned dependency). When the feed
      carries more than one client version, the newest older one is
      installed alone in a fresh container — apk by `pkg=<version>` from
      the signed index, opkg from its exact ipk in the feed (asserted to
      be listed in the index first) — and its `--version` asserted, so
      the pinning contract is exercised end to end.
    - GitHub release upload (tag pushes only, single writer): a `v*` tag
      carries the app + client files, a `client-v*` tag the client files
      alone (the app is unchanged and already lives on its own release).
    - GitHub Pages site assembly: `repo-site/` templates + generated index
      pages — the releases index and the per-tree pages (each tree page
      lists its architectures, linking straight to the feed pages), the
      per-feed pages list what their directories actually hold, and the
      two structural levels in between (`packages/`,
      `packages/<arch>/`) are one-line redirect stubs (`_layouts/
      redirect.html`), so browsing takes three clicks with no URL 404ing
      (`sed r` substitutions must keep file-read and delete on separate
      lines). Jekyll renders the site, and Pages deploys it
      (`permissions: contents, pages, id-token`).

On a `client-v*` tag the pipeline takes the client-only path. `build`
and `verify-integration` are skipped, `build-client` runs (and its
version assertion), and `publish-repo` assembles the SAME cumulative
trees with the app packages merged in from the prior releases (there is
no fresh app build to place), verifies the new client against the
current app, uploads a `client-vX.Y.Z` release and redeploys the site.
`publish-repo` gates on `!failure()` instead of the implicit
`success()` so the skipped jobs do not block it, while any real failure
still does. Routers pick the new client up on the next `apk upgrade` /
`opkg upgrade` — the app depends on `+trusttunnel-client` unversioned.

Repositories are served from the Pages site, not from release assets.
Release assets are per-tag snapshots, while the repositories accumulate
every prior release (the "keep every prior release installable"
contract). Pages serves the files byte-identically, which the package
managers rely on. No branch ever holds packages.

## Conventions and invariants

- **Shell**: POSIX `/bin/sh` everywhere, shellcheck-clean at error
  severity. Use `set -u` where safe — never in `uci-export` (see above).
  Keep the explanatory header comments. This codebase documents contracts
  in comments and in test headers, and the CI gates treat several of those
  as the specification.
- **Line endings**: LF is enforced for all text via `.gitattributes`
  (CRLF in a script breaks `/bin/sh\r` on the router).
- **Commits**: lowercase `area: description` style
  (`docs:`, `release:`, `fix:`, `cleanup:`, `backend:`, `service:`,
  `tests:`, `makefile:`, `gen-config:`, …). The subject is a single
  line, short (under 72 chars), imperative and without a trailing
  period. One concern per commit — a subject that joins several
  concerns (for example with a semicolon) signals a commit that must
  be split. A body is optional. When present, wrap it at 72 chars,
  explain what changed and why, and do not prefix paragraphs with
  file names. Merged to `master` via PRs. Feature work happens on
  branches.
- **i18n**: the interface is English-only — no translation package is
  built or installed. New user-visible strings in views use `_()`, and
  backend strings shown in the Diagnostics view use the `DIAG_TEXT` map
  in `diagnostics.js`.
- **Hardcoded paths** (keep consistent): `/etc/config/trusttunnel`,
  `/etc/init.d/trusttunnel`, `/opt/trusttunnel_client`,
  `/usr/libexec/trusttunnel/{uci-export,gen-config,routing,records.sh}`,
  `/var/etc/trusttunnel/{settings.tsv,client.toml,endpoint.pem,device,tun_since}`,
  `/etc/uci-defaults/40-luci-trusttunnel`,
  `/etc/hotplug.d/net/40-trusttunnel`. Kernel constants: fwmark `0x9527`,
  table `880`, rule priority `30820`, blackhole metric `1000`.
- **Scope**: the package must not touch dnsmasq, `https-dns-proxy`, cron,
  or anything beyond the listed files (`uninstall.sh` only cleans their
  leftovers from earlier versions of the package). Do not add such touches.
- **Killswitch**: the generated config keeps the client's own killswitch
  off (`killswitch_enabled = false`). The routing table blackhole is the
  killswitch, gated by `network.blackhole_on_down`. The default `0`
  (fail-open) arms it on attach and removes it on detach, so a dead or
  still-connecting client falls through to the direct route instead of
  blackholing the LAN. With `1` (strict) `up` arms it and keeps it until
  `down`, so marked traffic is dropped whenever it cannot reach the
  tunnel. `change_system_dns = false` — DNS is never intercepted.
- **Keys**: `key-build.pub` / `opkg-key.pub` are public. Never commit
  private keys. Repo signing keys rotate — run `install.sh` again on a
  router to refresh them.
- **Version discipline**: the `PKG_VERSION` fallback in the app Makefile
  must equal the last released version. Tags drive release contents. The
  CI rejects tags older than the previous tag and packages that do not
  match the tag.
- **Do not rebuild goldens casually**: backend behavior changes require
  updating the golden set in `tests/backend/goldens/` and its `healthy/`
  and proxy-mode variants, and the `driver.uc` normalizations must stay
  in sync.

## Typical tasks

- **Change a setting end-to-end**: UCI option in
  `root/etc/config/trusttunnel` → `uci-export` schema (30-key contract,
  see its header and `schema-keys:` comments) → `gen-config` emission →
  init script `change_class` mapping → settings.js field (+ validation)
  → records fixtures/tests → goldens if the backend surfaces it.
- **Verify a shell change**: `sh tests/run.sh`, targeted test
  (`sh tests/test_gen_config.sh` and similar), then shellcheck as in CI.
- **Verify a backend change**: `sh tests/backend/test_backend_contract.sh`
  (build the `tt-ucode-gate` image first if missing), plus the ucode
  import/compile gates from ci.yml.
- **Release**: bump client vendor version/hashes if needed, ensure the
  Makefile fallback equals the previous release, tag `vX.Y.Z` (tag must
  point to a commit newer than the previous tag), push. The release
  workflow builds, signs, verifies and publishes.
