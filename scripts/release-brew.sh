#!/usr/bin/env bash
# release-brew.sh — cut a kb release to the Homebrew tap.
#
# Usage:
#   scripts/release-brew.sh 0.2.0
#
# What it does (in order, stops on any failure):
#   1. Verifies tag v<version> exists on origin.
#   2. Downloads the release tarball, computes sha256.
#   3. Updates packaging/homebrew/Formula/kb.rb in-repo (version + url + sha).
#   4. Finds the tap clone, verifies remote, copies formula.
#   5. Commits + pushes in tap. Commits (NOT pushes) in main repo.
#
# Requires: git, curl, shasum. macOS sed (BSD).
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: $0 <version>   (e.g. $0 0.2.0)"
  exit 1
fi
VERSION="${VERSION#v}"   # strip leading v if given

REPO_ROOT="$(git rev-parse --show-toplevel)"
FORMULA_PATH="$REPO_ROOT/packaging/homebrew/Formula/kb.rb"
[ -f "$FORMULA_PATH" ] || { echo "formula not found: $FORMULA_PATH"; exit 1; }

say() { printf "\033[1;36m[release]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[release: fail]\033[0m %s\n" "$*" >&2; exit 1; }

# 1. Verify the tag is on origin
say "verifying origin has tag v${VERSION}"
git fetch --tags origin >/dev/null 2>&1
git ls-remote --tags origin "refs/tags/v${VERSION}" | grep -q "v${VERSION}$" \
  || die "tag v${VERSION} not found on origin. Tag and push it first: git tag v${VERSION} && git push origin v${VERSION}"

# 2. Compute sha256 of the release tarball
TARBALL_URL="https://github.com/nalediym/knowledge-base/archive/refs/tags/v${VERSION}.tar.gz"
say "computing sha256 of ${TARBALL_URL}"
SHA=$(curl -fsSL "$TARBALL_URL" | shasum -a 256 | awk '{print $1}')
[ -n "$SHA" ] && [ "${#SHA}" -eq 64 ] || die "sha256 computation failed"
say "sha256: ${SHA}"

# 3. Update the in-repo formula
say "patching $FORMULA_PATH"
sed -i '' \
  -e "s|refs/tags/v[0-9][0-9.]*\.tar\.gz|refs/tags/v${VERSION}.tar.gz|" \
  -e "s|^\(  version \)\"[^\"]*\"|\1\"${VERSION}\"|" \
  -e "s|^\(  sha256 \)\"[^\"]*\"|\1\"${SHA}\"|" \
  "$FORMULA_PATH"

# Verify the edit took
grep -q "version \"${VERSION}\"" "$FORMULA_PATH" || die "version substitution failed"
grep -q "sha256 \"${SHA}\""       "$FORMULA_PATH" || die "sha256 substitution failed"
grep -q "REPLACE_WITH_SHA256"     "$FORMULA_PATH" && die "placeholder still present — refusing to ship"
git -C "$REPO_ROOT" --no-pager diff -- packaging/homebrew/Formula/kb.rb || true

# 4. Find the tap clone
for candidate in \
  "$HOME/Projects/homebrew-kb" \
  "$HOME/homebrew-kb" \
  "$HOME/src/homebrew-kb" \
  "$HOME/code/homebrew-kb"
do
  if [ -d "$candidate/.git" ] && [ -f "$candidate/Formula/kb.rb" ]; then
    TAP="$candidate"; break
  fi
done
if [ -z "${TAP:-}" ]; then
  read -rp "Path to your nalediym/homebrew-kb clone: " TAP
  [ -d "$TAP/.git" ] && [ -f "$TAP/Formula/kb.rb" ] || die "not a valid tap checkout: $TAP"
fi

remote=$(git -C "$TAP" remote get-url origin 2>/dev/null || true)
case "$remote" in
  *nalediym/homebrew-kb*) ;;
  *) die "tap origin is '$remote' — not nalediym/homebrew-kb" ;;
esac
say "tap: $TAP"

# 5. Copy formula into tap, commit, push
cp "$FORMULA_PATH" "$TAP/Formula/kb.rb"
if git -C "$TAP" diff --quiet -- Formula/kb.rb; then
  say "tap already at v${VERSION}"
else
  git -C "$TAP" commit -am "kb ${VERSION}"
  git -C "$TAP" push
  say "tap pushed"
fi

# 6. Commit the in-repo formula (don't push — let the human push the main repo)
if ! git -C "$REPO_ROOT" diff --quiet -- packaging/homebrew/Formula/kb.rb; then
  git -C "$REPO_ROOT" commit -am "kb ${VERSION}: bump formula sha256"
  say "committed formula bump in main repo (not pushed — push when ready)"
fi

cat <<EOF

Release v${VERSION} wired up:
  tap formula pushed
  main formula committed locally ($(git -C "$REPO_ROOT" rev-parse --short HEAD))

Verify:
  brew update
  brew install nalediym/kb/kb
  kb version

Push the main repo when ready:
  git push origin main
EOF
