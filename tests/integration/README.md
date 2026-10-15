# Integration harness (`tests/integration/`)

An end-to-end suite. It installs this project **as intended** into a
dockerized OpenWrt router and connects the router to a real TrustTunnel
endpoint container. It then verifies the traffic through the tunnel. The
harness runs the real `install.sh` against a locally assembled and signed
package repository. It configures the router with the router's own tools
(`uci`, `/etc/init.d/*`). It asserts the install contract, the service
contract and the traffic contract.

## Running

```sh
sh tests/integration/build-sdk.sh          # build THIS tree's packages (one-time, ~15-30 min)
TT_PM=apk sh tests/integration/run.sh      # OpenWrt 25.12, apk
TT_PM=opkg sh tests/integration/run.sh     # OpenWrt 22.03, opkg
```

Both variants need docker and internet access, because install.sh updates
the default OpenWrt package repositories. Without docker the harness
reports SKIP (exit 77), like the other docker-gated tests. `tests/run.sh`
does not pick it up on purpose (the runner globs `tests/test_*.sh`). CI
runs it as its own workflow.

### Where the packages come from

The harness prefers, in order:

1. `TT_REPO_DIR` — a flat dir of built packages (the CI artifact layout)
2. `dist/` — the output of `tests/integration/build-sdk.sh`. That script
   builds `luci-app-trusttunnel` and `trusttunnel-client` from **this
   tree** with the OpenWrt SDK, the same recipe that the SDK action of
   the release pipeline uses
3. the latest GitHub release (`TT_RELEASE_TAG` pins a specific one)

Tree-built packages matter. The published release can lag the tree, and
a stale package would fail the tunnel assertions for a reason unrelated
to the harness. The pinned-certificate fix was the first such case.

The harness assembles the repository per run with a **fresh** signing key
(EC P-256 for apk, usign for opkg). The private key exists only in the
scratch directory. The served public key is the one that install.sh
installs.

### What a run does

| Stage | What it verifies |
| --- | --- |
| `preflight` | docker, `/dev/net/tun` |
| `archparse` | regression. The ipk arch/version derivation shared with release.yml (`ipk-arch.sh`) returns every matrix arch-name shape intact. A last-underscore split once clipped `mipsel_24kc` to `24kc` and `x86_64` to `64` |
| `pkgs` | the two packages for the PM (luci-app + client), from TT_REPO_DIR / dist/ / release |
| `repo` | hermetic repo assembly and signing (apk: mkndx and adbsign, opkg: ipkg-make-index and usign) |
| `serve` | repo server on the lab network (44.55.66.0/24), polled until it answers |
| `router` | openwrt/rootfs booted with `/sbin/init`, network configured via `uci import` + `/etc/init.d/network restart`, firewall settled |
| `endpoint` | pinned TrustTunnel endpoint release (hash-checked), self-signed cert with SAN `tt.test`, listening on TCP+UDP 8443 |
| `targets` | two REMOTE_ADDR oracle servers: on the lab net (through-tunnel target) and on the docker default bridge (private, direct target). Both answer directly before the tunnel |
| `install` | the real `install.sh` with `TT_REPO_URL` pointing at the served repo |
| `asserts` | install contract: packages installed, client binary runs, Default profile + firewall zone seeded, service registered but not started, repo entry + keys |
| `connect` | endpoint configured via uci (hostname, address, credentials, the **pinned** certificate), service enabled+started, tunnel up |
| `traffic` | service running, tun0 + routing state, client log connected, client.toml carries the pin, through-tunnel traffic arrives with the **endpoint's** source address, private traffic stays direct |
| `lifecycle` | the blackhole killswitch (kernel-level: with the device down, the marked lookup fails into the blackhole), the killswitch window (a SIGKILLed client drops the blackhole with its tun, so marked traffic falls through to the direct route until the respawned client re-attaches), a clean stop tears the routing down and a start restores it, install.sh / uci-defaults / reload idempotence, and the endpoint log shows the tunneled CONNECTs |
| `switch` | a second, twin endpoint container. The Backup server is saved next to the Default one (same fields, its own address) and made active via `main.endpoint` + reload. The records and client.toml follow the active server, the tunnel moves to the new endpoint's source address, and switching back restores the original |
| `migrate` | the boot-migration contract. The ACTIVE server's section is deleted via `uci` (a CLI edit), the dangling selector stops the service (direct traffic), and the uci-defaults script, run exactly as the boot and install.sh run it, re-points `main.endpoint` at the remaining server, which brings the tunnel back through it |

### Knobs

| Variable | Default | Meaning |
| --- | --- | --- |
| `TT_PM` | `apk` | `apk` (OpenWrt 25.12) or `opkg` (22.03) |
| `TT_REPO_DIR` | — | flat dir of prebuilt packages (CI artifact layout) |
| `TT_RELEASE_TAG` | `latest` | release tag to download packages from |
| `TT_SERVER_VERSION` | `v1.1.0` | the endpoint release (tarball is hash-checked) |
| `TT_LAB_SUBNET` | `44.55.66.0/24` | the lab network (must be a /24, globally-shaped range) |
| `TT_FILTER` | — | space-separated list of stage names to run. A partial run must include the stages it depends on, for example `TT_FILTER="serve router targets"` |
| `TT_LOGS_DIR` | — | fixed directory for the failure logs (the CI artifact upload). Defaults to `$SCRATCH/logs` |
| `TT_KEEP` | `0` | keep containers/network/scratch for debugging |

On failure the harness collects the router state (logread, trusttunnel
log, routing status, kernel state, configs) and the container logs into
`$TT_LOGS_DIR` (or `$SCRATCH/logs`) before it tears anything down. It
prints the scratch path. `TT_KEEP=1` keeps the containers too.

## CI

`.github/workflows/integration.yml` runs the suite on pull requests, main
pushes and manual dispatch. The suite is verified green end to end
(PR #20). A matrix job builds this tree's packages with the OpenWrt SDK
(apk on 25.12, ipk on 22.03). One job per package manager then runs the
harness against the built repositories and uploads the failure logs as an
artifact. The `/dev/net/tun` preflight (with a mknod/modprobe fallback)
fails loudly instead of letting the harness confuse everyone.

The release pipeline additionally runs the harness against the release's
own x86-64 packages (`verify-integration` in `release.yml`). Publishing
waits for it. There is no SDK rebuild there. The pipeline consumes the
release artifacts directly.

## Why the stages look the way they do

- **The lab subnet must look public.** The marking rules of the router
  (and the endpoint) refuse private and documentation ranges. The lab
  network therefore uses a globally-shaped range that docker can host as
  a private bridge (44.55.66.0/24 by default). The endpoint runs with
  `allow_private_network_connections = true`, a test-only relaxation
  that the vpn.toml fixture documents.
- **The router boots with `/sbin/init`** so procd, netifd, fw4 and
  logread behave like on a device. Otherwise netifd would enslave eth0
  into the default `br-lan` bridge and break docker networking. The
  harness reconfigures `network.lan` to use eth0 directly with the
  router's own tools.
- **The whoami targets are the traffic oracle.** Through-tunnel requests
  arrive with the endpoint's IP as source. Direct requests arrive with
  the caller's own IP. The direct target lives on a dedicated private
  docker network, a range that the router never marks. A custom network
  adds only the connected route. Joining the docker DEFAULT bridge would
  inject a second default route, and the client binds its endpoint
  sockets to the interface of the default route.
- **The lab default route is enforced.** The direct-net connect can race
  the asynchronous installation of the static default by netifd. If the
  connected gateway of docker wins (metric 0), the client dials the
  endpoint through the wrong gateway, and the tunnel never comes up. The
  harness replaces the default with the lab gateway after the connect and
  again before the service starts. It also asserts the route by counting
  `^default` lines. busybox `ip` ignores the `default` filter before
  install.sh replaces it.
- **The pinned certificate is exercised for real.** The client connects
  with `skip_verification = false`. The self-signed certificate carries
  the SAN for the SNI hostname (`tt.test`). A working tunnel therefore
  proves that the pin from `client.toml` authenticated the endpoint. This
  is the Phase 0 fix, end to end.
- **Startup races are waited out deterministically.** The python servers
  (repo + targets) take a moment to bind their sockets. The firewall
  loads the lan-zone rule asynchronously after the network restart. The
  tunnel needs up to a minute to establish. The harness polls for all
  three instead of sleeping.
- **The arch derivation is pinned against the pipeline.** release.yml
  derives the per-arch opkg feed directories (and the version key that
  its pin verification installs) from the client ipk file names
  (`trusttunnel-client_<ver>-<rel>_<arch>.ipk`). The derivation lives in
  `ipk-arch.sh`, which both the workflow and the harness source. The
  `archparse` regression stage therefore tests the exact code that the
  pipeline runs. A first implementation split at the last underscore and
  clipped arch names that contain underscores (`mipsel_24kc` → `24kc`,
  `x86_64` → `64`). It then produced feed directories that no device
  would fetch, and the release-time verification caught it. The opkg
  assembly of the harness also derives the feed directory from the real
  artifact of the run, so a regression fails the install assertions too.
- **The hermetic repository mirrors the official layout.** The release
  pipeline serves the repositories as
  `releases/<version>/packages/<arch>/trusttunnel/`, the official OpenWrt
  pattern (`releases/25.12.5/` for apk, `releases/22.03.7/` for opkg).
  The harness assembles the same shape
  (`repo/releases/25.12.5/packages/x86_64/trusttunnel/` or the 22.03.7
  equivalent with the signed index next to the packages). The derived
  URLs of `install.sh` and the router-side repository configuration are
  therefore exercised against the exact paths that a router will fetch
  from the Pages site.
- **apk fetches packages by their metadata-derived names.** The release
  assets carry a `-x86_64` suffix (per-arch uploads). That name would
  return 404 for the metadata-derived name. The harness therefore renames
  every package file to `name-version.apk` (read with `apk adbdump`)
  before it creates the index.
- **The install retries once on a package-manager mirror flake.** The
  update step hits the public OpenWrt mirrors, and busybox wget does not
  retry. install.sh is safe to rerun (the lifecycle stage asserts that
  its repository setup is idempotent). One retry therefore absorbs the
  transient download failures.
- **Every other network request is retried too.** The lab net is
  hermetic but not lossless. An fw4 reload can drop a single inbound
  reply. busybox wget reports that as "Operation not permitted", and
  curl as an empty body. The `retry`/`retry_out` helpers wrap the
  lifecycle reinstall, the traffic probes and the external downloads
  (GitHub release assets, the endpoint binary, ipkg-make-index.sh). The
  response body of a traffic probe IS the assertion value. `retry_out`
  prints the body of the last attempt when all attempts fail, so the
  assert still reports what was actually seen. The sibling harnesses
  share the same shape. `build-sdk.sh` retries the SDK image pull, the
  feed clones and the client source download. `restricted-feeds.sh`
  retries the verify image pull. `gui/run.sh` retries the Playwright
  image pull, the luci-base fetch and `npm ci`. The backend contract
  test retries its healthy-phase `apt-get install`.
- **On the apk path the package manager consumes the uci-defaults
  script.** apk runs `/etc/uci-defaults/*` right after it places them
  and removes them. The immediate run of install.sh is the fallback, and
  it only fires on opkg. The lifecycle stage runs the idempotence rerun
  only when the file still exists. It asserts the no-duplicate state on
  both paths.
- **The killswitch is asserted at the kernel level.** `ip route get
  <target> mark 0x9527` resolves via tun0 while the tunnel is up. With
  the device down the kernel drops the attached route, and the table
  holds only the blackhole. The same lookup then fails (`ip route get`
  answers EINVAL for a blackhole match). No client process is involved,
  so the check is deterministic.

## Possible extensions

Cheap, incremental additions that the design allows but that are not
implemented:

- an `upstream_protocol = http3` scenario (the endpoint already listens
  on UDP 8443)
- the opkg variant on `openwrt/rootfs:x86-64-23.05.6` and
  `x86-64-24.10.8` (same opkg branch, extra images)
- routing-profile scenarios: a Bypass profile whose `vpn_rules` contain
  the lab target (assert `vpn_mode = "selective"` and the generated
  `exclusions`) and a VPN profile with `bypass_rules` (assert
  `vpn_mode = "general"`)
- the uninstaller round trip (`uninstall.sh -y`): packages gone,
  feed/keys gone, kernel leftovers reported
- a snapshot test of the endpoint-down behavior with the client alive.
  The generated config sets `killswitch_enabled = false`, and the
  recovery behavior of the client was observed to vary, so the intended
  semantics should be decided first (possibly with an upstream issue)
