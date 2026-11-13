#!/bin/sh
# Pins the feed retention selector used by publish-repo.
#
# The published Pages site has a hard 1 GB limit, so the feed keeps only
# the newest few releases. The selector decides which release tags are
# downloaded again. Two failure modes are expensive and silent:
#   - keeping too many releases makes the site exceed the Pages limit,
#     and the deploy fails at the very end of a release;
#   - dropping the newest v* release removes the LuCI app from the feed,
#     so no new install works, even though the client feed still looks
#     healthy.
# The workflow-structure test cannot exercise this logic, so the selector
# is tested directly against sample tag lists.
. "$(dirname "$0")/lib.sh"

repo_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd) || exit 1
selector="$repo_root/tests/release/select-releases.sh"
tags_file="$TT_TEST_TMP/tags"

# run_selector <current-tag|-> <keep> <tags...> — newest tag first.
run_selector() {
	_rs_current=$1
	_rs_keep=$2
	shift 2
	: >"$tags_file"
	for _rs_tag in "$@"; do
		printf '%s\n' "$_rs_tag" >>"$tags_file"
	done
	sh "$selector" "$_rs_current" "$_rs_keep" "$tags_file"
}

# Fewer releases than the cap: keep all of them. The newest v* release
# is already in the set, so no app-only entry is added.
assert_eq \
	"$(printf 'v1.1.0\tfull\nv1.0.0\tfull')" \
	"$(run_selector - 3 v1.1.0 v1.0.0)" \
	"a dispatch run keeps every release when fewer than the cap exist"

# More releases than the cap: the current release occupies one slot, so
# only the newest keep-1 prior releases are downloaded again.
assert_eq \
	"$(printf 'client-v1.1.8\tfull\nv1.1.0\tfull')" \
	"$(run_selector v1.2.0 3 client-v1.1.8 v1.1.0 client-v1.1.7 v1.0.0)" \
	"a tag push keeps the current release plus the newest keep-1 prior releases"

# A client-only current release does not stage the app. The newest v*
# release is added as app-only when it is older than the retained set.
assert_eq \
	"$(printf 'client-v1.1.7\tfull\nclient-v1.1.6\tfull\nv1.0.0\tapp')" \
	"$(run_selector client-v1.1.8 3 client-v1.1.7 client-v1.1.6 v1.0.0)" \
	"a client-only current release adds the newest app release as app-only"

# The app release is not duplicated when the retained set already holds
# it: its client is then downloaded as part of the full release.
assert_eq \
	"$(printf 'v1.0.0\tfull\nclient-v1.1.7\tfull')" \
	"$(run_selector client-v1.1.8 3 v1.0.0 client-v1.1.7 client-v1.1.6)" \
	"the app release is not added twice when it is already retained"

# A dispatch run has no current release, so the cap applies to the prior
# releases in full.
assert_eq \
	"$(printf 'client-v1.1.8\tfull\nv1.1.0\tfull\nclient-v1.1.7\tfull')" \
	"$(run_selector - 3 client-v1.1.8 v1.1.0 client-v1.1.7 v1.0.0)" \
	"a dispatch run keeps the newest keep releases"

# Foreign release tags never enter the feed.
assert_eq \
	"$(printf 'v1.0.0\tfull')" \
	"$(run_selector - 3 feed-x86_64 docs-migration v1.0.0)" \
	"foreign tags are ignored"

# The current release is excluded from the download list even when the
# release already exists (a re-run of the same tag).
assert_eq \
	"$(printf 'v1.0.0\tfull')" \
	"$(run_selector v1.1.0 3 v1.1.0 v1.0.0)" \
	"the current release is not downloaded again"

# keep=1 with a client-only current release: the current client is the
# only retained client, and the app still comes from its release.
assert_eq \
	"$(printf 'v1.0.0\tapp')" \
	"$(run_selector client-v1.1.8 1 v1.0.0 client-v1.1.7)" \
	"keep=1 still retains the app for a client-only release"

# keep=1 on a dispatch: the newest release plus the app release when the
# newest release is client-only.
assert_eq \
	"$(printf 'client-v1.1.8\tfull\nv1.0.0\tapp')" \
	"$(run_selector - 1 client-v1.1.8 v1.0.0)" \
	"keep=1 on a dispatch adds the app release when the newest is client-only"

# A client-only history has no app release to add. The selector reports
# the client releases only; the publish verification then fails loudly
# because a feed without the app cannot install it.
assert_eq \
	"$(printf 'client-v1.1.8\tfull\nclient-v1.1.7\tfull')" \
	"$(run_selector - 3 client-v1.1.8 client-v1.1.7)" \
	"a client-only history yields no app-only entry"

assert_exit 1 "missing arguments fail" sh "$selector"
assert_exit 1 "a non-numeric keep count fails" sh "$selector" - abc "$tags_file"
assert_exit 1 "a zero keep count fails" sh "$selector" - 0 "$tags_file"
assert_exit 1 "a missing tags file fails" sh "$selector" - 3 "$TT_TEST_TMP/missing"

tt_test_summary
