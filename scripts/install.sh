#!/usr/bin/env bash
# kb — one-shot installer. Idempotent.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nalediym/knowledge-base/main/scripts/install.sh | bash
#   KB_REF=v0.1.0 curl -fsSL ... | bash   # pin to a tag
#   KB_PREFIX=~/.local curl -fsSL ... | bash   # override install prefix
set -euo pipefail

REPO="${KB_REPO:-https://github.com/nalediym/knowledge-base.git}"
REF="${KB_REF:-main}"
SHARE_DIR="${KB_SHARE:-$HOME/.local/share/kb}"
BIN_DIR="${KB_BIN:-$HOME/.local/bin}"
ELIXIR_VERSION="${KB_ELIXIR:-1.17.3-otp-27}"

say() { printf "\033[1;36m[kb]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[kb: fail]\033[0m %s\n" "$*" >&2; exit 1; }

# 1. Elixir toolchain — use whatever the user has, else install via mise.
if command -v elixir >/dev/null 2>&1; then
  say "using existing elixir: $(elixir --version | head -n1)"
else
  if ! command -v mise >/dev/null 2>&1; then
    say "installing mise (for elixir/erlang)"
    curl -fsSL https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
  say "installing elixir ${ELIXIR_VERSION} via mise"
  mise use -g "elixir@${ELIXIR_VERSION}"
  eval "$(mise activate bash)" 2>/dev/null || true
fi

command -v elixir >/dev/null 2>&1 || die "elixir not on PATH after install — open a new shell and re-run"
command -v git    >/dev/null 2>&1 || die "git is required"

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

# 3. Build the escript.
say "building escript"
cd "$SHARE_DIR/cli"
mix local.hex    --force --if-missing >/dev/null 2>&1 || mix local.hex    --force
mix local.rebar  --force --if-missing >/dev/null 2>&1 || mix local.rebar  --force
mix deps.get
MIX_ENV=prod mix escript.build

[ -x ./kb ] || die "escript build did not produce ./kb"

# 4. Symlink onto PATH.
mkdir -p "$BIN_DIR"
ln -sf "$SHARE_DIR/cli/kb" "$BIN_DIR/kb"
say "linked $BIN_DIR/kb -> $SHARE_DIR/cli/kb"

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
  binary : $BIN_DIR/kb
  repo   : $SHARE_DIR ($(git -C "$SHARE_DIR" rev-parse --short HEAD))

Next:
  kb init .        # in any project
  kb --help        # full command list

FTS5 hybrid retrieval needs to run via Mix (see README for the mix-run command).
EOF
