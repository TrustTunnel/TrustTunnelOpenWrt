#!/bin/sh
# Select the release tags that the Pages feed keeps.
#
# The published site has a hard 1 GB limit, so the feed keeps only the
# newest <keep> releases instead of every release ever published. The
# version releases themselves stay on GitHub: an older version is still
# downloadable from its own release, but it is no longer in the feed.
#
# The feed must always carry the newest LuCI app packages. A client-v*
# release does not build the app, so a run of client-only releases could
# otherwise push the app packages out of the retained set and break
# every new install. The newest v* release is therefore added as an
# app-only entry when it is not already in the full set. The publish
# workflow fetches only its app/runtime packages, so its client does not
# consume a retention slot.
#
# Usage:
#   select-releases.sh <current-tag|-> <keep> <tags-file>
#
# The tags file holds one release tag per line, newest first, with draft
# releases removed. The current release counts as one kept release: the
# publish job stages its packages itself, so it is not downloaded. Use
# "-" when there is no current release (a dispatch run).
#
# Output: one "tag<TAB>full|app" line per selected release.
#   full — download every package pattern (app, runtime and clients)
#   app  — download only the app/runtime patterns
set -eu

die() {
	printf 'select-releases: %s\n' "$*" >&2
	exit 1
}

current=${1:-}
keep=${2:-}
tags_file=${3:-}

[ -n "$keep" ] && [ -n "$tags_file" ] ||
	die "usage: select-releases.sh <current-tag|-> <keep> <tags-file>"
case $keep in
'' | *[!0-9]*) die "the keep count must be a positive integer: $keep" ;;
esac
[ "$keep" -ge 1 ] || die "the keep count must be a positive integer: $keep"
[ -f "$tags_file" ] || die "cannot read the tags file: $tags_file"

# A branch name on a dispatch run is not a release tag. Normalize it so
# the count below means the same thing for a dispatch and a tag push.
case $current in
v[0-9]* | client-v*) ;;
*) current=- ;;
esac

work=$(mktemp -d) || die "cannot create a temporary directory"
# shellcheck disable=SC2064
trap "rm -rf '$work'" EXIT INT TERM

# Only the version releases belong to the package feed. Foreign tags
# (for example a future feed-* release) are ignored. The current release
# is excluded: its packages come from the current artifacts.
: >"$work/eligible"
while IFS= read -r tag; do
	[ -n "$tag" ] || continue
	case $tag in
	v[0-9]* | client-v*) ;;
	*) continue ;;
	esac
	[ "$tag" = "$current" ] && continue
	printf '%s\n' "$tag" >>"$work/eligible"
done <"$tags_file"

# The current release is staged by the publish job, so it occupies one
# slot. A dispatch run has no current release.
full_count=$keep
if [ "$current" != - ]; then
	full_count=$((keep - 1))
fi

if [ "$full_count" -gt 0 ]; then
	head -n "$full_count" "$work/eligible" >"$work/full"
else
	: >"$work/full"
fi
: >"$work/selected"
while IFS= read -r tag; do
	printf '%s\n' "$tag" >>"$work/selected"
	printf '%s\tfull\n' "$tag"
done <"$work/full"

# A v* current release stages the app packages itself. Otherwise the feed
# needs the newest v* release, even when it is older than the retained
# set. Add it only once.
case $current in
v[0-9]*) exit 0 ;;
esac
app_tag=""
while IFS= read -r tag; do
	case $tag in
	v[0-9]*)
		app_tag=$tag
		break
		;;
	esac
done <"$work/eligible"
[ -n "$app_tag" ] || exit 0
already=0
while IFS= read -r tag; do
	if [ "$tag" = "$app_tag" ]; then
		already=1
		break
	fi
done <"$work/selected"
[ "$already" -eq 1 ] || printf '%s\tapp\n' "$app_tag"
