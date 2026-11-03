#!/bin/sh
# Build one trusttunnel-client package from the vendor tarball.
#
# The vendor client is prebuilt, so the release matrix must not run the
# OpenWrt SDK: the SDK resolves the package's runtime dependencies and
# builds the kernel and toolchain for every architecture. This script
# replaces that work with a small packager image. The release workflow
# calls it once per architecture, inside tests/release/packager.Dockerfile.
#
# The script reads the package fields and the install file list from
# packages/trusttunnel-client/Makefile. The generated package therefore
# follows the Makefile instead of repeating its metadata. The vendor
# tarball is the only download, and its SHA-256 must match PKG_HASH.
#
# Usage:
#   package-client build <apk|ipk> <arch>
#   package-client family <arch>
#   package-client hash <family>
#
# Environment:
#   TT_REPO_DIR           repo root (default /work)
#   TT_CLIENT_MAKEFILE    client Makefile (default
#                         $TT_REPO_DIR/packages/trusttunnel-client/Makefile)
#   TT_CLIENT_OUT_DIR     output directory (default $TT_REPO_DIR/dist)
#   TT_CLIENT_TARBALL_DIR local vendor tarball directory (test override)
#   TT_CLIENT_HASHES      family/hash file (test override)
set -eu

repo_dir=${TT_REPO_DIR:-/work}
makefile=${TT_CLIENT_MAKEFILE:-$repo_dir/packages/trusttunnel-client/Makefile}
out_dir=${TT_CLIENT_OUT_DIR:-$repo_dir/dist}

die() {
	printf 'package-client: %s\n' "$*" >&2
	exit 1
}

retry() {
	_retry_tries=$1
	_retry_wait=$2
	shift 2
	_retry_i=0
	while [ "$_retry_i" -lt "$_retry_tries" ]; do
		_retry_i=$((_retry_i + 1))
		if "$@"; then
			return 0
		fi
		if [ "$_retry_i" -lt "$_retry_tries" ]; then
			sleep "$_retry_wait"
		fi
	done
	return 1
}

makefile_field() {
	sed -n "s/^$1[[:space:]]*:[[:space:]]*=*[[:space:]]*//p" "$makefile" | head -n 1
}

makefile_block_field() {
	awk -v key="$1" '
		/^define Package\/trusttunnel-client$/ { inblock = 1; next }
		inblock && /^endef$/ { exit }
		inblock && $0 ~ "^[[:space:]]*" key ":=" {
			sub("^[[:space:]]*" key ":=", "")
			print
			exit
		}
	' "$makefile"
}

load_metadata() {
	PKG_NAME=$(makefile_field PKG_NAME)
	PKG_VERSION=$(makefile_field PKG_VERSION)
	PKG_RELEASE=$(makefile_field PKG_RELEASE)
	PKG_LICENSE=$(makefile_field PKG_LICENSE)
	PKG_MAINTAINER=$(makefile_field PKG_MAINTAINER)
	PKG_SOURCE_URL=$(makefile_field PKG_SOURCE_URL | sed "s/\$(PKG_VERSION)/$PKG_VERSION/g")
	TITLE=$(makefile_block_field TITLE)
	URL=$(makefile_block_field URL)
	SECTION=$(makefile_block_field SECTION)
	DEPENDS_RAW=$(makefile_block_field DEPENDS)

	[ -n "$PKG_NAME" ] || die "PKG_NAME is missing from $makefile"
	[ -n "$PKG_VERSION" ] || die "PKG_VERSION is missing from $makefile"
	[ -n "$PKG_RELEASE" ] || die "PKG_RELEASE is missing from $makefile"
	[ -n "$PKG_LICENSE" ] || die "PKG_LICENSE is missing from $makefile"
	[ -n "$PKG_MAINTAINER" ] || die "PKG_MAINTAINER is missing from $makefile"
	[ -n "$PKG_SOURCE_URL" ] || die "PKG_SOURCE_URL is missing from $makefile"
	[ -n "$TITLE" ] || die "TITLE is missing from $makefile"
	[ -n "$URL" ] || die "URL is missing from $makefile"
	[ -n "$SECTION" ] || die "SECTION is missing from $makefile"
	[ -n "$DEPENDS_RAW" ] || die "DEPENDS is missing from $makefile"

	VERSION_APK="${PKG_VERSION}-r${PKG_RELEASE}"
	VERSION_IPK="${PKG_VERSION}-${PKG_RELEASE}"
	DEPENDS_APK=$(printf '%s\n' "$DEPENDS_RAW" | tr ' ' '\n' | sed 's/^+//' | sed '/^$/d' | tr '\n' ' ' | sed 's/ $//')
	DEPENDS_IPK=$(printf '%s\n' "$DEPENDS_RAW" | tr ' ' '\n' | sed 's/^+//' | sed '/^$/d' | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')
	ORIGIN="feeds/ttowrt/packages/${PKG_NAME}"
}

family_for_arch() {
	case "$1" in
		x86_64) echo x86_64 ;;
		aarch64*) echo aarch64 ;;
		arm_cortex-*) echo armv7 ;;
		mips_*) echo mips ;;
		mipsel_*) echo mipsel ;;
		*) die "no vendor build for arch '$1'" ;;
	esac
}

hash_for_family() {
	if [ -n "${TT_CLIENT_HASHES:-}" ]; then
		awk -v family="$1" '$1 == family { print $2; found = 1 } END { exit(found ? 0 : 1) }' "$TT_CLIENT_HASHES" \
			|| die "no hash for family '$1' in $TT_CLIENT_HASHES"
		return 0
	fi

	_hash_block=$(sed -n '/^PKG_HASH[[:space:]]*:=/,/)))))/p' "$makefile" | tr -d '\\\n')
	[ -n "$_hash_block" ] || die "cannot read PKG_HASH from $makefile"
	_hash=$(printf '%s\n' "$_hash_block" | sed -n "s/.*\$(filter $1,\$(VENDOR_ARCH)),\([0-9a-f][0-9a-f]*\).*/\1/p")
	[ -n "$_hash" ] || die "no PKG_HASH for family '$1'"
	printf '%s\n' "$_hash"
}

download_tarball() {
	_family=$1
	_dest=$2
	_name="trusttunnel_client-v${PKG_VERSION}-linux-${_family}.tar.gz"
	if [ -n "${TT_CLIENT_TARBALL_DIR:-}" ]; then
		_src="$TT_CLIENT_TARBALL_DIR/$_name"
		[ -f "$_src" ] || die "missing vendor tarball $_src"
		cp "$_src" "$_dest"
	else
		retry 3 5 curl -fsSL -o "$_dest" "${PKG_SOURCE_URL}/$_name" \
			|| die "cannot download $_name"
	fi
}

verify_tarball() {
	_family=$1
	_tarball=$2
	_expected=$(hash_for_family "$_family")
	_actual=$(sha256sum "$_tarball" | awk '{ print $1 }')
	[ -n "$_actual" ] || die "cannot hash $_tarball"
	[ "$_actual" = "$_expected" ] || die "hash mismatch for $_tarball"
}

build_tree() {
	_top=$1
	_tree=$2
	_install_file=$3

	awk '
		/^define Package\/trusttunnel-client\/install$/ { inblock = 1; next }
		inblock && /^endef$/ { exit }
		inblock { print }
	' "$makefile" > "$_install_file"

	while IFS= read -r _line; do
		case "$_line" in
			*'$(INSTALL_DIR)'*)
				_dir=${_line##*'$(1)'}
				mkdir -p "$_tree$_dir"
				;;
			*'$(INSTALL_BIN)'*|*'$(INSTALL_DATA)'*)
				_src=$(printf '%s\n' "$_line" | sed -n 's/.*\$(PKG_BUILD_DIR)\/\([^ ]*\) .*/\1/p')
				_dest=$(printf '%s\n' "$_line" | sed -n 's/.*\$(1)\([^ ]*\)$/\1/p')
				[ -n "$_src" ] || die "cannot parse install source: $_line"
				[ -n "$_dest" ] || die "cannot parse install destination: $_line"
				case "$_dest" in
					*/) _dest="$_dest$_src" ;;
				esac
				case "$_line" in
					*'$(INSTALL_BIN)'*) _mode=0755 ;;
					*) _mode=0644 ;;
				esac
				mkdir -p "$(dirname "$_tree$_dest")"
				cp "$_top/$_src" "$_tree$_dest"
				chmod "$_mode" "$_tree$_dest"
				;;
			*)
				_trimmed=$(printf '%s\n' "$_line" | sed 's/^[[:space:]]*//')
				case "$_trimmed" in
					''|'#'*) ;;
					*) die "unsupported install line: $_line" ;;
				esac
				;;
		esac
	done < "$_install_file"

	chown -R 0:0 "$_tree"
}

build_apk() {
	_arch=$1
	_tree=$2
	_list_tmp=$3

	mkdir -p "$_tree/lib/apk/packages"
	(
		cd "$_tree" || exit 1
		find . \( -type f -o -type l \) -print | sed 's|^\./|/|' | sort > "$_list_tmp"
	)
	mv "$_list_tmp" "$_tree/lib/apk/packages/${PKG_NAME}.list"

	mkdir -p "$out_dir"
	_out="$out_dir/${PKG_NAME}-${VERSION_APK}-${_arch}.apk"
	apk mkpkg \
		--info "name:${PKG_NAME}" \
		--info "version:${VERSION_APK}" \
		--info "arch:${_arch}" \
		--info "license:${PKG_LICENSE}" \
		--info "origin:${ORIGIN}" \
		--info "url:${URL}" \
		--info "maintainer:${PKG_MAINTAINER}" \
		--info "description:${TITLE}" \
		--info "depends:${DEPENDS_APK}" \
		--files "$_tree" \
		--output "$_out"
	printf '%s\n' "$_arch" > "$out_dir/ARCH-${_arch}"
	printf '%s\n' "$_out"
}

build_ipk() {
	_arch=$1
	_tree=$2
	_work=$3

	mkdir -p "$out_dir"
	_data="$_work/data.tar.gz"
	(
		cd "$_tree" || exit 1
		tar --format=gnu --numeric-owner --sort=name --mtime=@0 -cpf - . | gzip -n > "$_data"
	)
	_installed_size=$(gzip -dc "$_data" | wc -c | tr -d ' ')

	_control_dir="$_work/CONTROL"
	mkdir -p "$_control_dir"
	{
		printf 'Package: %s\n' "$PKG_NAME"
		printf 'Version: %s\n' "$VERSION_IPK"
		printf 'Depends: %s\n' "$DEPENDS_IPK"
		printf 'Source: %s\n' "$ORIGIN"
		printf 'SourceName: %s\n' "$PKG_NAME"
		printf 'License: %s\n' "$PKG_LICENSE"
		printf 'Section: %s\n' "$SECTION"
		printf 'URL: %s\n' "$URL"
		printf 'Maintainer: %s\n' "$PKG_MAINTAINER"
		printf 'Architecture: %s\n' "$_arch"
		printf 'Installed-Size: %s\n' "$_installed_size"
		printf 'Description: %s\n' "$TITLE"
	} > "$_control_dir/control"
	chmod 0644 "$_control_dir/control"

	(
		cd "$_control_dir" || exit 1
		tar --format=gnu --numeric-owner --sort=name --mtime=@0 -cf - . | gzip -n > "$_work/control.tar.gz"
	)
	printf '2.0\n' > "$_work/debian-binary"

	_out="$out_dir/${PKG_NAME}_${VERSION_IPK}_${_arch}.ipk"
	(
		cd "$_work" || exit 1
		tar --format=gnu --numeric-owner --sort=name --mtime=@0 -cf - ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -n > "$_out"
	)
	printf '%s\n' "$_out"
}

build_package() {
	_pm=$1
	_arch=$2
	case "$_pm" in
		apk|ipk) ;;
		*) die "unsupported package manager '$_pm'" ;;
	esac

	load_metadata
	_family=$(family_for_arch "$_arch")
	_work=$(mktemp -d)
	trap 'rm -rf "$_work"' EXIT INT TERM

	_tarball="$_work/trusttunnel_client-v${PKG_VERSION}-linux-${_family}.tar.gz"
	download_tarball "$_family" "$_tarball"
	verify_tarball "$_family" "$_tarball"

	mkdir -p "$_work/src"
	tar -xzf "$_tarball" -C "$_work/src"
	_top="$_work/src/trusttunnel_client-v${PKG_VERSION}-linux-${_family}"
	[ -d "$_top" ] || die "unexpected vendor tarball layout: $_top is missing"

	_tree="$_work/tree"
	mkdir -p "$_tree"
	build_tree "$_top" "$_tree" "$_work/install.txt"

	case "$_pm" in
		apk) build_apk "$_arch" "$_tree" "$_work/list.txt" ;;
		ipk) build_ipk "$_arch" "$_tree" "$_work" ;;
	esac
}

case "${1:-}" in
	build)
		[ "$#" -eq 3 ] || die "usage: package-client build <apk|ipk> <arch>"
		build_package "$2" "$3"
		;;
	family)
		[ "$#" -eq 2 ] || die "usage: package-client family <arch>"
		family_for_arch "$2"
		;;
	hash)
		[ "$#" -eq 2 ] || die "usage: package-client hash <family>"
		load_metadata
		hash_for_family "$2"
		;;
	*)
		die "usage: package-client build <apk|ipk> <arch> | family <arch> | hash <family>"
		;;
esac
