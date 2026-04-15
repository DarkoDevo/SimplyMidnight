const { app, BrowserWindow, ipcMain } = require("electron");
const path = require("path");

const isDev = Boolean(process.env.VITE_DEV_SERVER_URL);

let mainWindow = null;
let mirrorWindow = null;

function loadWindow(window, mirrorMode = false) {
  if (isDev) {
    const url = new URL(process.env.VITE_DEV_SERVER_URL);
    if (mirrorMode) {
      url.searchParams.set("mirror", "1");
    }
    window.loadURL(url.toString());
  } else if (mirrorMode) {
    window.loadFile(path.join(__dirname, "..", "dist", "index.html"), {
      search: "mirror=1"
    });
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
