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
# npm 11 allow-scripts can skip electron's postinstall — force the binary
if [ ! -d "$HOME_DIR/native/macos/node_modules/electron/dist/Electron.app" ]; then
  say "fetching Electron binary"
  ( cd "$HOME_DIR/native/macos" && npm approve-scripts electron 2>/dev/null || true )
  ( cd "$HOME_DIR/native/macos/node_modules/electron" && node install.js )
fi

# Real Mac icon so Launchpad isn't a generic target
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$HOME_DIR/native/macos/Mapache.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  SRC="$HOME_DIR/native/macos/icon.png"
  sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$HOME_DIR/native/macos/icon.icns" 2>/dev/null || true
  rm -rf "$ICONSET"
fi

NODE_BIN="$(command -v node)"
NPM_BIN="$(command -v npm)"
ELECTRON_BIN="$HOME_DIR/native/macos/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron"

# Don't let stock Electron.app show up in Launchpad
STOCK_PLIST="$HOME_DIR/native/macos/node_modules/electron/dist/Electron.app/Contents/Info.plist"
if [ -f "$STOCK_PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$STOCK_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$STOCK_PLIST" 2>/dev/null \
    || true
fi

cat > "$BIN_DIR/mapache" <<EOF
#!/bin/sh
set -eu
export MAPACHE_HOME="${HOME_DIR}"
export PATH="$(dirname "$NODE_BIN"):/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$PATH"
cd "\$MAPACHE_HOME"
if ! curl -sf -o /dev/null --max-time 1 http://127.0.0.1:8080/; then
  nohup "${NPM_BIN}" run dev >>"\$MAPACHE_HOME/mapache.log" 2>&1 &
  echo \$! > "\$MAPACHE_HOME/mapache.pid"
  i=0
  while [ \$i -lt 120 ]; do
    curl -sf -o /dev/null --max-time 1 http://127.0.0.1:8080/ && break
    i=\$((i + 1))
    sleep 0.5
  done
fi
exec "${ELECTRON_BIN}" "\$MAPACHE_HOME/native/macos"
EOF
chmod +x "$BIN_DIR/mapache"

APP="$APPS_DIR/Mapaché.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$HOME_DIR/native/macos/icon.png" "$APP/Contents/Resources/icon.png" 2>/dev/null || true
if [ -f "$HOME_DIR/native/macos/icon.icns" ]; then
  cp "$HOME_DIR/native/macos/icon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
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
  <key>CFBundleIconFile</key><string>AppIcon</string>
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

# Launchpad / Spotlight look here first
if [ -w /Applications ]; then
  rm -rf "/Applications/Mapaché.app"
  ln -sfn "$APP" "/Applications/Mapaché.app" 2>/dev/null || true
fi

say "installed"
say "  app  $APP"
say "  cli  $BIN_DIR/mapache"
say "  src  $HOME_DIR  ($REF)"

if [ "${MAPACHE_NO_OPEN:-}" != "1" ]; then
  say "opening Mapaché"
  open "$APP" || "$BIN_DIR/mapache" &
fi
