# Updating

The setup script installs the repository entry, and the entry stays in
place. To keep the package current, run a package-manager command:

```sh
apk update && apk upgrade   # OpenWrt 25.12+
opkg update && opkg upgrade # OpenWrt 22.03–24.10
```

`trusttunnel-client` is a hard dependency of the LuCI app, so the binary
updates together with the package. A client-only release of the
repositories can also update the binary on its own.
`/etc/config/trusttunnel` survives untouched.

Every released client version stays in the repositories. You can pin a
specific build instead of taking the newest one:

```sh
# OpenWrt 25.12+ — the constraint is kept across upgrades:
apk add trusttunnel-client=1.0.49-r1
# OpenWrt 22.03–24.10 — opkg has no pkg=version syntax: install the
# versioned ipk from the feed and hold it:
wget -O /tmp/tt-client.ipk <feed-url>/trusttunnel-client_1.0.49-1_<arch>.ipk
opkg install --force-downgrade /tmp/tt-client.ipk
opkg flag hold trusttunnel-client
```

`<arch>` is the package architecture of the device (`x86_64`,
`aarch64_cortex-a53`, `mipsel_24kc`, ...). The version can be any one
that the feed lists.
