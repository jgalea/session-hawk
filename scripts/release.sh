#!/bin/zsh
#
# Cut a Session Hawk release: build (signed + notarized if a Developer ID
# identity and notary profile are available, unsigned otherwise), then
# publish it as a GitHub release with the DMG and zip attached.
#
# Usage:
#   zsh scripts/release.sh <version> [--notes-file <path>] [--draft]
#
# Example:
#   zsh scripts/release.sh 1.1.0
#   zsh scripts/release.sh 1.1.0 --notes-file release-notes.md

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: zsh scripts/release.sh <version> [--notes-file <path>] [--draft]" >&2
    exit 1
fi

version="$1"
shift

notes_file=""
draft_flag=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes-file)
            notes_file="$2"
            shift 2
            ;;
        --draft)
            draft_flag=(--draft)
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Commit or stash changes first." >&2
    exit 1
fi

current_branch="$(git branch --show-current)"
if [[ "$current_branch" != "main" ]]; then
    echo "Not on main (currently on $current_branch)." >&2
    exit 1
fi

git fetch origin main --quiet
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    echo "Local main is not up to date with origin/main. Pull first." >&2
    exit 1
fi

tag="v$version"
if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "Tag $tag already exists." >&2
    exit 1
fi

sign_identity=""
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    sign_identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/^ *[0-9]+\) [A-F0-9]+ "(.+)"$/\1/')"
    echo "Signing identity: $sign_identity"
else
    echo "No Developer ID Application identity found — building unsigned. See RELEASE.md."
fi

notary_profile=""
if [[ -n "$sign_identity" ]] && xcrun notarytool history --keychain-profile session-hawk-notary >/dev/null 2>&1; then
    notary_profile="session-hawk-notary"
    echo "Notary profile: $notary_profile"
elif [[ -n "$sign_identity" ]]; then
    echo "Signing identity found but no notarytool profile 'session-hawk-notary' — will sign without notarizing."
fi

echo
echo "Building Session Hawk v$version..."
SESSION_HAWK_VERSION="$version" \
SESSION_HAWK_SIGN_IDENTITY="$sign_identity" \
SESSION_HAWK_NOTARY_PROFILE="$notary_profile" \
zsh scripts/package-app.sh

dmg_path="output/package/Session Hawk.dmg"
zip_path="output/package/Session Hawk.zip"
if [[ ! -f "$dmg_path" ]]; then
    echo "Expected DMG not found at $dmg_path" >&2
    exit 1
fi

echo
echo "Creating GitHub release $tag..."
notes_args=(--generate-notes)
if [[ -n "$notes_file" ]]; then
    notes_args=(--notes-file "$notes_file")
fi

gh release create "$tag" "$dmg_path" "$zip_path" \
    --repo jgalea/session-hawk \
    --title "Session Hawk $tag" \
    "${notes_args[@]}" \
    "${draft_flag[@]}"

echo
echo "Verifying release assets are downloadable..."
dmg_url="$(gh release view "$tag" --repo jgalea/session-hawk --json assets \
    --jq '.assets[] | select(.name | endswith(".dmg")) | .url')"
status="$(curl -s -o /dev/null -w "%{http_code}" -L "$dmg_url")"
if [[ "$status" != "200" ]]; then
    echo "Warning: DMG asset returned HTTP $status" >&2
else
    echo "DMG verified downloadable (HTTP 200)."
fi

echo
echo "Done: https://github.com/jgalea/session-hawk/releases/tag/$tag"
