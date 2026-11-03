#!/bin/sh
# Pins the client packager contract. The release matrix must not run the
# SDK for the prebuilt client: every generated package must carry the
# fields and files of packages/trusttunnel-client/Makefile, and its
# payload must come from the vendor tarball of the architecture's CPU
# family.
#
# The test builds the real packager image, generates a package for every
# row of the release matrix, and inspects each package. The vendor
# tarballs are fake, so the test does not download the vendor release.
# The expected fields and files are read from the Makefile, not from a
# second hardcoded list.
. "$(dirname "$0")/lib.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WF="$ROOT/.github/workflows/release.yml"
MAKEFILE="$ROOT/packages/trusttunnel-client/Makefile"
IMAGE=trusttunnel-packager-test

# Docker Desktop on macOS shares $HOME, not the mktemp directory under
# /var/folders. Keep the fixtures under $HOME so the containers can see
# them on both the macOS dev host and the Linux CI runner.
WORK=$(mktemp -d "${HOME:-$ROOT}/.tt-package-client.XXXXXX") \
	|| tt_skip "cannot create a Docker-shareable work directory"
trap 'rm -rf "$WORK"' EXIT INT TERM

command -v docker >/dev/null 2>&1 || tt_skip "docker is required"

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
	sed -n "s/^$1[[:space:]]*:[[:space:]]*=*[[:space:]]*//p" "$MAKEFILE" | head -n 1
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
	' "$MAKEFILE"
}

family_for_arch() {
	case "$1" in
		x86_64) echo x86_64 ;;
		aarch64*) echo aarch64 ;;
		arm_cortex-*) echo armv7 ;;
		mips_*) echo mips ;;
		mipsel_*) echo mipsel ;;
		*) echo unknown ;;
	esac
}

require_nonempty() {
	[ -n "$2" ] || _tt_fail "$1 is present in the Makefile"
}

expected_install_files() {
	printf '%s\n' "$install_block" | while IFS= read -r line; do
		case "$line" in
			*'$(INSTALL_DIR)'*) ;;
			*'$(INSTALL_BIN)'*|*'$(INSTALL_DATA)'*)
				src=$(printf '%s\n' "$line" | sed -n 's/.*\$(PKG_BUILD_DIR)\/\([^ ]*\) .*/\1/p')
				dest=$(printf '%s\n' "$line" | sed -n 's/.*\$(1)\([^ ]*\)$/\1/p')
				case "$dest" in
					*/) dest="$dest$src" ;;
				esac
				case "$line" in
					*'$(INSTALL_BIN)'*) mode=755 ;;
					*) mode=644 ;;
				esac
				printf '%s %s\n' "$mode" "$dest"
				;;
			*)
				trimmed=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//')
				case "$trimmed" in
					''|'#'*) ;;
					*) _tt_fail "unsupported install line in the Makefile: $line" ;;
				esac
				;;
		esac
	done | sort
}

# The packager image is the shared artifact the release matrix uses.
if ! retry 3 5 docker build -q -t "$IMAGE" -f "$ROOT/tests/release/packager.Dockerfile" "$ROOT/tests/release" > "$WORK/docker-build.log" 2>&1; then
	_tt_fail "the packager image builds"
	cat "$WORK/docker-build.log"
	tt_test_summary
fi
_tt_pass "the packager image builds"

pkg_name=$(makefile_field PKG_NAME)
pkg_version=$(makefile_field PKG_VERSION)
pkg_release=$(makefile_field PKG_RELEASE)
pkg_license=$(makefile_field PKG_LICENSE)
pkg_maintainer=$(makefile_field PKG_MAINTAINER)
title=$(makefile_block_field TITLE)
url=$(makefile_block_field URL)
section=$(makefile_block_field SECTION)
depends_raw=$(makefile_block_field DEPENDS)

require_nonempty PKG_NAME "$pkg_name"
require_nonempty PKG_VERSION "$pkg_version"
require_nonempty PKG_RELEASE "$pkg_release"
require_nonempty PKG_LICENSE "$pkg_license"
require_nonempty PKG_MAINTAINER "$pkg_maintainer"
require_nonempty TITLE "$title"
require_nonempty URL "$url"
require_nonempty SECTION "$section"
require_nonempty DEPENDS "$depends_raw"

install_block=$(awk '
	/^define Package\/trusttunnel-client\/install$/ { inblock = 1; next }
	inblock && /^endef$/ { exit }
	inblock { print }
' "$MAKEFILE")
install_dir=$(printf '%s\n' "$install_block" | sed -n 's/.*\$(INSTALL_DIR) \$(1)\([^ ]*\)$/\1/p' | head -n 1)
[ -n "$install_dir" ] || _tt_fail "the Makefile declares an install directory"
install_dir_rel=${install_dir#/}

# The release matrix is the list of packages this contract covers.
awk '
	/^  package-client:/ { injob = 1; next }
	injob && /^  [a-z][a-z0-9-]*:/ { exit }
	injob && /ext:/ { ext = $2 }
	injob && /arch:/ { print ext, $2 }
' "$WF" > "$WORK/rows.txt"
if [ -s "$WORK/rows.txt" ]; then
	_tt_pass "the release matrix has rows"
else
	_tt_fail "the release matrix has rows"
fi

# The hash fixture pins the Makefile's PKG_HASH parsing.
grep -v '^#' "$ROOT/tests/fixtures/client-hashes.txt" | awk 'NF { print $1, $2 }' > "$WORK/hashes.txt"
awk '{ print $1 }' "$WORK/hashes.txt" > "$WORK/families.txt"
while read -r family expected; do
	[ -n "$family" ] || continue
	actual=$(TT_REPO_DIR="$ROOT" sh "$ROOT/tests/release/package-client.sh" hash "$family" 2>&1) \
		|| { _tt_fail "hash $family runs"; continue; }
	assert_eq "$expected" "$actual" "hash $family matches the Makefile"
done < "$WORK/hashes.txt"

while read -r pm arch; do
	[ -n "$arch" ] || continue
	expected_family=$(family_for_arch "$arch")
	actual_family=$(sh "$ROOT/tests/release/package-client.sh" family "$arch" 2>&1) \
		|| { _tt_fail "family $arch runs"; continue; }
	assert_eq "$expected_family" "$actual_family" "family for $arch"
done < "$WORK/rows.txt"

# Build every matrix row in one container run. The fake tarballs carry a
# per-family marker, so a wrong family mapping changes the payload.
if ! docker run --rm -v "$WORK:/fixtures" --entrypoint sh "$IMAGE" -c '
	set -eu
	version="$1"
	mkdir -p /fixtures/vendor
	: > /fixtures/hashes.txt
	while read -r family; do
		[ -n "$family" ] || continue
		name="trusttunnel_client-v${version}-linux-${family}"
		dir="/fixtures/vendor/$name"
		mkdir -p "$dir"
		printf "binary-%s\n" "$family" > "$dir/trusttunnel_client"
		printf "wizard-%s\n" "$family" > "$dir/setup_wizard"
		printf "sig-%s\n" "$family" > "$dir/trusttunnel_client.sig"
		printf "sig-%s\n" "$family" > "$dir/setup_wizard.sig"
		printf "license-%s\n" "$family" > "$dir/LICENSE"
		tar -czf "/fixtures/vendor/$name.tar.gz" -C /fixtures/vendor "$name"
		rm -rf "$dir"
		hash=$(sha256sum "/fixtures/vendor/$name.tar.gz" | awk "{ print \$1 }")
		printf "%s %s\n" "$family" "$hash" >> /fixtures/hashes.txt
	done < /fixtures/families.txt
' sh "$pkg_version" > "$WORK/fake-tarballs.log" 2>&1; then
	_tt_fail "the fake vendor tarballs are created"
	cat "$WORK/fake-tarballs.log"
	tt_test_summary
fi
_tt_pass "the fake vendor tarballs are created"

mkdir -p "$WORK/out"
if ! docker run --rm \
	-v "$ROOT:/work:ro" \
	-v "$WORK:/fixtures" \
	-w /work \
	-e TT_CLIENT_OUT_DIR=/fixtures/out \
	-e TT_CLIENT_TARBALL_DIR=/fixtures/vendor \
	-e TT_CLIENT_HASHES=/fixtures/hashes.txt \
	--entrypoint sh "$IMAGE" -c '
		set -eu
		while read -r pm arch; do
			[ -n "$arch" ] || continue
			/usr/local/bin/package-client build "$pm" "$arch"
		done < /fixtures/rows.txt
	' > "$WORK/build.log" 2>&1; then
	_tt_fail "the packager builds every matrix row"
	cat "$WORK/build.log"
	tt_test_summary
fi
_tt_pass "the packager builds every matrix row"

# Extract the metadata and the payload from every package. The container
# writes text dumps, so the host assertions stay portable.
if ! docker run --rm -v "$WORK:/fixtures" --entrypoint sh "$IMAGE" -c '
	set -eu
	install_dir="$1"
	pkg_name="$2"
	mkdir -p /fixtures/meta
	for f in /fixtures/out/*.apk; do
		[ -e "$f" ] || continue
		base=$(basename "$f")
		apk adbdump "$f" > "/fixtures/meta/$base.adbdump"
		rm -rf "/fixtures/meta/$base.extract"
		mkdir -p "/fixtures/meta/$base.extract"
		apk extract --allow-untrusted --no-chown --destination "/fixtures/meta/$base.extract" "$f" >/dev/null
		(
			cd "/fixtures/meta/$base.extract"
			find "$install_dir" -type f | while IFS= read -r p; do
				mode=$(stat -c "%a" "$p")
				printf "%s /%s\n" "$mode" "$p"
			done | sort
		) > "/fixtures/meta/$base.files"
		cat "/fixtures/meta/$base.extract/lib/apk/packages/$pkg_name.list" \
			> "/fixtures/meta/$base.list"
	done
	for f in /fixtures/out/*.ipk; do
		[ -e "$f" ] || continue
		base=$(basename "$f")
		tar xzOf "$f" ./control.tar.gz | tar xzO ./control > "/fixtures/meta/$base.control"
		tar tzf "$f" > "/fixtures/meta/$base.outerlist"
		size=$(tar xzOf "$f" ./data.tar.gz | gzip -dc | wc -c | tr -d " ")
		printf "%s\n" "$size" > "/fixtures/meta/$base.installed_size"
		rm -rf "/fixtures/meta/$base.extract"
		mkdir -p "/fixtures/meta/$base.extract"
		tar xzOf "$f" ./data.tar.gz | tar xzf - --no-same-owner -C "/fixtures/meta/$base.extract"
		(
			cd "/fixtures/meta/$base.extract"
			find "$install_dir" -type f | while IFS= read -r p; do
				mode=$(stat -c "%a" "$p")
				printf "%s /%s\n" "$mode" "$p"
			done | sort
		) > "/fixtures/meta/$base.files"
	done
' sh "$install_dir_rel" "$pkg_name" > "$WORK/inspect.log" 2>&1; then
	_tt_fail "the packages are inspected"
	cat "$WORK/inspect.log"
	tt_test_summary
fi
_tt_pass "the packages are inspected"

expected_files=$(expected_install_files)
expected_paths=$(printf '%s\n' "$expected_files" | awk '{ print $2 }' | sort)

while read -r pm arch; do
	[ -n "$arch" ] || continue
	family=$(family_for_arch "$arch")
	case "$pm" in
		apk) name="trusttunnel-client-${pkg_version}-r${pkg_release}-${arch}.apk" ;;
		ipk) name="trusttunnel-client_${pkg_version}-${pkg_release}_${arch}.ipk" ;;
		*) _tt_fail "unsupported package manager $pm"; continue ;;
	esac
	if [ ! -f "$WORK/out/$name" ]; then
		_tt_fail "$pm $arch package exists"
		continue
	fi
	_tt_pass "$pm $arch package exists"

	actual_files=$(cat "$WORK/meta/$name.files")
	assert_eq "$expected_files" "$actual_files" "$pm $arch files"

	for file in trusttunnel_client setup_wizard trusttunnel_client.sig setup_wizard.sig LICENSE; do
		case "$file" in
			trusttunnel_client) marker="binary-$family" ;;
			setup_wizard) marker="wizard-$family" ;;
			*.sig) marker="sig-$family" ;;
			LICENSE) marker="license-$family" ;;
		esac
		actual_marker=$(cat "$WORK/meta/$name.extract$install_dir/$file")
		assert_eq "$marker" "$actual_marker" "$pm $arch $file payload"
	done

	if [ "$pm" = apk ]; then
		if [ -f "$WORK/out/ARCH-$arch" ]; then
			_tt_pass "apk $arch marker exists"
		else
			_tt_fail "apk $arch marker exists"
		fi

		actual_fields=$(awk '
			/^info:/ { info = 1; next }
			/^paths:/ { info = 0 }
			info {
				sub(/^  /, "")
				if ($0 ~ /^(name|version|arch|license|origin|url|maintainer|description):/) print
			}
		' "$WORK/meta/$name.adbdump" | sort)
		expected_fields=$(printf '%s\n' \
			"name: $pkg_name" \
			"version: ${pkg_version}-r${pkg_release}" \
			"arch: $arch" \
			"license: $pkg_license" \
			"origin: feeds/ttowrt/packages/$pkg_name" \
			"url: $url" \
			"maintainer: $pkg_maintainer" \
			"description: $title" | sort)
		assert_eq "$expected_fields" "$actual_fields" "apk $arch metadata"

		actual_depends=$(awk '
			/^info:/ { info = 1; next }
			/^paths:/ { info = 0 }
			info && /^  depends:/ { indep = 1; next }
			info && /^  [a-z]/ { indep = 0 }
			indep && /^    - / { sub(/^    - /, ""); print }
		' "$WORK/meta/$name.adbdump" | sort | tr '\n' ' ' | sed 's/ $//')
		expected_depends=$(printf '%s\n' "$depends_raw" | tr ' ' '\n' | sed 's/^+//' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//')
		assert_eq "$expected_depends" "$actual_depends" "apk $arch depends"

		actual_paths=$(printf '%s\n' "$(cat "$WORK/meta/$name.list")" | sort)
		assert_eq "$expected_paths" "$actual_paths" "apk $arch package list"
	else
		assert_contains "$(cat "$WORK/meta/$name.outerlist")" "./debian-binary" "ipk $arch carries debian-binary"
		assert_contains "$(cat "$WORK/meta/$name.outerlist")" "./data.tar.gz" "ipk $arch carries data.tar.gz"
		assert_contains "$(cat "$WORK/meta/$name.outerlist")" "./control.tar.gz" "ipk $arch carries control.tar.gz"

		actual_fields=$(grep -E '^(Package|Version|Architecture|License|Section|URL|Maintainer|Source|SourceName|Description):' \
			"$WORK/meta/$name.control" | sort)
		expected_fields=$(printf '%s\n' \
			"Package: $pkg_name" \
			"Version: ${pkg_version}-${pkg_release}" \
			"Architecture: $arch" \
			"License: $pkg_license" \
			"Section: $section" \
			"URL: $url" \
			"Maintainer: $pkg_maintainer" \
			"Source: feeds/ttowrt/packages/$pkg_name" \
			"SourceName: $pkg_name" \
			"Description: $title" | sort)
		assert_eq "$expected_fields" "$actual_fields" "ipk $arch metadata"

		actual_depends=$(sed -n 's/^Depends: //p' "$WORK/meta/$name.control" \
			| tr ',' '\n' | sed 's/^ //' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//')
		expected_depends=$(printf '%s\n' "$depends_raw" | tr ' ' '\n' | sed 's/^+//' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//')
		assert_eq "$expected_depends" "$actual_depends" "ipk $arch depends"

		actual_size=$(sed -n 's/^Installed-Size: //p' "$WORK/meta/$name.control")
		expected_size=$(cat "$WORK/meta/$name.installed_size")
		assert_eq "$expected_size" "$actual_size" "ipk $arch installed size"
	fi
done < "$WORK/rows.txt"

tt_test_summary
