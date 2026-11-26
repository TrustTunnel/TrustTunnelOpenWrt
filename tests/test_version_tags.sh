#!/bin/sh
# Pins the package version derivation in the app, diagnostics and runtime
# Makefiles.
#
# The app version comes from the nearest `vX.Y.Z` release tag. Client
# releases use `client-vX.Y.Z` tags in the SAME repository, and they are
# usually the nearest tag after a client bump. A plain `git describe`
# would then name the app after the client release (for example
# `client-v1.3.0`), so a non-tag build — the documented master dispatch
# that republishes the feed — would produce a package no feed can match
# and the app would never receive the fix. The Makefiles therefore match
# only `v[0-9]*` tags.
#
# The test extracts each Makefile's real PKG_VERSION shell expression and
# runs it in a scratch repository, so the assertions cannot drift from
# the Makefiles. The fallback value is the last released app version; it
# changes with every release.
. "$(dirname "$0")/lib.sh"

repo_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd) || exit 1

command -v git >/dev/null 2>&1 || tt_skip "git is not installed"

makefiles='packages/luci-app-trusttunnel/Makefile
packages/luci-app-trusttunnel-diagnostics/Makefile
packages/trusttunnel/Makefile'

# version_from_makefile <makefile> — extract the PKG_VERSION assignment's
# shell expression verbatim (drop the make-level `$(strip $(shell ...))`
# wrapper, turn `$$` back into `$`) and run it in $TEST_REPO.
version_from_makefile() {
	_vm_mk=$1
	_vm_expr=$(sed -n 's/^PKG_VERSION:=\$(strip \$(shell \(.*\)))$/\1/p' "$_vm_mk")
	[ -n "$_vm_expr" ] || return 1
	_vm_expr=$(printf '%s\n' "$_vm_expr" | sed 's/\$\$/$/g')
	(cd "$TEST_REPO" && sh -c "$_vm_expr")
}

new_repo() {
	rm -rf "$1"
	mkdir -p "$1"
	(
		cd "$1" || exit 1
		git init -q
		git config user.email test@example.com
		git config user.name Test
		printf 'one\n' > file
		git add file
		git commit -qm one
	)
}

commit() {
	(
		cd "$TEST_REPO" || exit 1
		printf '%s\n' "$1" >> file
		git add file
		git commit -qm "$1"
	)
}

tag() {
	(cd "$TEST_REPO" && git tag "$1")
}

# assert_version <expected> <message> — check the expression in every
# package Makefile. The assertions run in a subshell of the pipeline, but
# the counters live in files, so the tally stays correct.
assert_version() {
	_av_expected=$1
	_av_message=$2
	printf '%s\n' "$makefiles" | while IFS= read -r _av_mk; do
		[ -n "$_av_mk" ] || continue
		assert_eq "$_av_expected" \
			"$(version_from_makefile "$repo_root/$_av_mk")" \
			"$_av_message ($_av_mk)"
	done
}

# A client tag is the nearest tag. The app must keep reporting the last
# app release, not the client version.
TEST_REPO="$TT_TEST_TMP/repo-client-nearest"
new_repo "$TEST_REPO"
tag v1.4.0
commit two
tag client-v9.9.9
assert_version 1.4.0 "a nearer client tag is ignored"

# An app tag and a client tag on the same commit: the app tag wins even
# when the client version is numerically higher. This is the real release
# shape: a v1.0.1 app tag lands on the commit that already carries
# client-v1.3.0, and a plain `git describe` would pick the client tag.
TEST_REPO="$TT_TEST_TMP/repo-same-commit"
new_repo "$TEST_REPO"
tag v1.0.1
tag client-v1.3.0
assert_version 1.0.1 "an app tag wins over a higher client tag on the same commit"

# No app tag at all: the fallback applies even when a client tag exists.
TEST_REPO="$TT_TEST_TMP/repo-no-app-tag"
new_repo "$TEST_REPO"
tag client-v9.9.9
assert_version 1.0.1 "client tags alone fall back to the last released version"

tt_test_summary
