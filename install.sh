#!/bin/sh
# Mapaché — one-line install
#   curl -fsSL https://raw.githubusercontent.com/doc-rogers/get-mapache/main/install.sh | sh
set -eu

REPO="${MAPACHE_REPO:-https://github.com/doc-rogers/Mapache.git}"
REF="${MAPACHE_REF:-heel-2026-08-12}"
HOME_DIR="${MAPACHE_HOME:-$HOME/.mapache}"
APPS_DIR="${MAPACHE_APPS:-$HOME/Applications}"
BIN_DIR="${MAPACHE_BIN:-$HOME/.local/bin}"

say() { printf 'mapache: %s\n' "$*"; }
die() { printf 'mapache: %s\n' "$*" >&2; exit 1; }

os="$(uname -s)"
[ "$os" = Darwin ] || die "this installer is for macOS (got $os)"

PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
export PATH
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=advice.detachedHead
export GIT_CONFIG_VALUE_0=false

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd git; then
  die "need git. Install Xcode CLT: xcode-select --install"
fi

if ! need_cmd node || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)'; then
  if need_cmd brew; then
    say "installing Node 22 via Homebrew"
    brew install node@22
    brew link --force --overwrite node@22 >/dev/null 2>&1 || true
    PATH="$(brew --prefix node@22)/bin:$PATH"
    export PATH
  else
    die "need Node 20+. Install from https://nodejs.org then re-run this curl."
  fi
fi

say "node $(node -v) · npm $(npm -v)"
say "pin $REF → $HOME_DIR"

mkdir -p "$HOME_DIR" "$APPS_DIR" "$BIN_DIR"

if [ -d "$HOME_DIR/.git" ]; then
  say "updating existing checkout"
  git -C "$HOME_DIR" fetch --depth 1 origin "refs/tags/$REF:refs/tags/$REF" 2>/dev/null \
    || git -C "$HOME_DIR" fetch --depth 1 origin "$REF"
  git -C "$HOME_DIR" checkout -qf "$REF"
else
  rm -rf "$HOME_DIR"
  git clone --depth 1 --branch "$REF" "$REPO" "$HOME_DIR"
fi

# Vite / Electron live in devDependencies — do not --omit=dev
say "installing app deps (2–4 min, deprecation warnings are noise)"
( cd "$HOME_DIR" && npm install --no-fund --no-audit --loglevel=error --foreground-scripts )
say "downloading Electron (~120MB) — this is the long quiet bit"
( cd "$HOME_DIR/native/macos" && npm install --no-fund --no-audit --loglevel=info --foreground-scripts )

cat > "$BIN_DIR/mapache" <<EOF
#!/bin/sh
set -eu
export MAPACHE_HOME="${HOME_DIR}"
export PATH="/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH"
cd "\$MAPACHE_HOME"
if ! curl -sf -o /dev/null --max-time 1 http://127.0.0.1:8080/; then
  nohup npm run dev >>"\$MAPACHE_HOME/mapache.log" 2>&1 &
  echo \$! > "\$MAPACHE_HOME/mapache.pid"
  i=0
  while [ \$i -lt 120 ]; do
    curl -sf -o /dev/null --max-time 1 http://127.0.0.1:8080/ && break
    i=\$((i + 1))
    sleep 0.5
  done
fi
cd "\$MAPACHE_HOME/native/macos"
exec npx electron .
EOF
chmod +x "$BIN_DIR/mapache"

APP="$APPS_DIR/Mapaché.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$HOME_DIR/native/macos/icon.png" "$APP/Contents/Resources/icon.png" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mapaché</string>
  <key>CFBundleDisplayName</key><string>Mapaché</string>
  <key>CFBundleIdentifier</key><string>life.trashpanda.mapache</string>
  <key>CFBundleVersion</key><string>0.4.0</string>
  <key>CFBundleShortVersionString</key><string>0.4.0</string>
  <key>CFBundleExecutable</key><string>Mapache</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
cat > "$APP/Contents/MacOS/Mapache" <<EOF
#!/bin/sh
export PATH="${BIN_DIR}:/opt/homebrew/bin:/usr/local/bin:\$PATH"
exec "${BIN_DIR}/mapache"
EOF
chmod +x "$APP/Contents/MacOS/Mapache"
xattr -cr "$APP" 2>/dev/null || true

say "installed"
say "  app  $APP"
say "  cli  $BIN_DIR/mapache"
say "  src  $HOME_DIR  ($REF)"

if [ "${MAPACHE_NO_OPEN:-}" != "1" ]; then
  say "opening Mapaché"
  open "$APP" || "$BIN_DIR/mapache" &
fi
