---
layout: default
title: "releases — __TREE__ — TrustTunnelOpenWrt"
---

# releases — `__TREE__`

The signed package repositories built against the OpenWrt `__TREE__`
release. Each architecture has a `trusttunnel` feed directory with the
signed index, the public signing key and the retained versions of the
packages. Each feed keeps the newest `__KEEP__` releases, because the
published site has a hard 1 GB limit. Older versions stay on their
GitHub releases.

Repository URLs for the router (the arch is the package architecture of
the device — `DISTRIB_ARCH` in `/etc/openwrt_release`, or
`/etc/apk/arch` on 25.12+):

```text
https://trusttunnel.github.io/TrustTunnelOpenWrt/releases/__TREE__/packages/<arch>/trusttunnel
```

Architectures:

__ARCH_LIST__

[« back to the releases](../)
