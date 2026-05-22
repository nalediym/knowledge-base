#!/usr/bin/env bash
# kb — one-shot installer for the Bun/TS port. Idempotent.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nalediym/knowledge-base/main/scripts/install.sh | bash
#   KB_REF=v0.3.0 curl -fsSL ... | bash   # pin to a tag
#   KB_PREFIX=~/.local curl -fsSL ... | bash   # override install prefix
set -euo pipefail

REPO="${KB_REPO:-https://github.com/nalediym/knowledge-base.git}"
REF="${KB_REF:-main}"
SHARE_DIR="${KB_SHARE:-$HOME/.local/share/kb}"
BIN_DIR="${KB_BIN:-$HOME/.local/bin}"

say() { printf "\033[1;36m[kb]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[kb: fail]\033[0m %s\n" "$*" >&2; exit 1; }

# 1. Bun runtime — install if missing.
if command -v bun >/dev/null 2>&1; then
  say "using existing bun: $(bun --version)"
else
  say "installing bun"
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi

command -v bun >/dev/null 2>&1 || die "bun not on PATH after install — open a new shell and re-run"
command -v git >/dev/null 2>&1 || die "git is required"

# 2. Fetch / update the repo.
mkdir -p "$(dirname "$SHARE_DIR")"
if [ -d "$SHARE_DIR/.git" ]; then
  say "updating $SHARE_DIR"
  git -C "$SHARE_DIR" fetch --tags --depth 50 origin
  git -C "$SHARE_DIR" checkout -q "$REF"
  git -C "$SHARE_DIR" reset -q --hard "$REF" 2>/dev/null || true
else
  say "cloning into $SHARE_DIR"
  git clone --depth 50 "$REPO" "$SHARE_DIR"
  git -C "$SHARE_DIR" checkout -q "$REF"
fi

# 3. Install workspace deps.
say "installing workspace deps"
(cd "$SHARE_DIR" && bun install --frozen-lockfile 2>/dev/null || bun install)

# 4. Drop a launcher onto PATH.
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/kb" <<EOF
#!/usr/bin/env bash
exec bun "$SHARE_DIR/packages/cli/src/bin.ts" "\$@"
EOF
chmod +x "$BIN_DIR/kb"
say "wrote $BIN_DIR/kb -> bun $SHARE_DIR/packages/cli/src/bin.ts"

# 5. PATH sanity check.
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "note: $BIN_DIR is not on PATH. add this to your shell rc:"
     printf '\n  export PATH="%s:$PATH"\n\n' "$BIN_DIR" ;;
esac

# 6. Smoke test.
"$BIN_DIR/kb" version

cat <<EOF

kb installed.
  launcher : $BIN_DIR/kb
  repo     : $SHARE_DIR ($(git -C "$SHARE_DIR" rev-parse --short HEAD))

Next:
  kb init .        # in any project
  kb help          # full command list
EOF
