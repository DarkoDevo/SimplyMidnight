const { app, BrowserWindow, ipcMain, desktopCapturer, screen, session } = require("electron");
const path = require("path");

const isDev = Boolean(process.env.VITE_DEV_SERVER_URL);

let mainWindow = null;
let mirrorWindow = null;
let selectedCaptureSourceId = null;
let identifyWindows = [];
let identifyTimeout = null;

function syncMainWindowTopmost() {
  if (!mainWindow || mainWindow.isDestroyed()) {
    return;
  }

  if (mainWindow.isFocused()) {
    mainWindow.setAlwaysOnTop(true, "floating");
  } else {
    mainWindow.setAlwaysOnTop(false);
  }
}

function loadWindow(window, mirrorMode = false) {
  if (isDev) {
    const baseUrl = process.env.VITE_DEV_SERVER_URL.replace(/\/$/, "");
    window.loadURL(mirrorMode ? `${baseUrl}/mirror.html` : process.env.VITE_DEV_SERVER_URL);
  } else if (mirrorMode) {
    window.loadFile(path.join(__dirname, "..", "dist", "mirror.html"));
  } else {
    window.loadFile(path.join(__dirname, "..", "dist", "index.html"));
  }
}

function clearIdentifyWindows() {
  if (identifyTimeout) {
    clearTimeout(identifyTimeout);
    identifyTimeout = null;
  }

  for (const window of identifyWindows) {
    if (window && !window.isDestroyed()) {
      window.close();
    }
  }

  identifyWindows = [];
}

function showDisplayIdentifiers(durationMs = 2500) {
  clearIdentifyWindows();

  const displays = screen.getAllDisplays();
  const primaryDisplay = screen.getPrimaryDisplay();

  identifyWindows = displays.map((display, index) => {
    const overlay = new BrowserWindow({
      x: display.bounds.x,
      y: display.bounds.y,
      width: display.bounds.width,
      height: display.bounds.height,
      frame: false,
      transparent: true,
      resizable: false,
      movable: false,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      focusable: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      backgroundColor: "#00000000",
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false
      }
    });

    overlay.setIgnoreMouseEvents(true, { forward: true });
    overlay.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });

    const label = `Display ${index + 1}${display.id === primaryDisplay.id ? " | primary" : ""}`;
    const details = `${display.bounds.width}x${display.bounds.height} @ ${display.bounds.x},${display.bounds.y}`;
    const html = `
      <!doctype html>
      <html>
        <body style="
          margin: 0;
          width: 100vw;
          height: 100vh;
          display: grid;
          place-items: center;
          background: rgba(2, 6, 12, 0.12);
          overflow: hidden;
          font-family: Arial, sans-serif;
          color: white;
        ">
          <div style="
            min-width: 320px;
            padding: 24px 32px;
            border: 2px solid rgba(141, 199, 255, 0.9);
            border-radius: 18px;
            background: rgba(5, 10, 20, 0.88);
            box-shadow: 0 24px 60px rgba(0, 0, 0, 0.45);
            text-align: center;
          ">
            <div style="font-size: 52px; font-weight: 700; color: #8dc7ff;">${label}</div>
            <div style="margin-top: 10px; font-size: 22px; color: #d8e7ff;">${details}</div>
          </div>
        </body>
      </html>
    `;

    overlay.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);
    return overlay;
  });

  identifyTimeout = setTimeout(() => {
    clearIdentifyWindows();
  }, Math.max(Number(durationMs) || 2500, 1000));
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 980,
    height: 760,
    minWidth: 840,
    minHeight: 640,
    title: "SimplyMidnight Overlay",
    alwaysOnTop: false,
    autoHideMenuBar: true,
    backgroundColor: "#0b0d12",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  mainWindow.setContentProtection(true);

  loadWindow(mainWindow, false);
  mainWindow.on("focus", syncMainWindowTopmost);
  mainWindow.on("blur", syncMainWindowTopmost);
  syncMainWindowTopmost();
}

function ensureMirrorWindow() {
  if (mirrorWindow && !mirrorWindow.isDestroyed()) {
    return mirrorWindow;
  }

  mirrorWindow = new BrowserWindow({
    width: 708,
    height: 168,
    minWidth: 120,
    minHeight: 30,
    frame: false,
    transparent: false,
    title: "SimplyMidnight Mirror",
    alwaysOnTop: true,
    autoHideMenuBar: true,
    resizable: true,
    backgroundColor: "#010204",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  mirrorWindow.setMovable(true);
  mirrorWindow.setContentProtection(true);

  loadWindow(mirrorWindow, true);
  mirrorWindow.on("closed", () => {
    mirrorWindow = null;
  });
  return mirrorWindow;
}

ipcMain.handle("overlay:set-always-on-top", (_, value) => {
  if (mirrorWindow && !mirrorWindow.isDestroyed()) {
    mirrorWindow.setAlwaysOnTop(Boolean(value));
  }
  return true;
});

ipcMain.handle("overlay:list-capture-sources", async () => {
  const displays = screen.getAllDisplays();
  const primaryDisplay = screen.getPrimaryDisplay();
  const displayMap = new Map(
    displays.map((display) => [
      String(display.id),
      {
        id: display.id,
        bounds: display.bounds,
        size: display.size,
        scaleFactor: display.scaleFactor,
        rotation: display.rotation,
        primary: display.id === primaryDisplay.id
      }
    ])
  );

  const sources = await desktopCapturer.getSources({
    types: ["window", "screen"],
    thumbnailSize: {
      width: 320,
      height: 180
    }
  });

  return sources.map((source) => ({
    id: source.id,
    name: source.name,
    displayId: source.display_id || "",
    kind: source.id.startsWith("screen:") ? "screen" : "window",
    display: source.display_id ? displayMap.get(String(source.display_id)) || null : null,
    thumbnailDataUrl: source.thumbnail && !source.thumbnail.isEmpty() ? source.thumbnail.toDataURL() : null
  }));
});

ipcMain.handle("overlay:identify-displays", () => {
  showDisplayIdentifiers();
  return true;
});

ipcMain.handle("overlay:prepare-clean-capture", async () => {
  if (!mainWindow || mainWindow.isDestroyed()) {
    return false;
  }

  mainWindow.setAlwaysOnTop(false);
  mainWindow.minimize();

  await new Promise((resolve) => {
    setTimeout(resolve, 350);
  });

  return true;
});

ipcMain.handle("overlay:set-selected-source", (_, sourceId) => {
  selectedCaptureSourceId = sourceId ? String(sourceId) : null;
  return true;
});

ipcMain.handle("overlay:set-mirror-enabled", (_, value) => {
  if (value) {
    ensureMirrorWindow();
  } else if (mirrorWindow && !mirrorWindow.isDestroyed()) {
    mirrorWindow.close();
    mirrorWindow = null;
  }
  return true;
});

ipcMain.handle("overlay:set-mirror-bounds", (_, bounds) => {
  if (!mirrorWindow || mirrorWindow.isDestroyed()) {
    return false;
  }

  const width = Math.max(Math.floor(Number(bounds && bounds.width) || 1), 1);
  const height = Math.max(Math.floor(Number(bounds && bounds.height) || 1), 1);
  mirrorWindow.setContentSize(width, height);
  return true;
});

ipcMain.handle("overlay:send-mirror-frame", (_, payload) => {
  if (!mirrorWindow || mirrorWindow.isDestroyed()) {
    return false;
  }

  mirrorWindow.webContents.send("overlay:mirror-frame", payload);
  return true;
});

ipcMain.handle("overlay:get-meta", () => {
  return {
    version: app.getVersion()
  };
});

app.whenReady().then(() => {
  session.defaultSession.setDisplayMediaRequestHandler(async (_, callback) => {
    const sources = await desktopCapturer.getSources({
      types: ["window", "screen"],
      thumbnailSize: {
        width: 1,
        height: 1
      }
    });

    let selectedSource = null
    if (selectedCaptureSourceId) {
      selectedSource = sources.find((source) => source.id === selectedCaptureSourceId) || null;
    }

    if (!selectedSource) {
      selectedSource = sources.find((source) => source.id.startsWith("screen:")) || sources[0] || null;
    }

    callback({
      video: selectedSource || undefined,
      audio: false
    });
  }, { useSystemPicker: false });

  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("before-quit", () => {
  clearIdentifyWindows();
});
