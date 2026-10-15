# Uninstalling

Run the uninstaller:

```sh
sh -c "$(wget -O - https://raw.githubusercontent.com/TrustTunnel/TrustTunnelOpenWrt/master/uninstall.sh)"
```

It halts and disables the service, removes the packages (the app, the
runtime and the client, plus the optional diagnostics package when it is
installed), tears down the repository configuration and the signing keys
the installer put in place, deletes the client binaries and caches (plus the
leftovers of earlier package versions), restarts `rpcd` and checks the
kernel for leftover routing state. It asks whether to remove the firewall
zone (default: yes) and the settings file (default: no — a reinstall
keeps it).

Flags: `-y` answers every question with yes; `-c` keeps
`/etc/config/trusttunnel` without asking. Shared dependencies (`kmod-tun`,
`ip-full`, `nftables`, `curl`, `ca-bundle`) stay installed on purpose.

Removing by hand works as well:

```sh
/etc/init.d/trusttunnel stop
/etc/init.d/trusttunnel disable
apk del luci-app-trusttunnel
# on 22.03–24.10: opkg remove luci-app-trusttunnel
rm -rf /opt/trusttunnel_client
uci show firewall | grep trusttunnel
uci delete firewall.@zone[1]   # the section numbers from the listing
uci delete firewall.@forwarding[1]
uci commit firewall
/etc/init.d/firewall restart
# also remove the repository entry and the signing keys:
#   apk:  /etc/apk/repositories.d/trusttunnel.list, /etc/apk/keys/trusttunnel.pub
#   opkg: the "src/gz trusttunnel" line in /etc/opkg/customfeeds.conf,
#         plus the key files under /etc/opkg/keys/
```
