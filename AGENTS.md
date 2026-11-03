# AGENTS.md — TrustTunnelOpenWrt

Guidance for AI agents and human contributors working in this repository.

## Table of Contents

- [Project Overview](#project-overview)
- [Technical Context](#technical-context)
- [Project Structure](#project-structure)
- [Build And Test Commands](#build-and-test-commands)
- [Contribution Instructions](#contribution-instructions)
- [Code Guidelines](#code-guidelines)
    - [System Design](#system-design)
    - [Architecture](#architecture)
    - [Code Quality](#code-quality)
    - [Testing](#testing)
    - [Dependency Management](#dependency-management)
    - [Configuration & Documentation](#configuration--documentation)
    - [Other](#other)

## Project Overview

`TrustTunnelOpenWrt` is an independent implementation of an OpenWrt package
set for the [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel) client.
It runs the tunnel on the router, delivers it to the LAN through kernel
routing and exposes a LuCI interface for configuration and diagnostics. It
targets OpenWrt 22.03 and newer on the CPU families the vendor client
supports. See `README.md` and the topic documents next to it for the
user-facing description.

## Technical Context

- **Language/Version**: POSIX `/bin/sh` for the router scripts and the test
  harnesses. JavaScript for the LuCI views (the LuCI 25.12 runtime).
  ucode v0.0.20250529 for the rpcd backend (the CI pin). GNU make for the
  package metadata.
- **Primary Dependencies**: the OpenWrt packages `ip-full`, `nftables`,
  `kmod-tun`, `ca-bundle`, `curl`, `luci-base` and `ucode-mod-math`, plus
  the vendor `trusttunnel_client` binary.
- **Storage**: the UCI config at `/etc/config/trusttunnel`. The generated
  files live under `/var/etc/trusttunnel/`.
- **Testing**: the shell suite (`sh tests/run.sh`), the docker-based
  contract, install, GUI and integration suites, and the node gates.
- **Target Platform**: OpenWrt 22.03+ routers (`opkg` on 22.03–24.10,
  `apk` on 25.12+) on `x86_64`, `aarch64`, `armv7l/armv8l`, `mips` and
  `mipsel`.
- **Project Type**: other — an OpenWrt package set: a router-side service,
  its LuCI app and the client binaries.
- **Performance Goals**: N/A.
- **Constraints**: the vendor client accepts exactly one listener. The
  package must not touch dnsmasq, cron or another package's configuration.
  The router scripts must stay POSIX `/bin/sh` (busybox). Five CPU families
  are supported.
- **Scale/Scope**: one router per installation. The signed repositories
  keep the last few released versions installable. Older versions stay on
  their GitHub releases.

## Project Structure

```text
.
├── install.sh, uninstall.sh    # router-side installer and uninstaller (POSIX sh)
├── packages/
│   ├── trusttunnel/            # the runtime: service, routing, records, UCI config
│   ├── luci-app-trusttunnel/   # the LuCI app: views, rpcd backend, ACL, menu
│   ├── luci-app-trusttunnel-diagnostics/  # optional Diagnostics and Tools views
│   └── trusttunnel-client/     # vendor client binaries, per-architecture
├── tests/
│   ├── run.sh                  # shell suite entry point
│   ├── lib.sh                  # assertion helpers
│   ├── test_*.sh               # the suite's tests
│   ├── fixtures/               # records fixtures and the schema key list
│   ├── tools/                  # schema key regeneration helper
│   ├── release/                # client packager image, script and feed selector
│   ├── license-clean/          # upstream-blob license gate
│   ├── backend/                # dockerized backend contract test and goldens
│   ├── gui/                    # Playwright suite, stub server and dev loop
│   └── integration/            # dockerized end-to-end suite and SDK build
├── repo-site/                  # Jekyll templates for the Pages package site
├── .github/workflows/          # ci.yml, integration.yml, release.yml
├── key-build.pub, opkg-key.pub # public halves of the signing keys
├── README.md, CONFIGURATION.md, REFERENCE.md, ...  # user documentation
└── LICENSE                     # Apache-2.0
```

## Build And Test Commands

- **Build**: `sh tests/integration/build-sdk.sh` builds this tree's packages
  with the pinned OpenWrt SDK (one-time, ~15–30 min). The release pipeline
  builds in CI with `openwrt/gh-action-sdk@v7`.
- **Test**: `sh tests/run.sh` runs the shell suite. The docker-gated suites
  are `docker build -q -t tt-ucode-gate -f tests/backend/Dockerfile
  tests/backend` followed by `sh tests/backend/test_backend_contract.sh`,
  `sh tests/install-harness.sh`, `sh tests/gui/run.sh` and
  `sh tests/integration/run.sh`.
- **Lint**: shellcheck (`docker run --rm -v "$PWD:/src" -w /src
  koalaman/shellcheck:v0.11.0 -s sh --severity=error <files>`, with the
  file list in `ci.yml`), `sh -n
  packages/trusttunnel/root/etc/init.d/trusttunnel`,
  `node tests/view-contract.js` and `sh tests/license-clean/check.sh`.
- **Format**: N/A — the project has no formatter.
- **Run**: `sh tests/gui/dev.sh` starts the LuCI dev loop on the host
  against the stub backend. Running the service itself needs a router or
  the integration lab.

## Contribution Instructions

- You MUST verify every change with the linter and the test gates before
  you finish.

  Use the following commands:
    - `sh tests/run.sh` to run the shell suite, plus the targeted test for the area you changed (`sh tests/test_gen_config.sh` and similar)
    - `docker run --rm -v "$PWD:/src" -w /src koalaman/shellcheck:v0.11.0 -s sh --severity=error <files>` to run the linter, with the file list in `ci.yml`
    - `node tests/view-contract.js` to check the RPC surface and the `DIAG_TEXT` map
    - `sh tests/backend/test_backend_contract.sh` (after `docker build -q -t tt-ucode-gate -f tests/backend/Dockerfile tests/backend`) to check the backend goldens
    - `sh tests/gui/run.sh` to run the browser contract suite

- You MUST update the tests for the changed code: the shell tests under
  `tests/`, the records fixtures, and the backend goldens when a backend
  method's output changes.

- You MUST run all tests and make them pass.

- You MUST update the Project Structure section of this file when the
  project structure changes.

- When a prompt asks for a refactoring or an improvement, you MUST capture
  the resulting rule in the relevant Code Guidelines subsection of this
  file.

- After completing a task, you MUST verify the written code against the
  Code Guidelines in this file.

- You MUST update the affected user documentation in the same change:
  `README.md`, `CONFIGURATION.md`, `REFERENCE.md`, `BEHAVIOUR.md`,
  `TROUBLESHOOTING.md`, `UPDATING.md` or `UNINSTALLING.md`.

- You MUST keep the explanatory header comments and the contracts they
  state. The CI gates treat several of those comments as the specification.

- When you change a UCI option, you MUST update the whole chain: the option
  in `root/etc/config/trusttunnel` → the `uci-export` schema (see its header
  and `schema-keys:` comments) → the `gen-config` emission → the init
  script's `change_class` mapping → the `settings.js` field and its
  validation → the records fixtures and tests → the goldens if the backend
  surfaces it.

- You MUST write commits in the project style: lowercase
  `area: description`, one concern per commit (see [Other](#other)).

- Before a release, you MUST bump the vendor version and hashes if needed,
  keep the Makefile fallback at the previous release, and tag `vX.Y.Z` on a
  commit newer than the previous tag.

## Code Guidelines

### System Design

The project is an OpenWrt package set, and its runtime is a router. These
rules follow from that:

- Every router-side script MUST be POSIX `/bin/sh` (busybox): no bashisms,
  no GNU-only flags.
- `/etc/config/trusttunnel` is the single source of truth. The files under
  `/var/etc/trusttunnel/` are generated. Regenerate them, never edit them.
- Kernel state MUST be idempotent: `routing up` tolerates a stale state,
  and `routing down` removes only this package's own state. Never flush a
  shared table.
- The package MUST NOT touch dnsmasq, `https-dns-proxy`, cron or any other
  package's configuration.
- The vendor client binary is a black box. Configure it through the
  generated `client.toml`. Never patch or wrap the binary.
- The runtime package MUST stay UI-free (no LuCI dependency), so a headless
  router can run the tunnel with `trusttunnel` alone.
- The optional diagnostics package MUST stay optional: the app never
  depends on it.

### Architecture

The universal principles, as this project applies them:

- **Separation of Concerns** — the views render, the rpcd backend reads
  state, the helpers change it.
- **Single Responsibility Principle** — one helper per job: `uci-export`
  emits the records, `gen-config` renders the TOML, `routing` owns the
  kernel state.
- **Dependency Direction** — the views depend on the backend, the backend
  on the records and the config. Nothing lower depends on the UI.
- **Explicit Boundaries** — the records TSV is the interface between the
  config and the runtime. Foreign UCI sections must not leak into it.
- **Data Flow Clarity** — one config → one TSV → one TOML → the client.
  Every generated file has exactly one writer.
- **Minimize Coupling, Maximize Cohesion** — the shared constants live in
  `records.sh` and `trusttunnel.uc`, not in each caller.
- **Make Invalid States Impossible** — `gen-config` never emits both
  listener blocks, and the routing helper refuses a mode mismatch.
- **Observability Built-in** — the client and the service log through
  syslog, and the backend's `diagnose` walks the whole chain.
- **Keep It Boring** — POSIX sh, UCI, nftables and ip. Add no new runtime
  dependency.

The layers, from the UI down to the kernel:

- **LuCI views** (`packages/luci-app-trusttunnel/htdocs/.../settings.js`,
  `status.js`) render the state and call the backend.
- **rpcd backend**
  (`packages/luci-app-trusttunnel/root/usr/share/rpcd/ucode/luci.trusttunnel`)
  reads the state for the UI, controls the service and imports configs.
- **Runtime helpers**
  (`packages/trusttunnel/root/usr/libexec/trusttunnel/`) emit the records,
  render the client config and own the kernel state.
- **Client binary and kernel** — the vendor `trusttunnel_client` plus the
  nftables and ip state it drives.

```text
LuCI views
     ↓ rpcd
rpcd backend
     ↓ uci + records
Runtime helpers (uci-export, gen-config, routing, records.sh, tt-uci.sh)
     ↓ generated files + kernel state
Client binary (trusttunnel_client)
```

The views may call only the backend. The backend and the init script may
read the records. Only the routing helper touches nftables and the ip
rules. No layer may depend on a layer above it.

#### The data flow

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

#### The records schema

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

#### Operation modes (tun / proxy)

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

#### Routing profiles (the core feature)

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

#### Kernel routing state (`/usr/libexec/trusttunnel/routing`)

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

#### Service lifecycle (`/etc/init.d/trusttunnel`)

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

#### Hotplug (`/etc/hotplug.d/net/40-trusttunnel`)

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

#### uci-defaults (`/etc/uci-defaults/40-luci-trusttunnel`)

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

#### rpcd backend (`/usr/share/rpcd/ucode/luci.trusttunnel`)

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

#### LuCI views

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

#### Router-side scripts (`install.sh` / `uninstall.sh`)

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

### Code Quality

- **Shell**: POSIX `/bin/sh` everywhere, shellcheck-clean at error
  severity. Use `set -u` where safe — never in `uci-export`:
  `/lib/functions.sh` reads uninitialized variables and dies under it.
- **Comments**: keep the explanatory header comments. This codebase
  documents contracts in comments and in test headers, and the CI gates
  treat several of those as the specification.
- **Line endings**: LF is enforced for all text via `.gitattributes`. A
  CRLF script breaks as `/bin/sh\r` on the router.
- **Naming**: the shared shell helpers use the `tt_` prefix (`tt_get`,
  `tt_list`, `tt_bool`, `tt_count`, `tt_mode_is_proxy`,
  `tt_assigned_profile_mode`). The views and the backend use camelCase for
  functions (`serializeDiagnose`, `renderDiagnose`).
- **Error handling**: fail loudly with a non-zero exit, except where a
  failure must not take the tunnel down — a failed proxy usage meter warns
  and continues. Scripts log through `logger` or stderr.
- **Executable bits**: shipped scripts MUST be `100755` in the git index.
  `Build/Compile` chmods them explicitly, because the index is not a
  reliable carrier of exec bits (zip downloads, Windows).
- **Static analysis gates** — all run in `ci.yml`, and a docker-gated step
  that skips with exit 77 passes. They are shellcheck over the explicit
  file list, `sh -n` on the init script, the ucode import and compile
  gates (the compiler must also REJECT a broken file, as a negative
  control), the JSON parse, the view module and `node vm.Script` checks,
  and the license-clean check (`sh tests/license-clean/check.sh`, which
  fails when a blob in the tree is byte-identical to a file of the
  upstream `NooBiToo/TrustTunnelOpenWrt` repository). Do not weaken or
  bypass a gate. Fix the code instead.

### Testing

- **Suite layout**: `tests/run.sh` runs every `tests/test_*.sh` in its own
  `mktemp -d` scratch directory (exported as `TT_TEST_TMP`) with stdin
  closed. It fails on any failure and reports skipped tests (`tt_skip`,
  exit 77) as "all tests passed (N skipped)". Docker-gated tests skip when
  docker is absent, so the plain suite runs anywhere.
- **Helpers**: `tests/lib.sh` provides `assert_eq`, `assert_contains`,
  `assert_exit`, `_tt_pass`/`_tt_fail`, `tt_skip` and `tt_test_summary`
  (call it at the end of each test). Counters live in files under
  `$TT_TEST_TMP`, so assertions in subshells still count.
- **Test file conventions**: every test file starts with a header comment
  stating the contract it pins, and explains the WHY of tricky assertions.
- **Fixtures and test data**:
  `tests/fixtures/records/{minimal,full,bypass}.tsv`,
  `tests/fixtures/schema-keys.txt` (regenerate with
  `sh tests/tools/dump-schema-keys.sh`) and
  `tests/fixtures/client-hashes.txt` (the vendor tarball hashes; update
  it with the Makefile on a vendor bump).
- **Mocking**: tests stub external commands (ip, nft, uci, logger, curl,
  logread) and honor `TT_*` overrides. See `test_routing.sh` (`TT_IP`,
  `TT_NFT`, `TT_LIBDIR`) and `test_uci_defaults.sh` (`TT_UCD_SCRIPT`,
  `TT_UCD_FILTER`).
- **The views runtime test** (`tests/test_views_runtime.sh` +
  `tests/views_runtime.js`) executes the views against mocks of the CURRENT
  LuCI runtime contracts (`uci.load()` resolving with the package-name
  list, no plain `form.Section`, `E()` reading only `arguments[2]`). It is
  the gate the syntax-only view checks cannot provide: the v1.0.16–1.0.20
  view bugs were runtime contract mismatches that parse fine and fail only
  when executed. It needs node and skips (exit 77) without it.
- **Docker-based suites**:
    - `tests/backend/test_backend_contract.sh` requires the pre-built
      pinned-ucode image and builds a rootfs lab from it
      (`tests/backend/lab.Dockerfile` + the stub tree under
      `tests/backend/rootfs/`). It copies the LIVE backend into
      `tests/backend/mod/luci/trusttunnel.uc` and byte-compares each
      method's output against `tests/backend/goldens/*.json` (baked rootfs
      state) and `goldens/healthy/*.json` (a real tun device in a
      privileged container). **Do not edit
      `tests/backend/mod/luci/trusttunnel.uc`** — the test overwrites it.
    - `tests/test_uci_defaults.sh` runs the real uci-defaults script in an
      OpenWrt rootfs container against scratch configs (fresh, duplicated,
      legacy, upgrade, side-effects and idempotent scenarios).
    - `tests/install-harness.sh` runs dry-run `install.sh` scenarios in
      `openwrt/rootfs` containers with stubbed apk/opkg/wget/usign. It is
      not picked up by `tests/run.sh` and supports `TT_FILTER`.
    - `tests/integration/` is the end-to-end suite. `build-sdk.sh` builds
      THIS tree's packages with the pinned OpenWrt SDK, then `run.sh` boots
      a real OpenWrt rootfs router (`/sbin/init`), runs the real
      `install.sh` against a hermetic signed repository, connects it to a
      real TrustTunnel endpoint container and asserts the install, service
      and traffic contracts (through-tunnel traffic arrives with the
      endpoint's source address, private traffic stays direct, the
      blackhole killswitch swallows marked traffic, and
      install/uci-defaults/reload are idempotent). The later stages
      exercise the multiple-server model live. `switch` saves a second
      endpoint as the Backup server, selects it via `main.endpoint` +
      reload and asserts the records, client.toml and the traffic follow
      it (and back). `migrate` deletes the ACTIVE server's section, asserts
      the dangling selector stops the service, then runs the uci-defaults
      script exactly as the boot runs it and asserts the selection is
      re-pointed at the remaining server, which brings the tunnel back. An
      early pure-shell `archparse` stage pins the ipk arch/version
      derivation (`tests/integration/ipk-arch.sh`, shared with release.yml's
      opkg assembly) against every matrix arch-name shape. Knobs:
      `TT_PM=apk|opkg`, `TT_REPO_DIR`, `TT_FILTER`, `TT_LOGS_DIR` and
      `TT_RELEASE_TAG` — see `tests/integration/README.md`. The suite is
      docker-gated (skip 77) and deliberately not picked up by
      `tests/run.sh`. Every network request in the docker harnesses is
      retried, because transient registry, mirror and lab-net failures must
      not fail a run.
- **The client packager test** (`tests/test_package_client.sh`) builds
  the real packager image (`tests/release/packager.Dockerfile`), generates
  a package for every row of the release client matrix from fake vendor
  tarballs, and checks each package's fields, files, payload and CPU-family
  mapping against `packages/trusttunnel-client/Makefile`. It is
  docker-gated (skip 77) and uses a work directory under `$HOME`, because
  Docker Desktop on macOS does not share `$TT_TEST_TMP`. The hash fixture
  pins the Makefile's `PKG_HASH` parsing.
- **The view-contract gate** (`tests/view-contract.js`) cross-checks the
  views against the backend without a browser: every `rpc.declare` must
  name a registered method that the ACL grants and declare a subset of its
  args, and every literal diagnose string in the goldens must be a key of
  the `DIAG_TEXT` map. Cover a new state in the backend contract test
  first, then this gate sees it.
- **The GUI suite** (`tests/gui/`) runs the REAL views in headless
  chromium against a stub ubus backend that serves the goldens
  byte-identically. The specs assert on the rendered DOM and on the RPC
  frames the stub records. `tests/gui/run.sh` is docker-gated and fetches
  the pinned luci-base resources into `tests/gui/.cache`. `tests/gui/dev.sh`
  is the manual development loop. It serves the views live from this tree
  and fakes the router state through the `/__stub` control endpoint. Both
  cache dirs are gitignored.
- **Verification before merge**: every gate in `ci.yml` must pass, plus
  `integration.yml` for the end-to-end suite.
- **Goldens**: do not rebuild them casually. `TT_REGEN=1` rewrites the
  goldens from the live output. Use it only to land a deliberate backend
  change, and diff the result. The `driver.uc` normalizations must stay in
  sync.

### Dependency Management

The project ships four packages. Three are mandatory, and one is optional.
The mandatory packages form one dependency chain:

```text
luci-app-trusttunnel-diagnostics  (optional)
  └── luci-app-trusttunnel
        └── trusttunnel
              └── trusttunnel-client
```

The rules:

- Pin the vendor tarball explicitly: `PKG_VERSION` plus the per-family
  `PKG_HASH` values, bumped together from the vendor's release API.
- Keep the `PKG_VERSION` fallback in the app, runtime and diagnostics
  Makefiles equal to the last released version (currently `1.0.0`).
- Prefer the OpenWrt base packages. The runtime depends only on
  `+trusttunnel-client +ip-full +nftables`. The app depends only on
  `+trusttunnel +luci-base +curl +ucode-mod-math`. Add a dependency only
  for significant value.
- Keep the dependency direction transitive. **Do not add `kmod-tun` or
  `ca-bundle` to the runtime** (they belong on `trusttunnel-client`'s
  DEPENDS), and **do not add `trusttunnel-client`, `ip-full`, `nftables`,
  `kmod-tun` or `ca-bundle` to the app**.
- The diagnostics add-on hard-depends on `+luci-app-trusttunnel`. The app
  must never depend on the add-on.
- `tests/test_deps.sh` enforces the two rules above, and that every system
  binary the installed files invoke is named in a package's DEPENDS.

**Rationale**: the packages install on a router with limited space, and
every dependency adds install and maintenance cost. Fewer, well-vetted
dependencies keep the package set small and predictable.

#### `trusttunnel/Makefile`

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

#### `luci-app-trusttunnel/Makefile`

- `PKG_VERSION` comes from `git describe --tags --abbrev=0` (tag `vX.Y.Z`
  → version `X.Y.Z`), falling back to the last released version (currently
  `1.0.0`). The fallback must track the latest release — the release
  workflow fails a tag build whose artifact does not carry the tag.
- `LUCI_DEPENDS:=+trusttunnel +luci-base +curl +ucode-mod-math`.
  **Do not add `trusttunnel-client`, `ip-full`, `nftables`, `kmod-tun` or
  `ca-bundle` here**: they belong on `trusttunnel`/`trusttunnel-client`
  and arrive transitively. `test_deps.sh` enforces this.
- No conffiles (`/etc/config/trusttunnel` is the runtime's) and no
  `Build/Compile` (no scripts ship in the UI package) — luci.mk copies
  `htdocs/` and `root/` as-is.

#### `luci-app-trusttunnel-diagnostics/Makefile`

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

#### `trusttunnel-client/Makefile`

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

### Configuration & Documentation

- **Runtime configuration**: everything lives in `/etc/config/trusttunnel`
  (the UCI sections `main`, `endpoint`, `network`, `routing_profile` and
  `domains`). The files under `/var/etc/trusttunnel/` are generated from
  it. Never edit them, always regenerate them.
- **Hardcoded paths** (keep consistent): `/etc/config/trusttunnel`,
  `/etc/init.d/trusttunnel`, `/opt/trusttunnel_client`,
  `/usr/libexec/trusttunnel/{uci-export,gen-config,routing,records.sh}`,
  `/var/etc/trusttunnel/{settings.tsv,client.toml,endpoint.pem,device,tun_since}`,
  `/etc/uci-defaults/40-luci-trusttunnel` and
  `/etc/hotplug.d/net/40-trusttunnel`.
- **Kernel constants**: fwmark `0x9527`, table `880`, rule priority
  `30820` and blackhole metric `1000`.
- **Secrets**: the private halves of the signing keys are GitHub secrets,
  never committed. The public halves (`key-build.pub`, `opkg-key.pub`) are
  committed. Do not commit generated files or caches (see `.gitignore`).
- **Documentation**: there is no `docs/` directory. User documentation
  lives in the repository root and is tracked on purpose: `README.md` is
  the landing page, and `CONFIGURATION.md`, `REFERENCE.md`, `BEHAVIOUR.md`,
  `TROUBLESHOOTING.md`, `UPDATING.md` and `UNINSTALLING.md` carry the
  how-to, reference and explanation content. Update the affected document
  in the same change as the code.

### Other

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
- **CI workflows**: `.github/workflows/ci.yml` holds the contract gates,
  `integration.yml` runs the end-to-end suite on PRs, master pushes and
  manual dispatch, and `release.yml` is the release pipeline below.
  Name a release job that only packages a prebuilt vendor artifact
  `package-*`, not `build-*`. The client job is `package-client`. It
  uses the shared packager image, not the SDK. Keep
  `tests/test_package_client.sh` in the shell suite, so every generated
  package stays checked against the Makefile.
- **Version discipline**: tags drive release contents. The CI rejects tags
  older than the previous tag and packages that do not match the tag.

#### Release pipeline (`.github/workflows/release.yml`)

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
- `prepare-packager` — builds the small client packager image
  (`tests/release/packager.Dockerfile`) and uploads it as the
  `package-client-packager` artifact. The image carries the pinned apk
  tools and `tests/release/package-client.sh`. It is built once per run,
  so the client matrix rows do not each pull an SDK image or clone a
  feed. The base image is pinned by digest.
- `package-client` — the client package per subtarget arch (the full
  matrix is in the workflow. The ipk list is the apk list minus
  `aarch64_cortex-a76`). Each row reuses the shared packager image and
  runs `tests/release/package-client.sh`, which reads the Makefile,
  downloads the vendor tarball and checks its SHA-256. No SDK or feed
  clone runs here. apk files get an `-<arch>` suffix and an
  `ARCH-<arch>` marker for repository assembly. ipk names already carry
  the arch. A row first checks whether the same version is already
  published and reuses it when the recipe matches — copies of the client
  Makefile, the packager script and the packager Dockerfile travel at
  each release tree's root
  (`releases/<version>/trusttunnel-client.Makefile`,
  `releases/<version>/package-client.sh` and
  `releases/<version>/packager.Dockerfile`, one set per tree, never
  inside the feed directories) for exactly that diff, so a recipe change
  without a version bump still forces a rebuild. On a `client-v*` tag an
  extra assertion checks the generated package carries the tag's version
  (the mirror of the app's tag-matching assertion, scoped to client tags
  because the client version legitimately differs from the app version).
- `verify-integration` — the same `tests/integration/run.sh` harness the
  PR workflow runs, executed against the packages THIS pipeline just
  packaged (no SDK rebuild. The release's own x86-64 artifacts are consumed
  directly). `publish-repo` waits for it, so only a behaviorally tested
  release ships. The job is skipped on `client-v*` tags: the app is
  unchanged (it passed the suite at its own release, and the client-bump
  PR already ran the suite against this exact tree via
  `integration.yml`), and the publish-repo verification below installs
  the new client against the repositories' current app.
- `publish-repo` — downloads the artifacts plus the retained prior
  releases' packages via `gh release download` (only the current package
  set is merged: the early `-lite` releases are filtered out, and an
  ipk-less first release is skipped, not failed). The published site has
  a hard 1 GB limit, so the feed keeps only the newest
  `TT_FEED_KEEP_RELEASES` releases (3 by default, the 3-5 range is the
  supported one) instead of every release ever published.
  `tests/release/select-releases.sh` picks the tags to download: the
  newest keep-1 prior releases plus the current release, and always the
  newest `v*` app release when the current release is not a `v*` one.
  The app-only release contributes its app/runtime packages only, so its
  client does not consume a retention slot. A feed with only one
  retained client version skips the pin verification. It then
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
      the retained versions of the packages. Retained: prior client
      packages are placed by their `-<arch>` asset suffix (apk) or their
      `_<arch>` name segment (ipk), and prior noarch LuCI packages land
      in every feed dir, so every retained version stays installable —
      pinning or downgrading an older retained client stays possible. A
      selector bug that merges too much fails the 900 MB size guard and
      the client-version count guard before the deploy. The package
      managers install the highest version unless a router pins one
      (apk: `apk add trusttunnel-client=<ver>-r<rel>`. opkg has no
      `pkg=version` CLI syntax, so pinning means installing the
      versioned ipk from the feed),
    - per-arch opkg feeds (`ipkg-make-index.sh` fetched from openwrt-22.03,
      run once per feed directory, manifest fields stripped, gzip,
      `usign -S` with `secrets.TT_OPKG_SIGN_KEY`. The signature covers the
      UNCOMPRESSED `Packages`). The two-empty-line padding works around
      usign's SHA-512 size bug — keep it. The feeds index the retained
      prior ipks too. The arch/version derivation from
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
and `verify-integration` are skipped, `package-client` runs (and its
version assertion), and `publish-repo` assembles the same capped trees,
always merging the newest `v*` app release (there is no fresh app build
to place), verifies the new client against the current app, uploads a
`client-vX.Y.Z` release and redeploys the site.
`publish-repo` gates on `!failure()` instead of the implicit
`success()` so the skipped jobs do not block it, while any real failure
still does. Routers pick the new client up on the next `apk upgrade` /
`opkg upgrade` — the app depends on `+trusttunnel-client` unversioned.

Repositories are served from the Pages site, not from release assets.
Release assets are per-tag snapshots of every release, while the
repositories keep only the newest `TT_FEED_KEEP_RELEASES` releases (the
"last few releases installable" contract). An older version is still
downloadable from its own release, but it is not in the feed. Pages
serves the files byte-identically, which the package managers rely on.
No branch ever holds packages.
