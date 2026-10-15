---
layout: default
title: "releases — TrustTunnelOpenWrt"
---

# releases — TrustTunnelOpenWrt

Signed package repositories in the official OpenWrt layout
(`releases/<version>/packages/<arch>/<feed>/`). Each package-manager era
has one release tree, named after the OpenWrt release that the packages
were built against:

- `25.12.5` — the apk repositories for OpenWrt 25.12+ (apk)
- `22.03.7` — the opkg repositories for OpenWrt 22.03–24.10 (opkg)

Each tree holds per-architecture `trusttunnel` feed directories with the
signed index, the public signing key and every released version of the
packages. This project ships no target-specific packages and no kernel
modules, so the official layout's `targets/<target>/<subtarget>/` trees
do not exist here.

Release trees:

__RELEASE_LIST__
