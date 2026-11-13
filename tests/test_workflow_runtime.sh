#!/bin/sh
# Pins the GitHub Actions runtime choices.
#
# `ubuntu-latest` is migrating to a new image, and `actions/cache@v4`
# targets the deprecated Node 20 runtime. A silent image change can break
# the Docker-based tests, and the Node notice becomes a forced migration.
# The workflows pin the runner image to ubuntu-24.04 and the cache action
# to the Node 24 major.
#
# The ci.yml shell gates used the BSD word-boundary classes [[:<:]] and
# [[:>:]]. GNU grep on the hosted runner rejects them with "Invalid
# character class name", so the gates silently did nothing. The workflows
# must use a POSIX bracket expression instead.
. "$(dirname "$0")/lib.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKFLOWS="$ROOT/.github/workflows"

for wf in "$WORKFLOWS"/*.yml; do
	name=$(basename "$wf")

	# Every job must name the pinned image. The old label is banned, so
	# a runner-image migration cannot move the Docker-based gates.
	bad=$(grep -E '^[[:space:]]*runs-on:' "$wf" | grep -v 'ubuntu-24.04' || true)
	if [ -n "$bad" ]; then
		_tt_fail "$name pins every runner to ubuntu-24.04"
		printf '%s\n' "$bad" | sed 's/^/    /'
	else
		_tt_pass "$name pins every runner to ubuntu-24.04"
	fi
	if grep -Eq 'ubuntu-latest' "$wf"; then
		_tt_fail "$name does not use ubuntu-latest"
	else
		_tt_pass "$name does not use ubuntu-latest"
	fi

	# GNU grep does not know the BSD word-boundary classes.
	if grep -Eq '\[\[:<:\]\]|\[\[:>:\]\]' "$wf"; then
		_tt_fail "$name uses a non-POSIX word-boundary class"
	else
		_tt_pass "$name uses POSIX grep classes"
	fi
done

# The cache action must run on the Node 24 runtime. v4 targets Node 20
# and the runner forces it onto Node 24 with a deprecation warning.
cache="$WORKFLOWS/integration.yml"
if grep -Eq '^[[:space:]]*uses: actions/cache@v6$' "$cache"; then
	_tt_pass "the cache action runs on Node 24"
else
	_tt_fail "the cache action runs on Node 24"
fi
if grep -Eq '^[[:space:]]*uses: actions/cache@v[0-5]$' "$cache"; then
	_tt_fail "the cache action is not on a pre-Node-24 major"
else
	_tt_pass "the cache action is not on a pre-Node-24 major"
fi

tt_test_summary
