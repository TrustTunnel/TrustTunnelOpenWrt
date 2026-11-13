#!/bin/sh
# Bump the trusttunnel-client pin to a vendor release.
#
#   update-client.sh --root DIR --version VERSION --assets FILE \
#                    [--tarball-dir DIR] [--dry-run]
#
# The scheduled update-client workflow calls this script. It rewrites
# exactly two files:
#
#   packages/trusttunnel-client/Makefile   PKG_VERSION and the five
#                                          per-family PKG_HASH values
#   tests/fixtures/client-hashes.txt       the same five hashes
#
# Everything else in both files is preserved byte-for-byte. The script
# never trusts the release API alone: it downloads every family tarball,
# compares its SHA-256 with the digest the API publishes, and checks the
# archive layout the packager needs (the top-level directory and the five
# installed files). A release that fails any check changes nothing.
#
# The script reads the current hashes through the same packager parser
# the release pipeline uses (tests/release/package-client.sh), so the two
# cannot drift. A stale hash fixture is repaired together with the pin.
#
# `--assets` is a TSV of `name<TAB>url<TAB>sha256`. The workflow writes it
# with `gh api --jq`, so this script needs no JSON parser. `--tarball-dir`
# replaces the download with local files and exists for the unit test.
# `--dry-run` prints the diff and writes nothing.
#
# Usage:
#   update-client.sh --root . --version 1.1.12 --assets assets.tsv
#   update-client.sh --root . --version 1.1.12 --assets assets.tsv --dry-run
set -eu

die() {
	printf 'update-client: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
usage: update-client.sh --root DIR --version VERSION --assets FILE
                        [--tarball-dir DIR] [--dry-run]
EOF
}

# The vendor ships one tarball per CPU family. The order is the Makefile's.
families="x86_64 aarch64 armv7 mips mipsel"

root=.
version=
assets=
tarball_dir=
dry_run=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--root)
			[ "$#" -ge 2 ] || die "--root needs a value"
			root=$2
			shift 2
			;;
		--version)
			[ "$#" -ge 2 ] || die "--version needs a value"
			version=$2
			shift 2
			;;
		--assets)
			[ "$#" -ge 2 ] || die "--assets needs a value"
			assets=$2
			shift 2
			;;
		--tarball-dir)
			[ "$#" -ge 2 ] || die "--tarball-dir needs a value"
			tarball_dir=$2
			shift 2
			;;
		--dry-run)
			dry_run=1
			shift
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			die "unknown argument: $1"
			;;
	esac
done

[ -n "$version" ] || die "--version is required"
[ -n "$assets" ] || die "--assets is required"

# The package version reaches apk/opkg and the tag name, so it must be the
# plain X.Y.Z shape the vendor's stable tags use. A prerelease tag is not a
# supported package version.
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
	|| die "unsupported vendor version '$version' (expected X.Y.Z)"

[ -f "$assets" ] || die "cannot read the assets file: $assets"
makefile="$root/packages/trusttunnel-client/Makefile"
fixture="$root/tests/fixtures/client-hashes.txt"
[ -f "$makefile" ] || die "cannot read $makefile"
[ -f "$fixture" ] || die "cannot read $fixture"

work=$(mktemp -d) || die "cannot create a work directory"
trap 'rm -rf "$work"' EXIT INT TERM

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{ print $1 }'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{ print $1 }'
	else
		die "sha256sum or shasum is required"
	fi
}

retry() {
	_tries=$1
	_wait=$2
	shift 2
	_i=0
	while [ "$_i" -lt "$_tries" ]; do
		_i=$((_i + 1))
		if "$@"; then
			return 0
		fi
		if [ "$_i" -lt "$_tries" ]; then
			sleep "$_wait"
		fi
	done
	return 1
}

# asset_field <name> <column> — one field of one asset line.
asset_field() {
	awk -F '\t' -v name="$1" -v column="$2" \
		'$1 == name { print $column; exit }' "$assets"
}

# hash_in_makefile <file> <family> — the family's PKG_HASH value.
#
# The packager owns the Makefile parsing. Reading through it keeps the
# updater and the release pipeline on one parser, so a change to the hash
# block cannot update one and miss the other.
hash_in_makefile() {
	TT_REPO_DIR="$root" TT_CLIENT_MAKEFILE="$1" \
		sh "$(dirname "$0")/../../tests/release/package-client.sh" hash "$2"
}

# Validate the release metadata before any download: every family must be
# present, and every digest must be a full lowercase sha256.
for family in $families; do
	name="trusttunnel_client-v${version}-linux-${family}.tar.gz"
	url=$(asset_field "$name" 2)
	digest=$(asset_field "$name" 3)
	[ -n "$url" ] || die "the release has no $name"
	digest=${digest#sha256:}
	[ ${#digest} -eq 64 ] || die "no valid sha256 digest for $name"
	case "$digest" in
		*[!0-9a-f]*)
			die "no valid sha256 digest for $name"
			;;
	esac
done

pinned=$(sed -n 's/^PKG_VERSION:=//p' "$makefile" | head -n 1)
[ -n "$pinned" ] || die "cannot read PKG_VERSION from $makefile"

# When the pin already names this version and both the Makefile and the
# fixture carry the release hashes, there is nothing to verify or write.
# This is the common scheduled-run path, so it avoids downloading five
# tarballs every day. The fixture is part of the check: a stale fixture
# must be repaired, not reported as current.
current=1
[ "$pinned" = "$version" ] || current=0
for family in $families; do
	name="trusttunnel_client-v${version}-linux-${family}.tar.gz"
	digest=$(asset_field "$name" 3)
	digest=${digest#sha256:}
	if ! actual=$(hash_in_makefile "$makefile" "$family"); then
		die "cannot read the $family hash from $makefile"
	fi
	[ "$actual" = "$digest" ] || current=0
	fixture_hash=$(awk -v family="$family" '$1 == family { print $2; exit }' "$fixture")
	[ "$fixture_hash" = "$digest" ] || current=0
done

if [ "$current" -eq 1 ]; then
	printf 'update-client: already at %s\n' "$version"
	exit 0
fi

# Download and verify every tarball. A digest mismatch or a missing member
# fails before either file is touched.
for family in $families; do
	name="trusttunnel_client-v${version}-linux-${family}.tar.gz"
	url=$(asset_field "$name" 2)
	digest=$(asset_field "$name" 3)
	digest=${digest#sha256:}
	tarball="$work/$name"
	if [ -n "$tarball_dir" ]; then
		[ -f "$tarball_dir/$name" ] || die "missing vendor tarball $tarball_dir/$name"
		cp "$tarball_dir/$name" "$tarball"
	else
		retry 3 5 curl -fsSL -o "$tarball" "$url" \
			|| die "cannot download $url"
	fi
	actual=$(sha256_of "$tarball")
	[ "$actual" = "$digest" ] \
		|| die "hash mismatch for $name (expected $digest, got $actual)"
	top="trusttunnel_client-v${version}-linux-${family}"
	tar -tzf "$tarball" > "$work/list-$family" 2>/dev/null \
		|| die "cannot read $name"
	for member in trusttunnel_client setup_wizard trusttunnel_client.sig setup_wizard.sig LICENSE; do
		grep -qx "$top/$member" "$work/list-$family" \
			|| die "$name has no $top/$member"
	done
done

# Build the family=hash list once for the two rewrites.
hash_pairs=
for family in $families; do
	name="trusttunnel_client-v${version}-linux-${family}.tar.gz"
	digest=$(asset_field "$name" 3)
	digest=${digest#sha256:}
	if [ -n "$hash_pairs" ]; then
		hash_pairs="$hash_pairs,$family=$digest"
	else
		hash_pairs="$family=$digest"
	fi
done

# PKG_VERSION is a single line; replace it without touching anything else.
sed "s/^PKG_VERSION:=.*/PKG_VERSION:=$version/" "$makefile" > "$work/Makefile.versioned"

# Every PKG_HASH branch carries the family in a `$(filter ...)` marker. The
# 64 hex characters after the marker are the hash. The marker locates the
# hash, and the 64-character check keeps a different expression from
# matching.
awk -v pairs="$hash_pairs" '
	BEGIN {
		n = split(pairs, items, ",")
		for (i = 1; i <= n; i++) {
			split(items[i], pair, "=")
			hashes[pair[1]] = pair[2]
		}
	}
	{
		for (family in hashes) {
			marker = "$(filter " family ",$(VENDOR_ARCH)),"
			pos = index($0, marker)
			if (pos == 0) {
				continue
			}
			start = pos + length(marker)
			rest = substr($0, start)
			if (match(rest, /^[0-9a-f]+/) && RLENGTH == 64) {
				$0 = substr($0, 1, start - 1) hashes[family] substr(rest, RLENGTH + 1)
			}
		}
		print
	}
' "$work/Makefile.versioned" > "$work/Makefile.new"

awk -v pairs="$hash_pairs" '
	BEGIN {
		n = split(pairs, items, ",")
		for (i = 1; i <= n; i++) {
			split(items[i], pair, "=")
			hashes[pair[1]] = pair[2]
		}
	}
	($1 in hashes) { $2 = hashes[$1] }
	{ print }
' "$fixture" > "$work/client-hashes.new"

# The rewrites must have landed. A silent no-op here would publish the old
# hashes under the new version.
got_version=$(sed -n 's/^PKG_VERSION:=//p' "$work/Makefile.new" | head -n 1)
[ "$got_version" = "$version" ] \
	|| die "failed to rewrite PKG_VERSION in $makefile"
for family in $families; do
	name="trusttunnel_client-v${version}-linux-${family}.tar.gz"
	expected=$(asset_field "$name" 3)
	expected=${expected#sha256:}
	if ! actual=$(hash_in_makefile "$work/Makefile.new" "$family"); then
		die "failed to read the $family hash from $work/Makefile.new"
	fi
	[ "$actual" = "$expected" ] \
		|| die "failed to rewrite the $family hash in $makefile"
	fixture_hash=$(awk -v family="$family" '$1 == family { print $2; exit }' \
		"$work/client-hashes.new")
	[ "$fixture_hash" = "$expected" ] \
		|| die "failed to rewrite the $family hash in $fixture"
done

if [ "$dry_run" -eq 1 ]; then
	diff -u "$makefile" "$work/Makefile.new" || true
	diff -u "$fixture" "$work/client-hashes.new" || true
	printf 'update-client: %s -> %s (dry run, nothing written)\n' "$pinned" "$version"
	exit 0
fi

cp "$work/Makefile.new" "$makefile"
cp "$work/client-hashes.new" "$fixture"
printf 'update-client: %s -> %s\n' "$pinned" "$version"
for family in $families; do
	name="trusttunnel_client-v${version}-linux-${family}.tar.gz"
	digest=$(asset_field "$name" 3)
	printf '  %-8s %s\n' "$family" "${digest#sha256:}"
done
