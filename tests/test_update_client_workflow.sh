#!/bin/sh
# Pins the scheduled client updater contract.
#
# The updater is a release gate, so its structure is a contract like the
# client-only release path in release.yml. The failure modes are silent
# and expensive: a direct push to master would publish an untested binary,
# a missing integration wait would skip the only tunnel test, and a tag
# push with GITHUB_TOKEN would not start the release pipeline at all.
#
# The test reads the workflow as text. It needs no YAML parser and no
# network.
. "$(dirname "$0")/lib.sh"

WF=.github/workflows/update-client.yml
RELEASE=.github/workflows/release.yml
CI=.github/workflows/ci.yml

[ -f "$WF" ] || { echo "  FAIL: cannot read $WF"; exit 1; }
[ -f "$RELEASE" ] || { echo "  FAIL: cannot read $RELEASE"; exit 1; }
[ -f "$CI" ] || { echo "  FAIL: cannot read $CI"; exit 1; }
wf="$(cat "$WF")"
release="$(cat "$RELEASE")"
ci="$(cat "$CI")"

assert_contains "$wf" 'cron: "0 6 * * *"' "the updater checks daily"
assert_contains "$wf" 'workflow_dispatch:' "the updater can run on demand"
assert_contains "$wf" 'dry_run:' "the dispatch has a dry-run input"
assert_contains "$wf" "github.repository == 'TrustTunnel/TrustTunnelOpenWrt' && github.ref == 'refs/heads/master'" \
	"the updater runs only on the project's master"
assert_contains "$wf" 'contents: write' "the updater can push a branch and a tag"
assert_contains "$wf" 'actions: write' "the updater can dispatch the test and release workflows"
assert_contains "$wf" 'group: update-client' "the updater runs one at a time"
assert_contains "$wf" 'repos/TrustTunnel/TrustTunnelClient/releases/latest' \
	"the updater reads the latest stable vendor release"
assert_contains "$wf" '.github/scripts/update-client.sh' "the updater uses the bump script"
assert_contains "$wf" 'for family in x86_64 aarch64 armv7 mips mipsel; do' \
	"the updater requires all five families"
assert_contains "$wf" 'x86_64|aarch64|armv7|mips|mipsel' \
	"the updater filters the five Linux asset families"
assert_contains "$wf" 'automation/client-' "the updater commits on an automation branch"
assert_contains "$wf" 'release: update the client to' "the bump commit follows the project style"
assert_contains "$wf" 'gh workflow run ci.yml --ref' "the updater dispatches the contract suite"
assert_contains "$wf" 'gh workflow run integration.yml --ref' "the updater dispatches the integration suite"
assert_contains "$wf" 'gh run watch' "the updater waits for the suites"
assert_contains "$wf" 'master moved during the run' "the updater refuses to merge into a moved master"
assert_contains "$wf" 'client-v$VERSION' "the updater creates the client tag"
assert_contains "$wf" 'gh workflow run release.yml --ref' "the updater dispatches the release pipeline"
assert_contains "$wf" 'gh release view' "the updater checks for an existing release"
assert_contains "$wf" "action == 'release'" "the updater re-dispatches a missing release"
assert_contains "$wf" 'changed while the pin already names that version' \
	"a same-version asset change fails loudly"
assert_contains "$wf" 'already exists but the checked-out tree does not match it' \
	"a stale tag with a different tree fails loudly"
assert_contains "$wf" 'Dry run complete' "the dry run stops before publishing"

# The scheduled job must not depend on a repository secret. A
# GITHUB_TOKEN with contents and actions write is enough for the branch,
# the tag and the dispatches.
if printf '%s\n' "$wf" | grep -q 'secrets\.'; then
	_tt_fail "the updater uses no repository secret"
else
	_tt_pass "the updater uses no repository secret"
fi

# release.yml must accept the dispatch the updater sends, and it must keep
# the master dispatch for the repository + site republish.
assert_contains "$release" 'refs/tags/client-v*)' "release.yml accepts a dispatch on a client tag"
assert_contains "$release" 'releasing the client' "release.yml names the client dispatch"
assert_contains "$release" 'refs/heads/master)' "release.yml keeps the master dispatch"
assert_contains "$release" 'Dispatch on master: republishing the repositories and the site' \
	"release.yml keeps the master dispatch behavior"

# ci.yml must be dispatchable on the automation branch, and its shellcheck
# list must cover the new files.
assert_contains "$ci" 'workflow_dispatch:' "ci.yml can be dispatched on the automation branch"
assert_contains "$ci" '.github/scripts/update-client.sh' "ci.yml lints the bump script"
assert_contains "$ci" 'tests/test_update_client.sh' "ci.yml lints the bump test"
assert_contains "$ci" 'tests/test_update_client_workflow.sh' "ci.yml lints this test"

tt_test_summary
