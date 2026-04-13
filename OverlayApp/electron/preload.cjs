const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("simplyMidnightApi", {
  setAlwaysOnTop(value) {
    return ipcRenderer.invoke("overlay:set-always-on-top", value);
  },
  getMeta() {
    return ipcRenderer.invoke("overlay:get-meta");
  }
});
