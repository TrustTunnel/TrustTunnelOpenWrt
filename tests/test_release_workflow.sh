#!/bin/sh
# Pins the client-only release path in .github/workflows/release.yml: a
# client-v* tag must publish a new client without rebuilding the LuCI app
# or re-running the full integration suite, and the publish step must not
# be blocked by those skipped jobs. The failure modes are silent and
# expensive (a broken gate fails late in a 39-arch matrix, or publishes a
# release whose packages do not match its tag), so the workflow structure
# is a contract, like the dependency declarations in test_deps.sh.
#
# It also pins the feed retention contract: the Pages site has a hard
# 1 GB limit, so the feed keeps only the newest TT_FEED_KEEP_RELEASES
# releases and the publish step refuses to deploy a larger tree. The
# selector always keeps the newest v* app release; a run of client-only
# releases must not push the app out of the feed. The selector's own
# behavior is covered by test_select_releases.sh. An older retained
# client must still be installable, so the pin verification stays.
#
# The client package is prebuilt, so the client matrix must use the
# shared packager image, not the SDK. The packager image is built once
# before the matrix and passed to every row.
. "$(dirname "$0")/lib.sh"

WF=.github/workflows/release.yml
[ -f "$WF" ] || { echo "  FAIL: cannot read $WF"; exit 1; }
wf="$(cat "$WF")"

# Extract one top-level job block (two-space indent) from the workflow.
job_body() {
	awk -v job="$1" '
		$0 ~ "^  " job ":" { inbody = 1; next }
		inbody && $0 ~ "^  [a-z][a-z0-9-]*:" { exit }
		inbody { print }
	' "$WF"
}

# The trigger: client-v* tags enter the same pipeline as v* tags.
assert_contains "$wf" '- "client-v*"' "release.yml triggers on client-v* tags"

# The gate job refuses runs that are not tag pushes: it must accept
# client-v* tags too, or a client-only release would be refused before
# any build starts.
assert_contains "$(job_body gate)" 'refs/tags/v*|refs/tags/client-v*' "the gate accepts client-v* tag pushes"

# The app build must be skipped on client-v* tags: its artifact-name
# assertion derives the version from the tag, and on a client-v* tag it
# would demand a client version in the app's file name and fail.
assert_contains "$(job_body build)" "!startsWith(github.ref, 'refs/tags/client-v')" "the app build skips client-v* tags"

# The full end-to-end suite is deliberately skipped for client-only
# releases; the publish step verifies the new client against the current
# app instead.
assert_contains "$(job_body verify-integration)" "!startsWith(github.ref, 'refs/tags/client-v')" "verify-integration skips client-v* tags"

# The client matrix must assert the generated package against the tag —
# the mirror of the app's own tag-matching assertion, scoped to client
# tags.
assert_contains "$(job_body package-client)" "Assert the client version matches the tag" "package-client asserts the client version against a client-v* tag"
assert_contains "$(job_body package-client)" 'GITHUB_REF_NAME#client-v' "package-client derives the expected version from the tag"

# The prebuilt client must not run the SDK. The packager image is built
# once and every matrix row reuses it.
assert_contains "$(job_body prepare-packager)" "tests/release/packager.Dockerfile" "prepare-packager builds the packager image"
assert_contains "$(job_body prepare-packager)" "name: package-client-packager" "prepare-packager uploads the shared image"
assert_contains "$(job_body package-client)" "needs: [gate, prepare-packager]" "package-client waits for the packager image"
assert_contains "$(job_body package-client)" "package-client-packager" "package-client downloads the shared image"
assert_contains "$(job_body package-client)" "docker load -i packager.tar.gz" "package-client loads the shared image"
assert_contains "$(job_body package-client)" "package-client.sh" "package-client checks the packager script in the recipe"
assert_contains "$(job_body package-client)" "packager.Dockerfile" "package-client checks the packager image in the recipe"
assert_contains "$(job_body publish-repo)" "needs: [build, prepare-packager, package-client, verify-integration]" "publish-repo waits for the packager image"
assert_contains "$(job_body publish-repo)" "staging/releases/25.12.5/package-client.sh" "publish-repo stores the packager script"
assert_contains "$(job_body publish-repo)" "staging/releases/22.03.7/package-client.sh" "publish-repo stores the packager script for opkg"
if printf '%s\n' "$(job_body package-client)" | grep -q "openwrt/gh-action-sdk"; then
	_tt_fail "package-client does not run the SDK"
else
	_tt_pass "package-client does not run the SDK"
fi
if printf '%s\n' "$(job_body package-client)" | grep -q "restricted-feeds.sh"; then
	_tt_fail "package-client does not clone the SDK feeds"
else
	_tt_pass "package-client does not clone the SDK feeds"
fi

# The publish job must run when the app build and the integration run
# were skipped (its needs then include skipped jobs), but must not run
# when anything failed: !failure() && !cancelled() is the gate.
assert_contains "$(job_body publish-repo)" '!failure() && !cancelled()' "publish-repo runs past skipped jobs but not past failures"

# On a client-only release the app artifacts do not exist: the download
# steps are gated, and the app is merged from the prior releases instead.
assert_contains "$(job_body publish-repo)" "Download the LuCI packages (apk)" "publish-repo still downloads the app artifacts on v* tags"
assert_contains "$(job_body publish-repo)" "!startsWith(github.ref, 'refs/tags/client-v')" "the app download steps are gated on client-v* tags"

# The rootfs verification asserts the installed client version: on a
# client-v* release this is what proves the repositories serve the new
# client together with the current app.
assert_contains "$(job_body publish-repo)" 'grep -q "$CLIENT_VERSION"' "the rootfs verification asserts the installed client version"

# The release upload splits: a v* tag carries app+client, a client-v*
# tag the client files alone (the app is unchanged and lives on its own
# release).
assert_contains "$(job_body publish-repo)" "Upload the client files to the client GitHub release" "publish-repo uploads a client-only release"
assert_contains "$(job_body publish-repo)" "startsWith(github.ref, 'refs/tags/v')" "the app+client upload step is scoped to v* tags"

# The feed retention cap: the Pages site has a hard 1 GB limit, so the
# publish job keeps only the newest TT_FEED_KEEP_RELEASES releases. The
# selector call, the cap constant and the guards are the workflow half
# of the contract; test_select_releases.sh covers the selection itself.
assert_contains "$(job_body publish-repo)" 'TT_FEED_KEEP_RELEASES: "3"' "publish-repo sets the retention cap"
assert_contains "$(job_body publish-repo)" "tests/release/select-releases.sh" "publish-repo uses the retention selector"
assert_contains "$(job_body publish-repo)" "gh api --paginate" "publish-repo lists every release, not the newest 100"
assert_contains "$(job_body publish-repo)" '[ "$mode" = app ]' "the selector's app-only mode has its own download branch"
assert_contains "$(job_body publish-repo)" 'TT_FEED_MAX_MB: "900"' "publish-repo caps the assembled tree below the Pages limit"
assert_contains "$(job_body publish-repo)" "du -sm staging/releases" "publish-repo checks the assembled tree size"
assert_contains "$(job_body publish-repo)" "trusttunnel-client-*.apk' | wc -l" "publish-repo checks the client-version count"

# The publish step must exercise the pinning contract: discover the
# newest older client version in the assembled x86_64 feeds, then install
# it in a fresh container — apk by pkg=version from the signed index,
# opkg from its exact ipk (opkg has no pkg=version CLI syntax).
assert_contains "$(job_body publish-repo)" "Find an older client version to pin" "publish-repo discovers an older client version to pin"
assert_contains "$(job_body publish-repo)" "Verify an older apk client can be pinned" "publish-repo verifies the apk pin install"
assert_contains "$(job_body publish-repo)" "Verify an older ipk client can be pinned" "publish-repo verifies the ipk pin install"
assert_contains "$(job_body publish-repo)" "steps.clientpin.outputs.apk_pin != ''" "the apk pin check is skipped when the feed has no older version"
assert_contains "$(job_body publish-repo)" "steps.clientpin.outputs.opkg_pin != ''" "the ipk pin check is skipped when the feed has no older version"
assert_contains "$(job_body publish-repo)" 'apk add "trusttunnel-client=$PIN_VERSION"' "the apk pin check installs the exact pinned version"
assert_contains "$(job_body publish-repo)" 'trusttunnel-client_${PIN_VERSION}_x86_64.ipk' "the ipk pin check installs the exact feed file"
assert_contains "$(job_body publish-repo)" 'opkg list trusttunnel-client | grep -q' "the ipk pin check asserts the old version is indexed"

tt_test_summary
