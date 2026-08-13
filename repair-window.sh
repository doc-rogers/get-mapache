#!/bin/sh
# Repair Mapaché Mac window: drag to move + resize-safe chrome.
# Does not need the private repo — safe when Tailscale blocks GitHub.
#   curl -fsSL https://raw.githubusercontent.com/doc-rogers/get-mapache/main/repair-window.sh | sh
set -eu
HOME_DIR="${MAPACHE_HOME:-$HOME/.mapache}"
[ -d "$HOME_DIR" ] || { echo "mapache: no $HOME_DIR — install first"; exit 1; }

say() { printf 'mapache: %s\n' "$*"; }

mkdir -p "$HOME_DIR/native/macos"

# --- Electron shell ---
cat > "$HOME_DIR/native/macos/main.cjs" <<'ENDMAIN'
"use strict";

const { app, BrowserWindow, shell, Menu } = require("electron");
const { spawn } = require("node:child_process");
const http = require("node:http");
const path = require("node:path");
const fs = require("node:fs");

const HOME = process.env.MAPACHE_HOME || path.resolve(__dirname, "../..");
const START_URL = process.env.MAPACHE_URL || "http://127.0.0.1:8080/";

function ping(url) {
  return new Promise((resolve) => {
    const req = http.get(url, (res) => {
      res.resume();
      resolve(res.statusCode && res.statusCode < 500);
    });
    req.on("error", () => resolve(false));
    req.setTimeout(1500, () => {
      req.destroy();
      resolve(false);
    });
  });
}

function startLocalServer() {
  const log = fs.openSync(path.join(HOME, "mapache.log"), "a");
  const child = spawn("npm", ["run", "dev"], {
    cwd: HOME,
    detached: true,
    stdio: ["ignore", log, log],
    env: { ...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.PATH || ""}` },
  });
  child.unref();
  try {
    fs.writeFileSync(path.join(HOME, "mapache.pid"), String(child.pid));
  } catch {
    /* ignore */
  }
}

async function ensureServer() {
  if (process.env.MAPACHE_URL) return;
  if (await ping(START_URL)) return;
  startLocalServer();
  for (let i = 0; i < 80; i += 1) {
    if (await ping(START_URL)) return;
    await new Promise((r) => setTimeout(r, 400));
  }
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 760,
    minHeight: 520,
    title: "Mapaché",
    backgroundColor: "#0a1423",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 16, y: 16 },
    fullscreenable: true,
    maximizable: true,
    movable: true,
    resizable: true,
    hasShadow: true,
    roundedCorners: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  win.loadURL(START_URL).catch((err) => {
    win.loadURL(
      "data:text/html;charset=utf-8," +
        encodeURIComponent("<p style='padding:2rem;font:15px sans-serif'>Mapaché isn’t reachable</p>"),
    );
  });

  win.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });
}

app.setName("Mapaché");

app.whenReady().then(async () => {
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      { role: "appMenu" },
      { role: "editMenu" },
      { role: "viewMenu" },
      { role: "windowMenu" },
    ]),
  );
  await ensureServer();
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
ENDMAIN

cat > "$HOME_DIR/native/macos/preload.cjs" <<'ENDPRE'
"use strict";
try {
  document.documentElement.dataset.mapacheNative = "macos";
} catch {
  /* ignore */
}
window.addEventListener("DOMContentLoaded", () => {
  document.documentElement.dataset.mapacheNative = "macos";
});
ENDPRE

# --- Drag CSS (append once) ---
CSS="$HOME_DIR/src/styles.css"
if [ -f "$CSS" ] && ! grep -q "desk-drag" "$CSS"; then
  cat >> "$CSS" <<'ENDCSS'

/* Native Mac: drag strip so the hidden titlebar can move */
html[data-mapache-native="macos"] .desk {
  position: relative;
  padding-top: 2.2rem;
}
html[data-mapache-native="macos"] .desk-drag {
  position: absolute;
  top: 0;
  right: 0;
  left: 4.75rem;
  height: 2.2rem;
  z-index: 30;
  -webkit-app-region: drag;
}
html[data-mapache-native="macos"] .desk-nav-brand {
  -webkit-app-region: drag;
}
html[data-mapache-native="macos"] button,
html[data-mapache-native="macos"] a,
html[data-mapache-native="macos"] input,
html[data-mapache-native="macos"] select {
  -webkit-app-region: no-drag;
}
ENDCSS
  say "patched styles.css"
fi

# --- desk-drag node (once) ---
SHELL="$HOME_DIR/src/components/mapache/stage-shell.tsx"
if [ -f "$SHELL" ] && ! grep -q 'desk-drag' "$SHELL"; then
  python3 - <<'PY'
from pathlib import Path
p = Path.home() / ".mapache/src/components/mapache/stage-shell.tsx"
s = p.read_text()
old = """      >
        <aside className="desk-nav" aria-label="Index">"""
new = """      >
        <div className="desk-drag" aria-hidden />
        <aside className="desk-nav" aria-label="Index">"""
if old in s:
    p.write_text(s.replace(old, new, 1))
    print("patched stage-shell")
else:
    print("stage-shell marker not found — skip")
PY
fi

say "window repair written"
say "restarting"
if [ -f "$HOME_DIR/mapache.pid" ]; then
  kill "$(cat "$HOME_DIR/mapache.pid")" 2>/dev/null || true
fi
pkill -f "electron.*native/macos" 2>/dev/null || true
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
if [ -x "$HOME/.local/bin/mapache" ]; then
  exec "$HOME/.local/bin/mapache"
fi
say "run: ~/.local/bin/mapache"
