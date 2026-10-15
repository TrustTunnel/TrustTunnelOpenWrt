# TrustTunnel OpenWrt package repositories

This site hosts the package repositories that
[install.sh](https://raw.githubusercontent.com/TrustTunnel/TrustTunnelOpenWrt/master/install.sh)
configures on the router:

- [releases/](releases/) — the signed package feeds in the official
  OpenWrt layout (`releases/<version>/packages/<arch>/<feed>/`). Each
  package-manager era has one release tree, named after the OpenWrt
  release that the packages were built against. The `25.12.5` tree holds
  the apk feeds for OpenWrt 25.12+, and the `22.03.7` tree holds the
  opkg feeds for 22.03–24.10. Each tree holds per-architecture
  `trusttunnel` feed directories with the signed index, the public
  signing key and every released version of the packages. Repository
  URLs for the router (the arch is the package architecture of the
  device):
  `https://trusttunnel.github.io/TrustTunnelOpenWrt/releases/25.12.5/packages/<arch>/trusttunnel/packages.adb`
  and
  `https://trusttunnel.github.io/TrustTunnelOpenWrt/releases/22.03.7/packages/<arch>/trusttunnel`

The feeds carry the four packages of the project: the LuCI app, the
runtime, the client binaries and the optional diagnostics add-on. The app
depends on the runtime, and the runtime depends on the client package.

The repositories are cumulative: they serve every released version of
the LuCI app, with the latest release (`__TAG__`) on top of all earlier
ones. You can pin or downgrade to an older version at any time. The same
holds for the client: every released `trusttunnel-client` build stays in
the feeds. The package managers install the highest version unless a
router pins an older one. A client update can arrive on its own as a
`client-v*` release. The repositories are then re-published with the new
client, while the LuCI app stays at its current version.

The GitHub
[releases](https://github.com/TrustTunnel/TrustTunnelOpenWrt/releases)
carry the same package files for manual download.

## Installing

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/TrustTunnel/TrustTunnelOpenWrt/master/install.sh)"
```

## Updating

Package updates use the standard package-manager commands:

```sh
# apk (25.12+):
apk update && apk upgrade
# opkg (22.03–24.10):
opkg update && opkg upgrade
```

Re-running the installer refreshes the signing keys. The package-manager
commands above update the packages: the LuCI app and the client binary
(the `trusttunnel-client` dependency). A client-only release updates the
binary while the app stays at its installed version.

## Pinning the client

Every released client build stays installable, so a router can hold a
specific `trusttunnel-client` version:

```sh
# apk (25.12+), version as listed in the feed's index:
apk add trusttunnel-client=1.1.7-r1
# opkg (22.03–24.10) has no pkg=version syntax: download the versioned
# ipk from the feed, install it (--force-downgrade is needed only when
# a newer build is already installed) and hold it across upgrades:
wget -O /tmp/tt-client.ipk https://trusttunnel.github.io/TrustTunnelOpenWrt/releases/22.03.7/packages/<arch>/trusttunnel/trusttunnel-client_1.1.7-1_<arch>.ipk
opkg install --force-downgrade /tmp/tt-client.ipk
opkg flag hold trusttunnel-client
```

Replace `<arch>` with the package architecture of the device (`x86_64`,
`aarch64_cortex-a53`, `mipsel_24kc`, ...). Replace the version with any
version that the feed lists.
