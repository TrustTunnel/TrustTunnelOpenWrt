#!/bin/sh
# Pins the automatic client bump contract.
#
# The scheduled update-client workflow must rewrite exactly two files:
# PKG_VERSION and the five per-family PKG_HASH values in the client
# Makefile, and the matching five lines in the hash fixture. Everything
# else must stay byte-identical. The script must verify every vendor
# tarball against the release digest and the archive layout before it
# writes anything, because a wrong hash or a missing member would fail
# later in the release matrix or, worse, publish a different binary.
#
# The test uses fake tarballs and a fake assets table. It never downloads
# the vendor release. The script reads the Makefile through
# tests/release/package-client.sh, the consumer the release pipeline uses,
# so the test also proves the two parsers agree. A stale hash fixture must
# be repaired without touching the Makefile.
. "$(dirname "$0")/lib.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/.github/scripts/update-client.sh"
PACKAGER="$ROOT/tests/release/package-client.sh"
WORK="$TT_TEST_TMP/update-client"
VERSION=9.9.9
FAMILIES="x86_64 aarch64 armv7 mips mipsel"

rm -rf "$WORK"
mkdir -p "$WORK/root/packages/trusttunnel-client" \
	"$WORK/root/tests/fixtures" \
	"$WORK/vendor"

reset_root() {
	cp "$ROOT/packages/trusttunnel-client/Makefile" \
		"$WORK/root/packages/trusttunnel-client/Makefile"
	cp "$ROOT/tests/fixtures/client-hashes.txt" \
		"$WORK/root/tests/fixtures/client-hashes.txt"
}

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{ print $1 }'
	else
		shasum -a 256 "$1" | awk '{ print $1 }'
	fi
}

make_family() {
	_version=$1
	_family=$2
	_name="trusttunnel_client-v${_version}-linux-${_family}"
	_dir="$WORK/vendor/$_name"
	rm -rf "$_dir"
	mkdir -p "$_dir"
	printf 'binary-%s\n' "$_family" > "$_dir/trusttunnel_client"
	printf 'wizard-%s\n' "$_family" > "$_dir/setup_wizard"
	printf 'sig-%s\n' "$_family" > "$_dir/trusttunnel_client.sig"
	printf 'sig-%s\n' "$_family" > "$_dir/setup_wizard.sig"
	printf 'license-%s\n' "$_family" > "$_dir/LICENSE"
	tar -czf "$WORK/vendor/$_name.tar.gz" -C "$WORK/vendor" "$_name"
	rm -rf "$_dir"
}

make_assets() {
	_version=$1
	_out=$2
	: > "$_out"
	for _family in $FAMILIES; do
		_name="trusttunnel_client-v${_version}-linux-${_family}.tar.gz"
		_hash=$(sha256_of "$WORK/vendor/$_name")
		printf '%s\t%s\t%s\n' "$_name" "https://example.invalid/$_name" \
			"sha256:$_hash" >> "$_out"
	done
}

make_release() {
	_version=$1
	for _family in $FAMILIES; do
		make_family "$_version" "$_family"
	done
	make_assets "$_version" "$WORK/assets.tsv"
}

run_ok() {
	_message=$1
	shift
	if "$@" > "$WORK/last.log" 2>&1; then
		_tt_pass "$_message"
	else
		_tt_fail "$_message"
		sed 's/^/    /' "$WORK/last.log"
	fi
}

run_fails() {
	_message=$1
	shift
	if "$@" > "$WORK/last.log" 2>&1; then
		_tt_fail "$_message"
		sed 's/^/    /' "$WORK/last.log"
	else
		_tt_pass "$_message"
	fi
}

expected_digest() {
	_family=$1
	awk -F '\t' -v name="trusttunnel_client-v${VERSION}-linux-${_family}.tar.gz" \
		'$1 == name { print $3; exit }' "$WORK/assets.tsv" | sed 's/^sha256://'
}

reset_root
make_release "$VERSION"
pinned=$(sed -n 's/^PKG_VERSION:=//p' "$ROOT/packages/trusttunnel-client/Makefile" | head -n 1)

run_ok "the bump runs" sh "$SCRIPT" --root "$WORK/root" --version "$VERSION" \
	--assets "$WORK/assets.tsv" --tarball-dir "$WORK/vendor"

assert_eq "$VERSION" "$(sed -n 's/^PKG_VERSION:=//p' "$WORK/root/packages/trusttunnel-client/Makefile" | head -n 1)" \
	"the Makefile version is rewritten"
for family in $FAMILIES; do
	expected=$(expected_digest "$family")
	actual=$(TT_REPO_DIR="$WORK/root" sh "$PACKAGER" hash "$family" 2>&1) \
		|| { _tt_fail "the $family hash reads back"; continue; }
	assert_eq "$expected" "$actual" "the $family Makefile hash matches the release digest"
	fixture=$(awk -v family="$family" '$1 == family { print $2 }' \
		"$WORK/root/tests/fixtures/client-hashes.txt")
	assert_eq "$expected" "$fixture" "the $family fixture hash matches the release digest"
done
assert_contains "$(cat "$WORK/root/packages/trusttunnel-client/Makefile")" \
	"# The version is the VENDOR release" "the Makefile comments are preserved"
assert_contains "$(cat "$WORK/root/tests/fixtures/client-hashes.txt")" \
	"# This fixture pins the Makefile's PKG_HASH parsing" "the fixture comments are preserved"
assert_eq "1" "$(sed -n 's/^PKG_RELEASE:=//p' "$WORK/root/packages/trusttunnel-client/Makefile")" \
	"PKG_RELEASE is unchanged"

before_makefile=$(sha256_of "$WORK/root/packages/trusttunnel-client/Makefile")
before_fixture=$(sha256_of "$WORK/root/tests/fixtures/client-hashes.txt")
run_ok "a second run is a no-op" sh "$SCRIPT" --root "$WORK/root" --version "$VERSION" \
	--assets "$WORK/assets.tsv" --tarball-dir "$WORK/vendor"
assert_eq "$before_makefile" "$(sha256_of "$WORK/root/packages/trusttunnel-client/Makefile")" \
	"a second run leaves the Makefile unchanged"
assert_eq "$before_fixture" "$(sha256_of "$WORK/root/tests/fixtures/client-hashes.txt")" \
	"a second run leaves the fixture unchanged"

# A stale fixture must be repaired even when the Makefile already matches.
# The current check used to look only at the Makefile, so a corrupted
# fixture made the script report "already at" and left the tree broken.
before_makefile=$(sha256_of "$WORK/root/packages/trusttunnel-client/Makefile")
awk -v family=aarch64 'BEGIN { OFS = " " } $1 == family { $2 = sprintf("%064d", 0) } { print }' \
	"$WORK/root/tests/fixtures/client-hashes.txt" > "$WORK/fixture.tmp"
mv "$WORK/fixture.tmp" "$WORK/root/tests/fixtures/client-hashes.txt"
run_ok "a stale fixture is repaired" sh "$SCRIPT" --root "$WORK/root" --version "$VERSION" \
	--assets "$WORK/assets.tsv" --tarball-dir "$WORK/vendor"
assert_eq "$before_makefile" "$(sha256_of "$WORK/root/packages/trusttunnel-client/Makefile")" \
	"the repair leaves the Makefile unchanged"
assert_eq "$(expected_digest aarch64)" \
	"$(awk -v family=aarch64 '$1 == family { print $2 }' "$WORK/root/tests/fixtures/client-hashes.txt")" \
	"the repair restores the aarch64 fixture hash"

reset_root
before_makefile=$(sha256_of "$WORK/root/packages/trusttunnel-client/Makefile")
before_fixture=$(sha256_of "$WORK/root/tests/fixtures/client-hashes.txt")
run_ok "the dry run succeeds" sh "$SCRIPT" --root "$WORK/root" --version "$VERSION" \
	--assets "$WORK/assets.tsv" --tarball-dir "$WORK/vendor" --dry-run
assert_eq "$before_makefile" "$(sha256_of "$WORK/root/packages/trusttunnel-client/Makefile")" \
	"the dry run leaves the Makefile unchanged"
assert_eq "$before_fixture" "$(sha256_of "$WORK/root/tests/fixtures/client-hashes.txt")" \
	"the dry run leaves the fixture unchanged"
assert_contains "$(cat "$WORK/last.log")" "$pinned -> $VERSION" \
	"the dry run prints the version change"

reset_root
grep -v 'linux-mips\.tar\.gz' "$WORK/assets.tsv" > "$WORK/assets-no-mips.tsv"
run_fails "a missing family fails" sh "$SCRIPT" --root "$WORK/root" --version "$VERSION" \
	--assets "$WORK/assets-no-mips.tsv" --tarball-dir "$WORK/vendor"
assert_contains "$(cat "$WORK/last.log")" "the release has no" "the missing family is reported"
assert_eq "$pinned" "$(sed -n 's/^PKG_VERSION:=//p' "$WORK/root/packages/trusttunnel-client/Makefile" | head -n 1)" \
	"a failed bump leaves the Makefile unchanged"

reset_root
awk -F '\t' 'BEGIN { OFS = "\t" } NR == 1 { $3 = "sha256:" sprintf("%064d", 0) } { print }' \
	"$WORK/assets.tsv" > "$WORK/assets-bad-digest.tsv"
run_fails "a digest mismatch fails" sh "$SCRIPT" --root "$WORK/root" --version "$VERSION" \
	--assets "$WORK/assets-bad-digest.tsv" --tarball-dir "$WORK/vendor"
assert_contains "$(cat "$WORK/last.log")" "hash mismatch" "the digest mismatch is reported"

reset_root
run_fails "a malformed version fails" sh "$SCRIPT" --root "$WORK/root" --version 9.9 \
	--assets "$WORK/assets.tsv" --tarball-dir "$WORK/vendor"
assert_contains "$(cat "$WORK/last.log")" "unsupported vendor version" "the malformed version is reported"

reset_root
broken="trusttunnel_client-v${VERSION}-linux-x86_64"
rm -rf "$WORK/vendor/$broken"
mkdir -p "$WORK/vendor/$broken"
printf 'binary\n' > "$WORK/vendor/$broken/trusttunnel_client"
printf 'wizard\n' > "$WORK/vendor/$broken/setup_wizard"
printf 'sig\n' > "$WORK/vendor/$broken/trusttunnel_client.sig"
printf 'sig\n' > "$WORK/vendor/$broken/setup_wizard.sig"
tar -czf "$WORK/vendor/$broken.tar.gz" -C "$WORK/vendor" "$broken"
rm -rf "$WORK/vendor/$broken"
make_assets "$VERSION" "$WORK/assets-broken.tsv"
run_fails "a tarball without LICENSE fails" sh "$SCRIPT" --root "$WORK/root" --version "$VERSION" \
	--assets "$WORK/assets-broken.tsv" --tarball-dir "$WORK/vendor"
assert_contains "$(cat "$WORK/last.log")" "LICENSE" "the missing archive member is reported"

tt_test_summary
