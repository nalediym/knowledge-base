# Homebrew tap for `kb`

The formula here is the source of truth. To publish:

1. **Create the tap repo** (one-time, on GitHub):
   ```bash
   gh repo create nalediym/homebrew-kb --public --description "Homebrew tap for kb"
   ```

2. **Seed it with the formula**:
   ```bash
   TAP=~/Projects/homebrew-kb
   git clone https://github.com/nalediym/homebrew-kb.git "$TAP"
   mkdir -p "$TAP/Formula"
   cp packaging/homebrew/Formula/kb.rb "$TAP/Formula/kb.rb"
   ```

3. **At each release tag**, update `url`, `version`, and `sha256`:
   ```bash
   VERSION=0.1.0
   SHA=$(curl -sL "https://github.com/nalediym/knowledge-base/archive/refs/tags/v${VERSION}.tar.gz" | shasum -a 256 | awk '{print $1}')
   sed -i '' \
     -e "s|refs/tags/v[0-9.]*|refs/tags/v${VERSION}|" \
     -e "s|version \".*\"|version \"${VERSION}\"|" \
     -e "s|sha256 \".*\"|sha256 \"${SHA}\"|" \
     "$TAP/Formula/kb.rb"
   (cd "$TAP" && git commit -am "kb ${VERSION}" && git push)
   ```

4. **User install**:
   ```bash
   brew install nalediym/kb/kb
   ```
   or, explicitly:
   ```bash
   brew tap nalediym/kb
   brew install kb
   ```

## Notes

- This is a **source formula** (Elixir/Erlang declared as deps, compiled at install time). Users get a fresh build from the tagged tarball. Build time: ~30 seconds once deps are cached.
- A future bottled formula (prebuilt per-platform binaries) drops the Elixir/Erlang deps and skips the `mix` steps — that's a follow-up when Burrito or similar is introduced.
- `head` stanza lets power users run `brew install --HEAD nalediym/kb/kb` against `main` for bleeding-edge.
