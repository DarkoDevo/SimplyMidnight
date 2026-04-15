const { app, BrowserWindow, ipcMain, desktopCapturer, screen, session } = require("electron");
const path = require("path");

const isDev = Boolean(process.env.VITE_DEV_SERVER_URL);

let mainWindow = null;
let mirrorWindow = null;
let selectedCaptureSourceId = null;

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

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 980,
    height: 760,
    minWidth: 840,
    minHeight: 640,
    title: "SimplyMidnight Overlay",
    alwaysOnTop: true,
    autoHideMenuBar: true,
    backgroundColor: "#0b0d12",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  loadWindow(mainWindow, false);
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

  loadWindow(mirrorWindow, true);
  mirrorWindow.on("closed", () => {
    mirrorWindow = null;
  });
  return mirrorWindow;
}

ipcMain.handle("overlay:set-always-on-top", (_, value) => {
  if (mainWindow) {
    mainWindow.setAlwaysOnTop(Boolean(value));
  }
  if (mirrorWindow && !mirrorWindow.isDestroyed()) {
    mirrorWindow.setAlwaysOnTop(Boolean(value));
  }
  return true;
});

ipcMain.handle("overlay:list-capture-sources", async () => {
  const displays = screen.getAllDisplays();
  const displayMap = new Map(
    displays.map((display) => [
      String(display.id),
      {
        id: display.id,
        bounds: display.bounds,
        size: display.size,
        scaleFactor: display.scaleFactor,
        rotation: display.rotation,
        primary: display.bounds.x === 0 && display.bounds.y === 0
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
