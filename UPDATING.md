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

Each feed keeps the newest three releases, because the published site
has a hard 1 GB limit. The newest LuCI app release is always kept. You
can pin a specific client build that the feed still lists:

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
`aarch64_cortex-a53`, `mipsel_24kc`, ...). The version must be one that
the feed lists. An older version outside the retained set is still on
its GitHub release: download the `.apk` or `.ipk` from there and install
it locally.
