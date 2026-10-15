# Updating

The repository entry installed by the setup script remains, so keeping the
package current is a plain package-manager call:

```sh
apk update && apk upgrade   # OpenWrt 25.12+
opkg update && opkg upgrade # OpenWrt 22.03–24.10
```

`trusttunnel-client` is a hard dependency of the LuCI app, so the binary
updates together with the package — and can also arrive on its own, via
a client-only release of the repositories — while `/etc/config/trusttunnel`
survives untouched.

Every released client version stays in the repositories, so a specific
build can be pinned instead of taking the newest one:

```sh
# OpenWrt 25.12+ — the constraint is kept across upgrades:
apk add trusttunnel-client=1.0.49-r1
# OpenWrt 22.03–24.10 — opkg has no pkg=version syntax: install the
# versioned ipk from the feed and hold it:
wget -O /tmp/tt-client.ipk <feed-url>/trusttunnel-client_1.0.49-1_<arch>.ipk
opkg install --force-downgrade /tmp/tt-client.ipk
opkg flag hold trusttunnel-client
```

`<arch>` is the device's package architecture (`x86_64`,
`aarch64_cortex-a53`, `mipsel_24kc`, ...), and the version can be any
one the feed lists.
